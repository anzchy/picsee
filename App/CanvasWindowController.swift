import AppKit
import os
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
import SwiftUI

/// Window intent is isolated; decode admission and buffers are shared by the pipeline.
@MainActor
final class CanvasWindowController: NSWindowController, NSWindowDelegate {
    private let canvas: CanvasInputBridge
    private let filesystemLogger = Logger(subsystem: "io.github.anzchy.picsee", category: "filesystem")
    private let pipeline: any ImagePipeline
    private var fileURL: URL?
    private var generation = UUID()
    private let accessIntent = AccessIntent()
    private var desiredMaximum = 0
    private var decodeProgress = CanvasDecodeProgress()
    private var decoding = false
    private var decodeTask: Task<Void, Never>?
    private let binding = UUID()
    private var currentKey: RenderKey?

    let session: ViewerSession
    private let inspector: InspectorModel
    private let router = CommandRouter()
    private let accessServices: Task<AccessServices, Error>
    private var imageSource: AccessImageSource?
    private var sourceGeneration: UUID?
    private var currentAccessRequest: AccessRequest?
    private var openTask: Task<Void, Never>?
    private var navigationTask: Task<Void, Never>?
    var onRecentsChanged: (([RecentFolder]) -> Void)?
    var canNavigate: Bool { fileURL != nil && window?.attachedSheet == nil }
    private var inspectorHost: NSHostingView<InspectorPlaceholder>!
    var onOpenRequest: (() -> Void)?
    var menuTracking: () -> Bool = { false }

