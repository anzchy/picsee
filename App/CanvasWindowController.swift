import AppKit
import os
import PicseeCore
import PicseeApplication
import PicseeMacUI
import PicseeInfrastructure
import SwiftUI
import Observation

/// Window intent is isolated; decode admission and buffers are shared by the pipeline.
@MainActor
final class CanvasWindowController: NSWindowController, NSWindowDelegate {
    private let canvas: CanvasInputBridge
    private let filesystemLogger = Logger(subsystem: "io.github.anzchy.picsee", category: "filesystem")
    private let pipeline: any ImagePipeline
    private var fileURL: URL?
    private var generation: UUID { session.imageLoader.generation }
    private let accessIntent = AccessIntent()
    private let inputIntent = AccessIntent()

    private var chromeOverlay: ViewerChromeOverlay!
    private var stateHost: ViewerStateHost!
    private var retryIntent: ViewerRetryIntent?
    private var retryFromFolderScan = false
    private let chromeTimer = ChromeTimerAdapter()
    private var chromeEvents: ChromeEventBridge?
    private var chromeGeneration: UUID?
    private var chromeHasImage = false
    private var gridProjection = FolderGridProjection()
    private let gridSearch = GridSearchState()
    private let searchProjection = GridSearchProjectionScheduler()
    private var gridView: GridBrowserView!
    private var gridShell: GridShellView!
    func completeGridDisplay(_ snapshot: FolderSnapshot, currentItemID: ItemID?, offset: NSPoint?) {
        searchProjection.cancel()
        let filtered = gridSearch.project(snapshot)
        let current = currentItemID ?? gridSearch.currentItemID(in: filtered, currentItemID: gridView.currentItemID)
        session.updateItems(filtered.navigationEntries.map(\.itemID),
            sourceVersion: .init(snapshot.version.generation))
        presentation.showCompletedGrid(filtered, selection: session.selection,
            currentItemID: current, offset: offset)
        pendingGridCurrentItemID = nil
        if let current = gridView.currentItemID { session.focus(current) }
        gridShell.showSearchEmpty(!gridSearch.term.isEmpty && filtered.navigationEntries.isEmpty, term: gridSearch.term)
        gridShell.setSearchStatus(resultCount: filtered.navigationEntries.count, term: gridSearch.term)
    }
    private var presentation: GridViewerPresentation!
    private var gridFolderRoot: AccessRootID?
    private var gridFolderURL: URL?
    private var gridPreviewScrollOffset: NSPoint?
    private var folderEntryRestore: ((FolderEntryRestoreTarget) -> Void)?
    private var pendingGridCurrentItemID: ItemID?
    let session: ViewerSession
    private let inspector: InspectorModel
    private let router = CommandRouter()
    private let accessServices: Task<AccessServices, Error>
    private var navigationTask: Task<Void, Never>?
    var onRecentsChanged: (([RecentFolder]) -> Void)?
    var canNavigate: Bool { fileURL != nil && window?.attachedSheet == nil }
    var gridShellVisible: Bool { gridShell != nil && !gridShell.isHidden }
    func toggleGridSidebar() { if gridShellVisible { gridShell.toggleSidebar() } }
    var gridSearchAvailable: Bool { gridShellVisible && !gridView.isHidden }
    private var inspectorHost: NSHostingView<MotionPolicyContent<InspectorPlaceholder>>!
    var onOpenRequest: (() -> Void)?
    var menuTracking: () -> Bool = { false }
    var appearanceAdapter: WindowAppearanceAdapter?

    override func showWindow(_ sender: Any?) {
        if let window { appearanceAdapter?.register(window) }
        super.showWindow(sender)
    }

    /// Under memory pressure the grid keeps only visible thumbnails; prefetch resumes when it ends.
    func memoryPressure(_ active: Bool) { gridView.setMemoryPressure(active) }

