import AppKit
import os
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
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

    let session: ViewerSession
    private let inspector: InspectorModel
    private let router = CommandRouter()
    private var inspectorHost: NSHostingView<InspectorPlaceholder>!
    var onOpenRequest: (() -> Void)?
    var menuTracking: () -> Bool = { false }

    init(pipeline: any ImagePipeline, preferencesStore: any DisplayPreferencesStore) {
        self.pipeline = pipeline
        session = ViewerSession(preferencesStore: preferencesStore)
        inspector = InspectorModel(session: session)
        let window = CommandWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Picsee"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        session.host = self
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
            return responder === self.canvas && self.session.inspectorFocus.focus != .canvas
        }
        window.didChangeResponder = { [weak self] in
            guard let self else { return }
            // SwiftUI briefly resigns its field editor to the window while clearing FocusState.
            // It is not panel focus; preserving canvas intent lets the field-release callback restore it.
            guard self.window?.firstResponder !== self.window else { return }
            self.session.updateFocus(self.focusContext)
        }
        window.consumeKey = { [weak self] event in self?.consumePanelKey(event) ?? false }
        canvas.pointerIsOverPanel = { [weak self] in
            guard let self, !self.inspectorHost.isHidden, let window = self.window else { return false }
            return self.inspectorHost.bounds.contains(
                self.inspectorHost.convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
        canvas.onCanvasFocus = { [weak self] in self?.session.updateFocus(.canvas) }
        canvas.onTab = { [weak self] reverse in
            self?.session.tab(reverse: reverse)
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
                        if key.itemID == expectedKey.itemID, key.revision != revision,
                           decodeProgress.restartForRevision(request: token, current: current) {
                            currentKey = nil
                            canvas.beginOpening()
                        } else {
                            canvas.showFailure(); desiredMaximum = 0
                        }
                    }
                }
            } catch {
                let current = PresentationToken(binding: binding, generation: generation)
                if token == current && !Task.isCancelled {
                    // This controller supplies valid URLs and positive sizes. invalidRequest
                    // here means the prepared render identity no longer matches the file.
                    if error as? ImageDecodeError == .invalidRequest,
                       decodeProgress.restartForRevision(request: token, current: current) {
                        currentKey = nil
                        canvas.beginOpening()
                    } else {
                        canvas.showFailure(); desiredMaximum = 0
                    }
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

// Native effects only. The Session decides command availability and transitions.
extension CanvasWindowController: ViewerSessionHost {
    var inspectorVisible: Bool { session.inspectorFocus.isVisible }
    var hasImage: Bool { canvas.hasImage }
    private var focusContext: FocusContext {
        if window?.firstResponder is NSTextInputClient { return .textInput }
        return window?.firstResponder === canvas ? .canvas : .panel
    }
    @discardableResult
    func route(_ command: CommandID, from entry: CommandEntry) -> Bool {
        session.updateFocus(focusContext)
        session.setMenuTracking(menuTracking())
        return router.route(command, from: entry, to: session)
    }
    func performCanvas(_ command: CommandID, from entry: CommandEntry) {
        canvas.apply(command, from: entry)
    }
    func requestOpen() { onOpenRequest?() }
    func showInspector(_ visible: Bool) {
        inspector.hasImage = canvas.hasImage
        inspectorHost.isHidden = !visible
    }
    func applyFocus(_ focus: FocusContext) {
        guard focus == .canvas else { return }
        window?.makeFirstResponder(canvas)
    }
    private func consumePanelKey(_ event: NSEvent) -> Bool {
        guard !menuTracking(), inspectorVisible, focusContext != .canvas else { return false }
        if event.keyCode == 53 { return route(.escape, from: .key) }
        if event.keyCode == 48 && event.modifierFlags.contains(.shift) {
            session.tab(reverse: true)
            return true
        }
        return false
    }
    func windowDidUpdate(_ notification: Notification) {
        if inspector.hasImage != canvas.hasImage { inspector.hasImage = canvas.hasImage }
    }
}
