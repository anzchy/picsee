import AppKit
import os
import PicseeCore
import PicseeApplication
import SwiftUI

/// Window intent is isolated; decode admission and buffers are shared by the pipeline.
@MainActor
final class CanvasWindowController: NSWindowController, NSWindowDelegate {
    private let canvas = CanvasView(frame: .zero)
    private let filesystemLogger = Logger(subsystem: "io.github.anzchy.picsee", category: "filesystem")
    private let pipeline: any ImagePipeline
    private var fileURL: URL?
    private var generation = UUID()
    private var desiredMaximum = 0
    private var decodeProgress = CanvasDecodeProgress()
    private var decoding = false
    private var decodeTask: Task<Void, Never>?
    private let binding = UUID()
    private var currentKey: RenderKey?

    private let inspector = InspectorModel()
    private let router = CommandRouter()
    private var commandEntry: CommandEntry = .key
    private var inspectorHost: NSHostingView<InspectorPlaceholder>!
    var onOpenRequest: (() -> Void)?
    var menuTracking: () -> Bool = { false }

    init(pipeline: any ImagePipeline) {
        self.pipeline = pipeline
        let window = CommandWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Picsee"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        let content = NSView(frame: window.contentView!.bounds)
        content.wantsLayer = true
        canvas.frame = content.bounds
        canvas.autoresizingMask = [.width, .height]
        canvas.focusRingType = .exterior
        canvas.setAccessibilityIdentifier("viewer.canvas")
        content.addSubview(canvas)
        inspectorHost = NSHostingView(rootView: InspectorPlaceholder(model: inspector, route: { [weak self] id in
            self?.route(id, from: .button)
        }, restoreCanvasFocus: { [weak self] in
            self?.window?.makeFirstResponder(self?.canvas)
        }))
        inspectorHost.frame = NSRect(x: content.bounds.width - 272, y: 0, width: 272, height: content.bounds.height)
        inspectorHost.autoresizingMask = [.minXMargin, .height]
        inspectorHost.isHidden = true
        content.addSubview(inspectorHost)
        window.contentView = content
        window.makeFirstResponder(canvas)
        window.preserveResponder = { [weak self] responder in
            guard let self else { return false }
            return responder === self.canvas && self.inspector.state.focus != .canvas
        }
        window.didChangeResponder = { [weak self] in
            guard let self else { return }
            self.inspector.state.updateFocus(self.focusContext)
        }
        window.consumeKey = { [weak self] event in self?.consumePanelKey(event) ?? false }
        canvas.pointerIsOverPanel = { [weak self] in
            guard let self, !self.inspectorHost.isHidden, let window = self.window else { return false }
            return self.inspectorHost.bounds.contains(
                self.inspectorHost.convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
        canvas.onCanvasFocus = { [weak self] in self?.inspector.state.updateFocus(.canvas) }
        canvas.onTab = { [weak self] reverse in
            self?.inspector.state.tab(reverse: reverse)
            self?.applyFocus()
        }
        canvas.onCommand = { [weak self] id in self?.route(id, from: .key) ?? false }
        canvas.onResolutionNeeded = { [weak self] maximum in
            self?.desiredMaximum = maximum
            self?.decodeIfNeeded()
        }
    }

    required init?(coder: NSCoder) { nil }

    func open(_ url: URL) {
        filesystemLogger.notice("Open file=\(url.lastPathComponent, privacy: .private)")
        decodeTask?.cancel()
        decodeTask = nil
        decoding = false
        generation = UUID()
        fileURL = url
        currentKey = nil
        decodeProgress = CanvasDecodeProgress()
        let scale = window?.backingScaleFactor ?? 1
        desiredMaximum = max(1, Int(ceil(max(canvas.bounds.width, canvas.bounds.height) * scale)))
        canvas.beginOpening()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
        decodeIfNeeded()
    }

    func windowWillClose(_ notification: Notification) {
        decodeTask?.cancel()
        decodeTask = nil
        decoding = false
        generation = UUID()
        currentKey = nil
        fileURL = nil
        // The running synchronous decode retains its File Grant until actual completion.
    }

    private func decodeIfNeeded() {
        guard !decoding, let url = fileURL, let maximum = decodeProgress.nextMaximum(desired: desiredMaximum) else { return }
        decoding = true
        let token = PresentationToken(binding: binding, generation: generation)
        let isPreview = !decodeProgress.previewCompleted
        decodeTask = Task { [self] in
            let scoped = url.startAccessingSecurityScopedResource()
            // A running cancellation returns only after the synchronous decoder returns.
            // This keeps this consumer's File Grant alive without inventing #8's leases.
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let prepared = try await pipeline.request(for: url, maximumPixelSize: maximum)
                let request = ImageDecodeRequest(fileURL: url, maximumPixelSize: maximum,
                    renderKey: prepared.renderKey, isPreview: isPreview)
                try Task.checkCancellation()
                guard token.generation == generation else { return }
                currentKey = request.renderKey
                let image = try await pipeline.image(for: request)
                try Task.checkCancellation()
                if let key = request.renderKey, let expectedKey = currentKey, let revision = image.revision {
                    let expected = RenderKey(itemID: expectedKey.itemID, revision: revision, maximumPixelSize: maximum)
                    let current = PresentationToken(binding: binding, generation: generation)
                    if current.accepts(key: key, expected: expected, token: token) {
                        try Task.checkCancellation()
                        guard token == PresentationToken(binding: binding, generation: generation) else { return }
                        decodeProgress.completed(image, isPreview: isPreview)
                        canvas.install(image)
                    } else if token == current {
                        canvas.showFailure(); desiredMaximum = 0
                    }
                }
            } catch {
                if token.generation == generation && !Task.isCancelled {
                    canvas.showFailure(); desiredMaximum = 0
                }
            }
            if token.generation == generation {
                decoding = false
                decodeTask = nil
                decodeIfNeeded()
            }
        }
    }
}

// The UI adapter resolves its own window; no global current-image state.
extension CanvasWindowController: WindowCommandTarget {
    var inspectorVisible: Bool { inspector.state.isVisible }
    private var focusContext: FocusContext {
        if window?.firstResponder is NSTextInputClient { return .textInput }
        return window?.firstResponder === canvas ? .canvas : .panel
    }
    func isEnabled(_ command: CommandID) -> Bool {
        switch command {
        case .fit, .actualPixels, .zoomIn, .zoomOut: canvas.hasImage
        case .escape: inspectorVisible && focusContext != .canvas
        case .open, .inspector: true
        default: false
        }
    }
    @discardableResult
    func route(_ command: CommandID, from entry: CommandEntry) -> Bool {
        inspector.state.updateFocus(focusContext)
        let previousEntry = commandEntry
        commandEntry = entry
        defer { commandEntry = previousEntry }
        return router.route(command, from: entry, focus: focusContext, menuTracking: menuTracking(), to: self)
    }
    func perform(_ command: CommandID) {
        switch command {
        case .open: onOpenRequest?()
        case .inspector:
            inspector.state.setVisible(!inspectorVisible)
            inspector.hasImage = canvas.hasImage
            inspectorHost.isHidden = !inspectorVisible
            applyFocus()
        case .escape:
            inspector.state.escape()
            applyFocus()
        default: canvas.apply(command, from: commandEntry)
        }
    }
    private func applyFocus() {
        guard inspector.state.focus == .canvas else { return }
        window?.makeFirstResponder(canvas)
    }
    private func consumePanelKey(_ event: NSEvent) -> Bool {
        guard !menuTracking(), inspectorVisible, focusContext != .canvas else { return false }
        if event.keyCode == 53 { return route(.escape, from: .key) }
        if event.keyCode == 48 && event.modifierFlags.contains(.shift) {
            inspector.state.tab(reverse: true)
            applyFocus()
            return true
        }
        return false
    }
    func windowDidUpdate(_ notification: Notification) {
        if inspector.hasImage != canvas.hasImage { inspector.hasImage = canvas.hasImage }
    }
}