    init(pipeline: any ImagePipeline, preferencesStore: any DisplayPreferencesStore, accessServices: Task<AccessServices, Error>, motionPolicy: MotionPolicy) {
        self.pipeline = pipeline
        self.accessServices = accessServices
        session = ViewerSession(preferencesStore: preferencesStore, imageLoader: ViewerImageLoader(trace: NativeFirstPreviewTrace(), presentation: pipeline as? any ImagePresentationPinning))
        canvas = CanvasInputBridge(frame: .zero, session: session)
        inspector = InspectorModel(session: session)
        let window = CommandWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        WindowImageTitle.apply(to: window, imageURL: nil)
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
        let content = ViewerDropView(frame: window.contentView!.bounds,
            acceptsDrop: { [weak window] in window?.attachedSheet == nil },
            onDrop: { [weak self] in self?.openInput($0) })
        content.wantsLayer = true
        canvas.frame = content.bounds
        canvas.autoresizingMask = [.width, .height]
        canvas.focusRingType = .exterior
        canvas.setAccessibilityIdentifier("viewer.canvas")
        content.addSubview(canvas)
        stateHost = ViewerStateHost(frame: content.bounds, session: session)
        stateHost.autoresizingMask = [.width, .height]
        stateHost.onRetry = { [weak self] in
            self?.retryIntent?.reopen { url, request in
                guard let self else { return }
                let retainsFolder = self.session.folderScan?.preservesPresentationAuthorityForRetry(url, accessRequest: request) == true
                self.open(url, accessRequest: request, fromFolderScan: self.retryFromFolderScan || retainsFolder)
            }
        }
        stateHost.onCancelFolderReading = { [weak self] in self?.cancelFolderEntry() }
        content.addSubview(stateHost)
        let dragStrip = ChromeDragStrip(frame: NSRect(x: 0, y: content.bounds.height - 28, width: content.bounds.width, height: 28))
        dragStrip.autoresizingMask = [.width, .minYMargin]
        dragStrip.setAccessibilityIdentifier("chrome.drag-strip")
        content.addSubview(dragStrip)
        inspectorHost = NSHostingView(rootView: MotionPolicyContent(policy: motionPolicy) { InspectorPlaceholder(model: inspector, route: { [weak self] id in
            self?.route(id, from: .button)
        }, restoreCanvasFocus: { [weak self] in
            self?.window?.makeFirstResponder(self?.canvas)
        }) })
        inspectorHost.frame = NSRect(x: content.bounds.width - 272, y: 0, width: 272, height: content.bounds.height)
        inspectorHost.autoresizingMask = [.minXMargin, .height]
        inspectorHost.isHidden = true
        content.addSubview(inspectorHost)
        chromeOverlay = ViewerChromeOverlay(frame: content.bounds, session: session, motionPolicy: motionPolicy)
        chromeOverlay.autoresizingMask = [.width, .height]
        chromeOverlay.setAccessibilityIdentifier("chrome.tools")
        content.addSubview(chromeOverlay)
        gridShell = GridShellView(frame: NSRect(x: 0, y: 0, width: content.bounds.width,
                                                height: content.bounds.height - 28), preferencesStore: preferencesStore)
        gridShell.autoresizingMask = [.width, .height]
        gridShell.isHidden = true
        gridShell.onSearchChange = { [weak self] term in self?.updateGridSearch(term) }
        gridShell.onSort = { [weak self] action in self?.applyGridSort(action) }
        gridShell.onOpenSortMenu = { button, menu in
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button)
        }
        gridShell.sortConditions = { [weak self] in self?.session.folderConditions ?? .init() }
        content.addSubview(gridShell)
        gridView = GridBrowserView(frame: NSRect(origin: .zero, size: gridShell.mainFrame.size))
        gridView.thumbnailLoader = { [accessServices, pipeline] entry, rootID, coverage, priority in
            let services = try await accessServices.value
            let source = try await AccessImageSource.open(.root(rootID, file: entry.url),
                access: services.files, pipeline: pipeline)
            do {
                let result = try await source.image(covering: coverage, priority: priority)
                await source.close()
                try Task.checkCancellation()
                return result
            } catch {
                await source.close()
                throw error
            }
        }
        gridView.thumbnailPinning = pipeline as? any ImagePresentationPinning
        gridView.thumbnailPrefetchResumption = pipeline as? any PrefetchResuming
        gridView.autoresizingMask = [.width, .height]
        gridView.isHidden = true
        gridView.setAccessibilityHidden(true)
        gridView.onSelect = { [weak self] id in
            self?.gridSearch.userChoseCurrentItem(id)
            self?.session.select(id)
        }
        gridView.onSelectionGesture = { [weak self] id, modifier in
            guard let self else { return BrowserSelection() }
            self.session.select(id, modifier: modifier)
            return self.session.selection
        }
        gridView.onClearSelection = { [weak self] in
            self?.session.clearSelection()
            return self?.session.selection ?? BrowserSelection()
        }
        gridView.onCurrentChange = { [weak self] id in self?.session.focus(id) }
        gridView.onDeselect = { [weak self] in
            guard let self else { return }
            self.session.clearSelection()
            self.gridView.synchronizeSelection(self.session.selection)
        }
        gridShell.mainContent.addSubview(gridView)
        content.addSubview(stateHost, positioned: .above, relativeTo: gridShell)
        content.addSubview(inspectorHost, positioned: .above, relativeTo: stateHost)
        content.addSubview(chromeOverlay, positioned: .above, relativeTo: inspectorHost)
        presentation = GridViewerPresentation(canvas: canvas, chrome: chromeOverlay, state: stateHost,
            grid: gridView, inspector: inspectorHost, shell: gridShell)
        window.contentView = content
        chromeOverlay.linkKeyViews(to: canvas)
        stateHost.linkKeyViews(to: canvas, chrome: chromeOverlay)
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

