import AppKit
import os
import PicseeCore
import PicseeApplication
import PicseeMacUI
import PicseeInfrastructure
import SwiftUI

/// Window intent is isolated; decode admission and buffers are shared by the pipeline.
@MainActor
final class CanvasWindowController: NSWindowController, NSWindowDelegate {
    private let canvas: CanvasInputBridge
    private let filesystemLogger = Logger(subsystem: "io.github.anzchy.picsee", category: "filesystem")
    private let pipeline: any ImagePipeline
    private var fileURL: URL?
    private var generation: UUID { session.imageLoader.generation }
    private let accessIntent = AccessIntent()

    private var chromeOverlay: ViewerChromeOverlay!
    private let chromeTimer = ChromeTimerAdapter()
    private var chromeEvents: ChromeEventBridge?
    private var chromeGeneration: UUID?
    private var chromeHasImage = false
    let session: ViewerSession
    private let inspector: InspectorModel
    private let router = CommandRouter()
    private let accessServices: Task<AccessServices, Error>
    private var navigationTask: Task<Void, Never>?
    var onRecentsChanged: (([RecentFolder]) -> Void)?
    var canNavigate: Bool { fileURL != nil && window?.attachedSheet == nil }
    private var inspectorHost: NSHostingView<InspectorPlaceholder>!
    var onOpenRequest: (() -> Void)?
    var menuTracking: () -> Bool = { false }

    init(pipeline: any ImagePipeline, preferencesStore: any DisplayPreferencesStore, accessServices: Task<AccessServices, Error>) {
        self.pipeline = pipeline
        self.accessServices = accessServices
        session = ViewerSession(preferencesStore: preferencesStore, imageLoader: ViewerImageLoader(trace: NativeFirstPreviewTrace()))
        canvas = CanvasInputBridge(frame: .zero, session: session)
        inspector = InspectorModel(session: session)
        let window = CommandWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Picsee"
        window.titlebarAppearsTransparent = true
        window.acceptsMouseMovedEvents = true
        window.autorecalculatesKeyViewLoop = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.center()
        super.init(window: window)
        session.host = self
        session.imageLoader.host = self
        window.delegate = self
        let content = NSView(frame: window.contentView!.bounds)
        content.wantsLayer = true
        canvas.frame = content.bounds
        canvas.autoresizingMask = [.width, .height]
        canvas.focusRingType = .exterior
        canvas.setAccessibilityIdentifier("viewer.canvas")
        content.addSubview(canvas)
        let dragStrip = ChromeDragStrip(frame: NSRect(x: 0, y: content.bounds.height - 28, width: content.bounds.width, height: 28))
        dragStrip.autoresizingMask = [.width, .minYMargin]
        dragStrip.setAccessibilityIdentifier("chrome.drag-strip")
        content.addSubview(dragStrip)
        inspectorHost = NSHostingView(rootView: InspectorPlaceholder(model: inspector, route: { [weak self] id in
            self?.route(id, from: .button)
        }, restoreCanvasFocus: { [weak self] in
            self?.window?.makeFirstResponder(self?.canvas)
        }))
        inspectorHost.frame = NSRect(x: content.bounds.width - 272, y: 0, width: 272, height: content.bounds.height)
        inspectorHost.autoresizingMask = [.minXMargin, .height]
        inspectorHost.isHidden = true
        content.addSubview(inspectorHost)
        chromeOverlay = ViewerChromeOverlay(frame: content.bounds, session: session)
        chromeOverlay.autoresizingMask = [.width, .height]
        chromeOverlay.setAccessibilityIdentifier("chrome.tools")
        content.addSubview(chromeOverlay)
        window.contentView = content
        chromeOverlay.linkKeyViews(to: canvas)
        inspectorHost.nextKeyView = canvas
        session.chromeHost = self
        session.installChromeScheduler(chromeTimer)
        chromeEvents = ChromeEventBridge(window: window, overlay: chromeOverlay, timer: chromeTimer)
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
            self?.session.requireImageResolution(maximum)
        }
    }

    required init?(coder: NSCoder) { nil }

    func windowDidResize(_ notification: Notification) { canvas.synchronizeViewport() }
    func windowDidEnterFullScreen(_ notification: Notification) { canvas.synchronizeViewport(); session.activity() }
    func windowDidExitFullScreen(_ notification: Notification) { canvas.synchronizeViewport(); session.activity() }

    func open(_ url: URL, accessRequest: AccessRequest? = nil) {
        _ = accessIntent.begin()
        refreshRecents()
        filesystemLogger.notice("Open file=\(url.lastPathComponent, privacy: .private)")
        fileURL = url
        navigationTask?.cancel()
        let scale = window?.backingScaleFactor ?? 1
        let maximum = max(1, Int(ceil(max(canvas.bounds.width, canvas.bounds.height) * scale)))
        session.openImage(url, maximumPixelSize: maximum, opener: ViewerImageLoader.accessOpener(intent: accessIntent) { [accessServices, pipeline] operation in
            let services = try await operation.wait { try await accessServices.value }
            let request: AccessRequest
            if let accessRequest { request = accessRequest }
            else {
                let root = try await operation.wait { await services.files.rootCovering(url) }
                request = root.map { .root($0, file: url) } ?? .fileGrant(url)
            }
            try operation.check()
            return try await AccessImageSource.open(request, access: services.files, pipeline: pipeline)
        })
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
    }

    func windowWillClose(_ notification: Notification) {
        accessIntent.invalidate()
        session.closeImage()
        fileURL = nil
        navigationTask?.cancel()
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
        if let view = window?.firstResponder as? NSView,
           chromeOverlay.tools.contains(where: { view === $0 || view.isDescendant(of: $0) }) { return .tools }
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
        if event.keyCode == 48 && (focusContext == .tools || event.modifierFlags.contains(.shift)) {
            session.tab(reverse: event.modifierFlags.contains(.shift))
            return true
        }
        return false
    }
    func windowDidUpdate(_ notification: Notification) {
        if inspector.hasImage != canvas.hasImage { inspector.hasImage = canvas.hasImage }
        if chromeGeneration != generation || chromeHasImage != canvas.hasImage {
            let opened = chromeGeneration != generation
            chromeGeneration = generation; chromeHasImage = canvas.hasImage
            chromeOverlay.refresh(filename: fileURL?.lastPathComponent)
            if opened { session.activity() }
        }
    }
}