    init(pipeline: any ImagePipeline, preferencesStore: any DisplayPreferencesStore, accessServices: Task<AccessServices, Error>) {
        self.pipeline = pipeline
        self.accessServices = accessServices
        session = ViewerSession(preferencesStore: preferencesStore)
        canvas = CanvasInputBridge(frame: .zero, session: session)
        inspector = InspectorModel(session: session)
        let window = CommandWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Picsee"
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
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
        // Explicit opens change generation; revision retries within a decode retain it.
        canvas.openingGeneration = { [weak self] in self?.generation ?? UUID() }
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

    func windowDidResize(_ notification: Notification) { canvas.synchronizeViewport() }
    func windowDidEnterFullScreen(_ notification: Notification) { canvas.synchronizeViewport() }
    func windowDidExitFullScreen(_ notification: Notification) { canvas.synchronizeViewport() }

    func open(_ url: URL, accessRequest: AccessRequest? = nil) {
        let operation = accessIntent.begin()
        refreshRecents()
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
        openTask?.cancel()
        navigationTask?.cancel()
        let openingGeneration = generation
        openTask = Task { [self] in
            do {
                let services = try await operation.wait { try await accessServices.value }
                let request: AccessRequest
                if let accessRequest { request = accessRequest }
                else {
                    let root = try await operation.wait { await services.files.rootCovering(url) }
                    request = root.map { .root($0, file: url) } ?? .fileGrant(url)
                }
                try operation.check()
                let source = try await AccessImageSource.open(request, access: services.files, pipeline: pipeline)
                guard operation.isCurrent, generation == openingGeneration else { await source.close(); return }
                let old = imageSource
                imageSource = source; sourceGeneration = openingGeneration; currentAccessRequest = request
                try await operation.wait { await old?.close() }
                decodeIfNeeded()
            } catch {
                if generation == openingGeneration, operation.isCurrent {
                    let old = imageSource; imageSource = nil
                    await old?.close()
                    guard operation.isCurrent, generation == openingGeneration else { return }
                    canvas.showFailure()
                    showAccessError(error)
                }
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        accessIntent.invalidate()
        decodeTask?.cancel()
        decodeTask = nil
        decoding = false
        generation = UUID()
        currentKey = nil
        fileURL = nil
        openTask?.cancel(); navigationTask?.cancel()
        let source = imageSource; imageSource = nil; sourceGeneration = nil
        Task { await source?.close() }
    }

    private func decodeIfNeeded() {
        guard !decoding, sourceGeneration == generation, let source = imageSource, let maximum = decodeProgress.nextMaximum(desired: desiredMaximum) else { return }
        decoding = true
        let token = PresentationToken(binding: binding, generation: generation)
        let isPreview = !decodeProgress.previewCompleted
        decodeTask = Task { [self] in
            do {
                let (request, image) = try await source.image(maximumPixelSize: maximum, isPreview: isPreview)
                guard token.generation == generation else { return }
                currentKey = request.renderKey
                try Task.checkCancellation()
                if let key = request.renderKey, let expectedKey = currentKey, let revision = image.revision {
                    let expected = RenderKey(itemID: expectedKey.itemID, revision: revision, maximumPixelSize: maximum, isPreview: isPreview,
                        frameIndex: expectedKey.frameIndex, policy: expectedKey.policy,
                        decoderVersion: expectedKey.decoderVersion, purpose: expectedKey.purpose)
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
                    if (error as? ImageLoadError)?.kind == .sourceChanged,
                       decodeProgress.restartForRevision(request: token, current: current) {
                        currentKey = nil
                        canvas.beginOpening()
                        do { try await renewImageSource(token: token) }
                        catch {
                            if token.generation == generation, !Task.isCancelled {
                                canvas.showFailure(); desiredMaximum = 0
                            }
                        }
                    } else {
                        canvas.showFailure(); desiredMaximum = 0
                        if error is FileAccessError { showAccessError(error) }
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

    private func renewImageSource(token: PresentationToken) async throws {
        let operation = accessIntent.current
        guard let request = currentAccessRequest else { throw FileAccessError.startFailed }
        let services = try await operation.wait { try await accessServices.value }
        let source = try await AccessImageSource.open(request, access: services.files, pipeline: pipeline)
        guard token.generation == generation, operation.isCurrent else { await source.close(); return }
        let old = imageSource; imageSource = source
        try await operation.wait { await old?.close() }
    }

    func refreshRecents() {
        let operation = accessIntent.current
        Task { [weak self] in
            guard let self else { return }
            do {
                let services = try await operation.wait { try await accessServices.value }
                let folders = try await operation.wait { try await services.recent.load() }
                onRecentsChanged?(folders)
            } catch { if operation.isCurrent { showAccessError(error) } }
        }
    }

    func openRecent(_ folder: RecentFolder) {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        openFolder(folder.url, rootID: folder.rootID)
    }

    func openGrantedFolder(_ folder: URL) {
        let operation = accessIntent.begin()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        navigationTask?.cancel()
        navigationTask = Task { [self] in
            do {
                let services = try await operation.wait { try await accessServices.value }
                let id = try await operation.wait { try await services.grant(folder) }
                refreshRecents()
                try operation.check()
                openFolder(folder, rootID: id)
            } catch { if operation.isCurrent { showAccessError(error) } }
        }
    }

    private func openFolder(_ folder: URL, rootID: AccessRootID) {
        let operation = accessIntent.begin()
        refreshRecents()
        navigationTask?.cancel()
        let current = generation
        navigationTask = Task { [self] in
            do {
                let services = try await operation.wait { try await accessServices.value }
                let first = try await operation.firstImage(list: {
                    try await services.images(in: folder, rootID: rootID)
                }, remember: {
                    try await services.recent.add(RecentFolder(rootID: rootID, url: folder, displayName: folder.lastPathComponent))
                })
                if let first {
                    refreshRecents()
                    open(first, accessRequest: .root(rootID, file: first))
                } else { showAccessMessage(String(localized: "No Images in This Folder")) }
            } catch {
                if operation.isCurrent, generation == current {
                    if error as? FileAccessError == .corruptStore { showAccessError(error) }
                    else { promptForFolder(folder, currentImage: nil, direction: .next) }
                }
            }
        }
    }

    func navigate(_ direction: NavigationDirection) {
        guard let file = fileURL else { return }
        let operation = accessIntent.navigation()
        navigationTask?.cancel()
        let current = generation
        navigationTask = Task { [self] in
            do {
                let services = try await operation.wait { try await accessServices.value }
                let root = try await operation.wait { await services.files.rootCovering(file) }
                let images: [URL]
                if let root { images = try await operation.wait { try await services.images(in: file.deletingLastPathComponent(), rootID: root) } }
                else { images = [] }
                try operation.check()
                guard generation == current else { return }
                switch FolderNavigation(images: images).step(from: file, direction: direction, covered: root != nil) {
                case .needsGrant(let folder): promptForFolder(folder, currentImage: file, direction: direction)
                case .move(let next): if let root { open(next, accessRequest: .root(root, file: next)) }
                case .end: break
                }
            } catch {
                if operation.isCurrent, generation == current {
                    if error is FileAccessError { promptForFolder(file.deletingLastPathComponent(), currentImage: file, direction: direction) }
                    else { showAccessError(error) }
                }
            }
        }
    }

    private func promptForFolder(_ folder: URL, currentImage: URL?, direction: NavigationDirection, mismatch: Bool = false) {
        guard let window, window.attachedSheet == nil else { return }
        let current = generation
        let operation = accessIntent.current
        FolderGrantPrompt.request(folder: folder, window: window, mismatch: mismatch) { [weak self] chosen in
            guard let self, operation.isCurrent else { return }
            self.navigationTask = Task { [self] in
                do {
                    let services = try await operation.wait { try await accessServices.value }
                    let id = try await operation.wait { try await services.grant(chosen) }
                    refreshRecents()
                    guard operation.isCurrent, generation == current else { return }
                    if let currentImage {
                        let contains: Bool
                        do {
                            contains = try await operation.wait { try await services.files.withLease(.root(id, file: currentImage)) { _ in true } }
                        } catch FileAccessError.outsideRoot { contains = false }
                        if contains {
                            let images = try await operation.wait { try await services.images(in: currentImage.deletingLastPathComponent(), rootID: id) }
                            if case .move(let next) = FolderNavigation(images: images).step(from: currentImage, direction: direction, covered: true) {
                                open(next, accessRequest: .root(id, file: next))
                            }
                        } else {
                            promptForFolder(folder, currentImage: currentImage, direction: direction, mismatch: true)
                        }
                    } else { openFolder(chosen, rootID: id) }
                } catch { if operation.isCurrent { showAccessError(error) } }
            }
        }
    }

    private func showAccessError(_ error: Error) {
        filesystemLogger.error("Access operation outcome=failed error=\(String(describing: error), privacy: .private)")
        showAccessMessage(String(localized: "Folder Access Failed"))
    }
    private func showAccessMessage(_ message: String) {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: String(localized: "OK"))
        alert.beginSheetModal(for: window)
    }
}

// Native effects only. The Session decides command availability and transitions.
extension CanvasWindowController: ViewerSessionNavigationHost {
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
        _ = canvas.apply(command, from: entry)
    }
    func performCanvasZoom(_ command: CommandID, from entry: CommandEntry) -> Double? {
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