    func windowDidResize(_ notification: Notification) {
        gridShell.layoutSubtreeIfNeeded()
        canvas.synchronizeViewport()
    }
    func windowDidEnterFullScreen(_ notification: Notification) { canvas.synchronizeViewport(); session.activity() }
    func windowDidExitFullScreen(_ notification: Notification) { canvas.synchronizeViewport(); session.activity() }

    func open(_ url: URL, accessRequest: AccessRequest? = nil, fromFolderScan: Bool = false) {
        if !fromFolderScan {
            searchProjection.cancel()
            session.leaveBrowsing()
            session.completeFolderEntry()
            folderEntryRestore = nil
            gridFolderRoot = nil
            gridFolderURL = nil
            presentation.showViewer()
        }
        retryIntent = ViewerRetryIntent(fileURL: url, accessRequest: accessRequest)
        retryFromFolderScan = fromFolderScan
        if !fromFolderScan { _ = accessIntent.begin() }
        refreshRecents()
        filesystemLogger.notice("Open file=\(url.lastPathComponent, privacy: .private)")
        fileURL = url
        window?.representedURL = url
        if !fromFolderScan { navigationTask?.cancel() }
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
        gridView.stopThumbnails()
        gridFolderRoot = nil
        gridFolderURL = nil
        endInput()
        session.endFolderScan()
        accessIntent.invalidate()
        session.closeImage()
        fileURL = nil
        WindowImageTitle.apply(to: window, imageURL: nil)
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
        endInput()
        let operation = accessIntent.begin()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        navigationTask?.cancel()
        navigationTask = Task { [self] in
            do {
                let services = try await operation.wait { try await accessServices.value }
                let currentURL = try await operation.wait { try await services.probeRootURL(folder.rootID) }
                AccessRecovery.openRecent(folder, currentURL: .success(currentURL), host: self)
            } catch {
                if operation.isCurrent { AccessRecovery.openRecent(folder, currentURL: .failure(error), host: self) }
            }
        }
    }