// Untested native titlebar/first-responder wiring; policy and views are package-tested.
extension CanvasWindowController: ViewerChromeHost {
    func applyChrome(toolsVisible: Bool, trafficLightsVisible: Bool) {
        chromeOverlay.setToolsVisible(toolsVisible)
        if let window { ChromeTitlebarPolicy.apply(to: window, visible: trafficLightsVisible, fullScreen: window.styleMask.contains(.fullScreen)) }
    }
    func focusChromeTool(reverse: Bool, entering: Bool) -> Bool {
        chromeOverlay.focusTool(reverse: reverse, entering: entering)
    }
}

// The package owns generation, identity, tier and lease decisions; these are native effects.
extension CanvasWindowController: ViewerImageHost {
    func beginImageOpening() {
        window?.title = "Picsee"
        canvas.beginOpening()
    }
    func installImage(_ image: DecodedImage, fileURL: URL) {
        canvas.install(image)
        window?.title = fileURL.lastPathComponent
    }
    func imageLoadFailed(_ error: any Error) {
        canvas.showFailure()
        window?.title = "Picsee"
        if error is FileAccessError { showAccessError(error) }
    }
}

/// Untested os adapter. Lifecycle balancing is covered at the Application tracing port.
@MainActor private final class NativeFirstPreviewTrace: FirstPreviewTracing {
    private let log = OSLog(subsystem: "io.github.anzchy.picsee", category: "render")
    private let logger = Logger(subsystem: "io.github.anzchy.picsee", category: "render")
    private var ids: [UUID: OSSignpostID] = [:]
    func begin(_ id: UUID, fileURL: URL) {
        let signpost = OSSignpostID(log: log)
        ids[id] = signpost
        os_signpost(.begin, log: log, name: "FirstPreview", signpostID: signpost,
                    "file=%{private}s", fileURL.lastPathComponent)
    }
    func end(_ id: UUID, outcome: FirstPreviewOutcome) {
        guard let signpost = ids.removeValue(forKey: id) else { return }
        os_signpost(.end, log: log, name: "FirstPreview", signpostID: signpost,
                    "outcome=%{public}s", outcome.rawValue)
        logger.notice("FirstPreview outcome=\(outcome.rawValue, privacy: .public) open=\(id.uuidString, privacy: .private)")
    }
}