    func openGrantedFolder(_ folder: URL) {
        endInput()
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

    private func openFolder(_ folder: URL, rootID: AccessRootID, currentItemID: ItemID? = nil) {
        if folderEntryRestore == nil { folderEntryRestore = makeFolderEntryRestore() }
        searchProjection.cancel()
        gridSearch.reset()
        gridShell.setSearchTerm("")
        gridShell.showSearchEmpty(false)
        pendingGridCurrentItemID = currentItemID
        let operation = accessIntent.begin()
        if let window { GridWindowIdentity.enterFolder(folder, session: session, canvas: canvas, window: window) }
        else { session.enterFolderGrid(items: [], sourceVersion: .init(0)); canvas.showFailure() }
        retryIntent = nil
        retryFromFolderScan = false
        fileURL = nil
        inspector.hasImage = false
        gridFolderRoot = rootID
        gridFolderURL = folder
        gridShell.showFolder(folder.lastPathComponent)
        gridProjection = FolderGridProjection()
        let pending = FolderSnapshot(version: .init(rootID: rootID, folder: folder, generation: 0),
            entries: [], isComplete: false)
        _ = gridProjection.apply(pending)
        gridView.display(pending, selectedItemID: nil)
        showGrid(reading: true)
        refreshRecents()
        navigationTask?.cancel()
        let current = generation
        navigationTask = Task { [self] in
            do {
                let authority = FolderScanPresentationAuthority(access: operation, input: inputIntent.current, originatingTask: navigationTask)
                let services = try await operation.wait { try await accessServices.value }
                try await folderScanner(services).begin(folder: folder, rootID: rootID,
                    canPresent: { authority.isCurrent }).value
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
        if session.folderScan?.queueNavigation(direction, folder: file.deletingLastPathComponent(), input: file) == true { return }
        let operation = accessIntent.navigation()
        navigationTask?.cancel()
        let current = generation
        navigationTask = Task { [self] in
            do {
                let authority = FolderScanPresentationAuthority(access: operation, input: inputIntent.current, originatingTask: navigationTask)
                let services = try await operation.wait { try await accessServices.value }
                let root = try await operation.wait { await services.files.rootCovering(file) }
                try operation.check()
                guard generation == current else { return }
                if let root {
                    try await folderScanner(services).begin(folder: file.deletingLastPathComponent(), rootID: root,
                        input: file, pending: direction, canPresent: { authority.isCurrent }).value
                } else { promptForFolder(file.deletingLastPathComponent(), currentImage: file, direction: direction) }
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
                        let authority = FolderScanPresentationAuthority(access: operation, input: inputIntent.current, originatingTask: navigationTask)
                        let contains: Bool
                        do {
                            contains = try await operation.wait { try await services.files.withLease(.root(id, file: currentImage)) { _ in true } }
                        } catch FileAccessError.outsideRoot { contains = false }
                        if contains {
                            try await folderScanner(services).begin(folder: currentImage.deletingLastPathComponent(), rootID: id,
                                input: currentImage, pending: direction, canPresent: { authority.isCurrent }).value
                        } else {
                            promptForFolder(folder, currentImage: currentImage, direction: direction, mismatch: true)
                        }
                    } else { endInput(); openFolder(chosen, rootID: id) }
                } catch { if operation.isCurrent { showAccessError(error) } }
            }
        }
    }

    private func showAccessError(_ error: Error) {
        filesystemLogger.error("Access operation outcome=failed error=\(String(describing: error), privacy: .private)")
        showAccessMessage(String(localized: "Folder Access Failed"))
    }
    private func showInputMessage(_ notice: ViewerInputNotice) {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        switch notice {
        case .unsupported(let name):
            alert.messageText = String(localized: "This File Can’t Be Opened")
            alert.informativeText = String(format: String(localized: "“%@” isn’t a supported image format."), name)
        case .rejected:
            alert.messageText = String(localized: "None of These Files Can Be Opened")
            alert.informativeText = String(localized: "None of the dropped or opened files is a supported image.")
        case .multipleFolders:
            alert.messageText = String(localized: "Open One Folder at a Time")
            alert.informativeText = String(localized: "Drop or open a single folder to continue.")
        }
        alert.addButton(withTitle: String(localized: "OK"))
        alert.beginSheetModal(for: window)
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
        let controls: [NSView] = stateHost.buttons + chromeOverlay.tools
        if let view = window?.firstResponder as? NSView,
           controls.contains(where: { view === $0 || view.isDescendant(of: $0) }) { return .tools }
        if window?.firstResponder is NSTextInputClient { return .textInput }
        return window?.firstResponder === canvas ? .canvas : .panel
    }
    @discardableResult
    func route(_ command: CommandID, from entry: CommandEntry) -> Bool {
        if command == .search, gridSearchAvailable { gridShell.focusSearch(); return true }
        if !gridView.isHidden && (command == .preview || command == .enter) {
            gridPreviewScrollOffset = gridView.contentOffset
            session.beginBrowsing(items: gridView.displayedItemIDs,
                sourceVersion: .init(gridProjection.snapshot?.version.generation ?? 0),
                scrollAnchor: gridView.firstVisibleItemID())
        }
        session.updateFocus(focusContext)
        session.setMenuTracking(menuTracking())
        return router.route(command, from: entry, to: session)
    }
    private func returnToFolder(of file: URL) {
        let operation = accessIntent.navigation()
        navigationTask?.cancel()
        let current = generation
        navigationTask = Task { [self] in
            do {
                let services = try await operation.wait { try await accessServices.value }
                guard let root = try await operation.wait({ await services.files.rootCovering(file) }) else { return }
                try operation.check()
                guard generation == current else { return }
                let destination = try await operation.wait {
                    try await services.files.withLease(.root(root, file: file)) { lease in
                        GridSingleImageReturnPolicy.destination(for: file,
                            root: ItemIdentityRoot(id: root, url: lease.url))
                    }
                }
                openFolder(destination.folder, rootID: root, currentItemID: destination.currentItemID)
            } catch {
                if operation.isCurrent, generation == current { showAccessError(error) }
            }
        }
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
    func presentGridItem(_ id: ItemID) {
        guard let entry = gridProjection.entry(for: id), let rootID = gridFolderRoot,
              gridProjection.snapshot?.version.rootID == rootID else { return }
        searchProjection.cancel()
        presentation.showViewer()
        open(entry.url, accessRequest: .root(rootID, file: entry.url), fromFolderScan: true)
    }
    func returnToGrid() {
        guard gridFolderRoot != nil, let folder = gridProjection.snapshot?.version.folder ?? gridFolderURL else { return }
        session.setInspectorVisible(false)
        session.closeImage()
        canvas.showFailure()
        fileURL = nil
        if let snapshot = gridProjection.snapshot {
            GridWatchedSearchRefresh.restoreGrid(snapshot, session: session,
                search: gridSearch, grid: gridView, shell: gridShell)
            showGrid()
            if let offset = gridPreviewScrollOffset { gridView.restoreContentOffset(offset) }
            else if let anchor = session.scrollAnchor { gridView.scrollTo(anchor) }
        } else { showGrid() }
        if let window { GridWindowIdentity.showFolder(folder, in: window) }
    }
    private func showGrid(reading: Bool = false) {
        presentation.showGrid(reading: reading)
        if reading {
            showReadingState()
        } else {
            let current = pendingGridCurrentItemID ?? session.selection.currentItemID
            pendingGridCurrentItemID = nil
            gridView.activate(currentItemID: current)
        }
    }
    private func updateGridSearch(_ term: String) {
        guard gridSearchAvailable else { gridShell.setSearchTerm(gridSearch.term); return }
        gridSearch.setTerm(term, currentItemID: gridView.currentItemID)
        guard let snapshot = gridProjection.snapshot, snapshot.isComplete else { return }
        displaySearchedGrid(snapshot)
    }
    private func displaySearchedGrid(_ source: FolderSnapshot) {
        let term = gridSearch.term
        if term.isEmpty {
            searchProjection.cancel()
            presentSearchedGrid(source, source: source)
            return
        }
        searchProjection.schedule(source, term: term) { [weak self] filtered in
            guard let self, self.gridProjection.snapshot == source,
                  self.gridSearch.term == term else { return }
            self.presentSearchedGrid(filtered, source: source)
        }
    }
    private func presentSearchedGrid(_ filtered: FolderSnapshot, source: FolderSnapshot) {
        let current = gridSearch.currentItemID(in: filtered, currentItemID: gridView.currentItemID)
        session.updateItems(filtered.navigationEntries.map(\.itemID),
            sourceVersion: .init(source.version.generation))
        gridView.display(filtered, selection: session.selection)
        gridView.setCurrentItemID(current)
        if let current { session.focus(current) }
        gridShell.showSearchEmpty(!gridSearch.term.isEmpty && filtered.navigationEntries.isEmpty, term: gridSearch.term)
        gridShell.setSearchStatus(resultCount: filtered.navigationEntries.count, term: gridSearch.term)
    }
    private func applyGridSort(_ action: FolderMenuAction) {
        guard gridSearchAvailable, session.hasFolderSource,
              session.filePreviewSet == nil, session.previewSet == nil else { return }
        let selection = FolderMenuSelection(conditions: session.folderConditions,
            loopEnabled: session.folderLoopEnabled, recursiveEnabled: session.folderRecursiveEnabled)
        session.setFolderConditions(FolderMenuPolicy.applying(action, to: selection).conditions)
    }
    private func showReadingState() {
        stateHost.display(.readingFolder)
        if let cancel = stateHost.buttons.first {
            gridShell.linkKeyViews(from: cancel)
            window?.makeFirstResponder(cancel)
        }
    }
    private func cancelFolderEntry() {
        pendingGridCurrentItemID = nil
        let restore = folderEntryRestore
        folderEntryRestore = nil
        guard let target = session.cancelFolderEntry() else { session.cancelFolderReading(); return }
        restore?(target)
    }
    /// Native half of the restore point; the Session records the target, stops the scan and restores its own state.
    private func makeFolderEntryRestore() -> ((FolderEntryRestoreTarget) -> Void) {
        let completeGrid = gridFolderRoot != nil && gridProjection.snapshot?.isComplete == true
        let root = completeGrid ? gridFolderRoot : nil, folder = completeGrid ? gridFolderURL : nil
        let projection = completeGrid ? gridProjection : FolderGridProjection()
        let offset = gridView.contentOffset, previewOffset = completeGrid ? gridPreviewScrollOffset : nil
        let request = retryIntent?.accessRequest, fromFolder = retryFromFolderScan
        let priorSearchTerm = gridSearch.term, priorCurrent = gridView.currentItemID
        session.beginFolderEntry(shownImage: fileURL, hasCompleteGrid: completeGrid)
        return { [weak self] target in
            guard let self else { return }
            gridFolderRoot = root
            gridFolderURL = folder
            gridProjection = projection
            gridPreviewScrollOffset = previewOffset
            switch target {
            case .grid:
                guard let snapshot = projection.snapshot else { return }
                gridSearch.setTerm(priorSearchTerm, currentItemID: priorCurrent)
                gridShell.setSearchTerm(priorSearchTerm)
                completeGridDisplay(snapshot, currentItemID: priorCurrent, offset: offset)
                if let window { GridWindowIdentity.showFolder(snapshot.version.folder, in: window) }
            case .viewer(let file):
                // A grid preview reopens inside its restored grid; Esc still returns there.
                presentation.show(target)
                open(file, accessRequest: request, fromFolderScan: fromFolder || root != nil)
            case .empty:
                restoreEmptyFolderEntry()
            }
        }
    }
    private func restoreEmptyFolderEntry() {
        searchProjection.cancel()
        gridFolderRoot = nil
        gridFolderURL = nil
        gridProjection = FolderGridProjection()
        gridPreviewScrollOffset = nil
        session.leaveBrowsing()
        presentation.showViewer()
        canvas.showFailure()
        window?.title = "Picsee"
        window?.representedURL = nil
        stateHost.refresh()
    }
    private func consumePanelKey(_ event: NSEvent) -> Bool {
        if !gridView.isHidden, focusContext != .textInput,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if event.keyCode == 49 { return route(.preview, from: .key) }
            if event.keyCode == 36 || event.keyCode == 76 { return route(.enter, from: .key) }
        }
        if InspectorEscapePolicy.handlesEscape(inspectorVisible: inspectorVisible,
            menuTracking: menuTracking(), focus: focusContext, keyCode: event.keyCode) {
            return route(.escape, from: .key)
        }
        guard !menuTracking(), inspectorVisible, focusContext != .canvas else { return false }
        if event.keyCode == 48 && (focusContext == .tools || event.modifierFlags.contains(.shift)) {
            session.tab(reverse: event.modifierFlags.contains(.shift))
            return true
        }
        return false
    }
    func windowDidUpdate(_ notification: Notification) {
        stateHost.refresh()
        if !gridView.isHidden {
            stateHost.isHidden = true
            stateHost.setAccessibilityHidden(true)
        }
        if inspector.hasImage != canvas.hasImage { inspector.hasImage = canvas.hasImage }
        if chromeGeneration != generation || chromeHasImage != canvas.hasImage {
            let opened = chromeGeneration != generation
            chromeGeneration = generation; chromeHasImage = canvas.hasImage
            chromeOverlay.refresh(session: session)
            stateHost.linkKeyViews(to: canvas, chrome: chromeOverlay)
            if opened { session.activity() }
        }
    }
}

// Untested native effect; the Session runs it only after menu and Inspector/panel Esc (package-tested).
extension CanvasWindowController: ViewerSingleImageReturnHost {
    var canReturnToFolder: Bool { gridView.isHidden && fileURL != nil && window?.attachedSheet == nil }
    func returnSingleImageToFolder() {
        if let fileURL { returnToFolder(of: fileURL) }
    }
}

// Untested native titlebar/first-responder wiring; policy and views are package-tested.
extension CanvasWindowController: ViewerChromeHost {
    func applyChrome(toolsVisible: Bool, trafficLightsVisible: Bool) {
        chromeOverlay.setToolsVisible(toolsVisible)
        stateHost.linkKeyViews(to: canvas, chrome: chromeOverlay)
        if let window {
            ChromeTitlebarPolicy.apply(to: window,
                visible: ChromeTitlebarPolicy.trafficLightsVisible(
                    isGridVisible: !gridView.isHidden, viewerVisible: trafficLightsVisible),
                fullScreen: window.styleMask.contains(.fullScreen))
        }
    }
    func focusChromeTool(reverse: Bool, entering: Bool) -> Bool {
        ViewerStateFocus.move(reverse: reverse, entering: entering, state: stateHost, chrome: chromeOverlay)
    }
}

// The package owns generation, identity, tier and lease decisions; these are native effects.
extension CanvasWindowController: ViewerImageHost {
    func beginImageOpening() {
        WindowImageTitle.apply(to: window, imageURL: nil)
        canvas.beginOpening()
        stateHost.refresh()
    }
    func installImage(_ image: DecodedImage, fileURL: URL) {
        canvas.install(image)
        WindowImageTitle.apply(to: window, imageURL: fileURL)
        stateHost.refresh()
    }
    func imageLoadFailed(_ error: any Error) {
        canvas.showFailure()
        WindowImageTitle.apply(to: window, imageURL: nil)
        let cancelled = session.dismissCancelledImageFailure(error)
        stateHost.refresh()
        if cancelled { return }
        if error is FileAccessError { showAccessError(error) }
    }
}

// Untested native recovery forwarding; the Application owns decision/host routing.
extension CanvasWindowController: AccessRecoveryHost {
    func browseRecoveredFolder(_ url: URL, rootID: AccessRootID) { openFolder(url, rootID: rootID) }
    func showAccessRecoveryError(_ error: any Error) { showAccessError(error) }
    func requestFolderReconnection(rootID: AccessRootID, lastKnownFolder: URL, displayName: String) {
        guard let window, window.attachedSheet == nil else { return }
        let operation = accessIntent.current
        ReconnectPrompt.request(displayName: displayName, lastKnownFolder: lastKnownFolder,
                                window: window, isCurrent: { operation.isCurrent }) { [weak self] selection in
            guard let self, operation.isCurrent else { return }
            switch selection {
            case .anotherFolder(let url): openGrantedFolder(url)
            case .reconnect(let url):
                navigationTask?.cancel()
                navigationTask = Task { [self] in
                    do {
                        let services = try await operation.wait { try await accessServices.value }
                        let target = try await operation.wait { try await services.reconnect(rootID, folder: url) }
                        refreshRecents()
                        try operation.check()
                        openFolder(target.url, rootID: target.rootID)
                    } catch { if operation.isCurrent { showAccessError(error) } }
                }
            }
        }
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

// Native input effects; classification and admission belong to the Session.
extension CanvasWindowController: ViewerInputHost {
    func openInput(_ urls: [URL]) {
        let operation = inputIntent.begin()
        Task { [weak self] in
            guard let self else { return }
            do {
                let services = try await operation.wait { try await accessServices.value }
                let scale = window?.backingScaleFactor ?? 1
                let maximum = max(1, Int(ceil(max(canvas.bounds.width, canvas.bounds.height) * scale)))
                let admission = ViewerInputAdmission(access: services.files, pipeline: pipeline,
                    maximumPixelSize: maximum, rootCovering: { await services.files.rootCovering($0) })
                await session.openInput(urls, operation: operation, admission: admission, host: self)
            } catch { if operation.isCurrent { showAccessError(error) } }
        }
    }
    private func endInput() { inputIntent.invalidate(); session.endFilePreviewSet() }
    func openInputImage(_ url: URL, accessRequest: AccessRequest?) {
        session.endFolderScan()
        open(url, accessRequest: accessRequest)
        guard case .root(let rootID, _)? = accessRequest else { return }
        let operation = accessIntent.current
        navigationTask = Task { [self] in
            do {
                let authority = FolderScanPresentationAuthority(access: operation, input: inputIntent.current, originatingTask: navigationTask)
                let services = try await operation.wait { try await accessServices.value }
                try await folderScanner(services).begin(folder: url.deletingLastPathComponent(), rootID: rootID,
                    input: url, canPresent: { authority.isCurrent }).value
            } catch {
                filesystemLogger.error("Background folder scan outcome=failed error=\(String(describing: error), privacy: .private)")
            }
        }
    }
    func showInputNotice(_ notice: ViewerInputNotice) { showInputMessage(notice) }
    func promptForInputFolder(_ folder: URL) { promptForFolder(folder, currentImage: nil, direction: .next) }
}

// Untested native scan effects; snapshot navigation policy is covered in PicseeApplication.
extension CanvasWindowController: FolderScanHost {
    private func folderScanner(_ services: AccessServices) -> FolderScanCoordinator {
        if let scan = session.folderScan { return scan }
        let scan = FolderScanCoordinator(access: services.files, scanner: services.browser,
            trace: NativeFolderScanTrace(), metadataReader: ImageFolderMetadataReader(), watcher: services.watch)
        scan.host = self
        session.folderScan = scan
        observeGridSnapshot(scan)
        return scan
    }
    private func observeGridSnapshot(_ scan: FolderScanCoordinator) {
        withObservationTracking {
            gridView.setMetadataSortState(scan.metadataSortState)
            chromeOverlay.setMetadataSortState(scan.metadataSortState)
            // A restored source equals the projection already shown; repainting it would cover a restored viewer.
            if let snapshot = scan.snapshot, gridFolderRoot == snapshot.version.rootID,
               snapshot != gridProjection.snapshot, gridProjection.apply(snapshot), snapshot.isComplete {
                let anchor = gridView.firstVisibleItemID() ?? gridProjection.scrollAnchor
                gridProjection.setScrollAnchor(anchor)
                // A watched refresh only reconciles: an open Preview Set shrinks in place and the grid stays as shown.
                let entering = folderEntryRestore != nil
                let offset = gridView.contentOffset
                if entering {
                    completeGridDisplay(snapshot, currentItemID: pendingGridCurrentItemID, offset: nil)
                    folderEntryRestore = nil
                    session.completeFolderEntry()
                } else if !gridView.isHidden {
                    // Re-filter synchronously without moving keyboard focus out of the search field.
                    GridWatchedSearchRefresh.apply(snapshot, session: session, search: gridSearch,
                        scheduler: searchProjection, grid: gridView, shell: gridShell, gridVisible: true)
                    gridView.restoreContentOffset(offset)
                } else {
                    GridWatchedSearchRefresh.apply(snapshot, session: session, search: gridSearch,
                        scheduler: searchProjection, grid: gridView, shell: gridShell, gridVisible: false)
                }
            }
        } onChange: { [weak self, weak scan] in
            Task { @MainActor [weak self, weak scan] in
                guard let self, let scan, self.session.folderScan === scan else { return }
                self.observeGridSnapshot(scan)
            }
        }
    }
    func openFolderImage(_ url: URL, rootID: AccessRootID) {
        if gridFolderRoot == rootID { return }
        // A scan-owned move must not revoke the authority that admits its later batches.
        open(url, accessRequest: .root(rootID, file: url), fromFolderScan: true)
    }
    func clearFolderImageForNoMatches() {
        retryIntent = nil
        retryFromFolderScan = false
        fileURL = nil
        session.closeImage()
        canvas.showFailure()
        WindowImageTitle.apply(to: window, imageURL: nil)
    }
    func rememberFolder(_ folder: URL, rootID: AccessRootID) async throws {
        let operation = accessIntent.current
        let authority = FolderScanPresentationAuthority(access: operation, input: inputIntent.current, originatingTask: navigationTask)
        let services = try await operation.wait { try await accessServices.value }
        guard authority.isCurrent else { throw CancellationError() }
        try await operation.wait {
            try await services.recent.add(RecentFolder(rootID: rootID, url: folder, displayName: folder.lastPathComponent))
        }
        guard authority.isCurrent else { throw CancellationError() }
        refreshRecents()
    }
    func showEmptyFolder() { showAccessMessage(String(localized: "No Images in This Folder")) }
    func folderScanDidComplete(count: Int) { chromeOverlay.refresh(session: session) }
    func folderScanDidStart() {
        chromeOverlay.refresh(session: session)
        // An Include Subfolders rescan from the grid; the Session already recorded what Cancel Reading returns to.
        guard presentation.showReadingOverGrid(session.folderScan?.isReadingFolder == true) else { return }
        if folderEntryRestore == nil { folderEntryRestore = makeFolderEntryRestore() }
        showReadingState()
    }
    func folderScanDidEnd() { chromeOverlay.refresh(session: session) }

    /// Untested native os adapter; structured lifecycle is covered at the Application trace port.
    @MainActor private final class NativeFolderScanTrace: FolderScanTracing {
        private let log = OSLog(subsystem: "io.github.anzchy.picsee", category: "filesystem")
        private let logger = Logger(subsystem: "io.github.anzchy.picsee", category: "filesystem")
        private var ids: [UInt64: OSSignpostID] = [:]
        func begin(generation: UInt64, folderURL: URL) {
            let id = OSSignpostID(log: log)
            ids[generation] = id
            os_signpost(.begin, log: log, name: "FolderScan", signpostID: id,
                "generation=%{public}llu folder=%{private}s", generation, folderURL.path)
            logger.notice("FolderScan begin generation=\(generation, privacy: .public) folder=\(folderURL.path, privacy: .private)")
        }
        func firstBatch(count: Int, generation: UInt64) {
            os_signpost(.event, log: log, name: "scan_first_batch", "count=%{public}ld generation=%{public}llu", count, generation)
            logger.notice("scan_first_batch count=\(count, privacy: .public) generation=\(generation, privacy: .public)")
        }
        func complete(count: Int, generation: UInt64) {
            os_signpost(.event, log: log, name: "scan_complete", "count=%{public}ld generation=%{public}llu", count, generation)
            logger.notice("scan_complete count=\(count, privacy: .public) generation=\(generation, privacy: .public)")
        }
        func failure(_ error: any Error, generation: UInt64) {
            logger.error("FolderScan failure generation=\(generation, privacy: .public) error=\(String(describing: error), privacy: .private)")
        }
        func end(outcome: FolderScanOutcome, generation: UInt64) {
            guard let id = ids.removeValue(forKey: generation) else { return }
            os_signpost(.end, log: log, name: "FolderScan", signpostID: id,
                "outcome=%{public}s generation=%{public}llu", outcome.rawValue, generation)
            logger.notice("FolderScan outcome=\(outcome.rawValue, privacy: .public) generation=\(generation, privacy: .public)")
        }
    }
}
