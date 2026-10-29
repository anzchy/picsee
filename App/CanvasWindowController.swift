import AppKit
import os
import PicseeCore
import PicseeApplication
import PicseeMacUI
import PicseeInfrastructure
import SwiftUI
import Observation
import Darwin

/// Window intent is isolated; decode admission and buffers are shared by the pipeline.
@MainActor
final class CanvasWindowController: NSWindowController, NSWindowDelegate {
    private let canvas: CanvasInputBridge
    private let filesystemLogger = Logger(subsystem: "io.github.anzchy.picsee", category: "filesystem")
    private let pipeline: any ImagePipeline
    private var fileURL: URL?
    struct WaitingAccessPosition {
        let rootID: AccessRootID
        let folderURL: URL
        let currentItemID: ItemID?
        let currentImageURL: URL?
        let wasViewing: Bool
        let conditions: FolderViewConditions
        let recursive: Bool
        let loop: Bool
        let searchTerm: String
        let scrollOffset: NSPoint
        var counter: UInt64
    }
    private(set) var waitingAccessPosition: WaitingAccessPosition?
    private(set) var accessLossCause: AccessLossCause?
    private var presentationRootID: AccessRootID?
    private var accessMonitor: AccessMonitor?
    private var accessObserver: UUID?
    private var accessAttachmentTask: Task<Void, Never>?
    private var accessAttachmentGeneration = UUID()
    private var scanReadContext: AccessMonitor.ReadContext?
    private var presentationReadContext: AccessMonitor.ReadContext?
    private var generation: UUID { session.imageLoader.generation }
    private let accessIntent = AccessIntent()
    private let inputIntent = AccessIntent()
    private let rootScanAdmission = RootScanAdmission()

    private var chromeOverlay: ViewerChromeOverlay!
    private var stateHost: ViewerStateHost!
    private var lostAccessView: LostAccessStateView!
    private var accessAnnouncementTask: Task<Void, Never>?
    private var retryIntent: ViewerRetryIntent?
    private var retryFromFolderScan = false
    private let chromeTimer = ChromeTimerAdapter()
    private var chromeEvents: ChromeEventBridge?
    private var chromeGeneration: UUID?
    private var chromeHasImage = false
    private var gridProjection = FolderGridProjection()
    private var viewedRefreshVersion: SnapshotVersion?
    private let gridSearch = GridSearchState()
    private let searchProjection = GridSearchProjectionScheduler()
    private var gridView: GridBrowserView!
    private var gridShell: GridShellView!
    private var sidebarTreeTask: Task<Void, Never>?
    private var sidebarLoader: SidebarFolderLoadSession?
    private var sidebarTreeGeneration = UUID()
    private var sidebarWatchSubscription: (any FolderWatchSubscription)?
    var sidebarBrowserOverride: SidebarFolderBrowser?
    private var sidebarKnownCounts: [URL: Int] = [:]
    func completeGridDisplay(_ snapshot: FolderSnapshot, currentItemID: ItemID?, offset: NSPoint?) {
        guard waitingAccessPosition == nil, scanReadContext?.permit.isCurrent != false else { return }
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
    private var latestRecents: [RecentFolder] = []
    private var viewerEmptyFolderChildren: URL?
    private var gridFolderURL: URL?
    private var gridPreviewScrollOffset: NSPoint?
    private var folderEntryRestore: ((FolderEntryRestoreTarget) -> Void)?
    private var pendingGridCurrentItemID: ItemID?
    let session: ViewerSession
    let inspector: InspectorModel
    private let motionPolicy: MotionPolicy
    private let router = CommandRouter()
    private let accessServices: Task<AccessServices, Error>
    private var navigationTask: Task<Void, Never>?
    private var standaloneGrantURL: URL?
    private var standaloneWatch: (any DispatchSourceFileSystemObject)?
    private var standaloneWatchTask: Task<Void, Never>?
    private let standaloneWatchFallback = FileGrantWatchFallback()
    private var standaloneReconcileTask: Task<Void, Never>?
    private var standaloneReconcilePending = false
    private var standaloneRecheckAfterOpen = false
    var onRecentsChanged: (([RecentFolder]) -> Void)?
    var canNavigate: Bool { fileURL != nil && window?.attachedSheet == nil }
    var gridShellVisible: Bool { gridShell != nil && !gridShell.isHidden }
    func toggleGridSidebar() { if gridShellVisible { gridShell.toggleSidebar() } }
    var gridSearchAvailable: Bool { gridShellVisible && !gridView.isHidden && gridShell.searchAvailable }
    private var inspectorHost: NSHostingView<MotionPolicyContent<InspectorPanel>>!
    private var inspectorOverlayMode = false
    var onOpenRequest: (() -> Void)?
    var accessAnnouncementObserver: ((String) -> Void)?
    var menuTracking: () -> Bool = { false }
    var appearanceAdapter: WindowAppearanceAdapter?

    override func showWindow(_ sender: Any?) {
        attachAccessMonitor()
        if let window { appearanceAdapter?.register(window) }
        super.showWindow(sender)
    }

    /// Under memory pressure the grid keeps only visible thumbnails; prefetch resumes when it ends.
    func memoryPressure(_ active: Bool) { gridView.setMemoryPressure(active) }

    init(pipeline: any ImagePipeline, preferencesStore: any DisplayPreferencesStore, accessServices: Task<AccessServices, Error>,
         motionPolicy: MotionPolicy, inspectorReader: (any InspectorMetadataReading)? = nil) {
        self.pipeline = pipeline
        self.accessServices = accessServices
        session = ViewerSession(preferencesStore: preferencesStore, imageLoader: ViewerImageLoader(trace: NativeFirstPreviewTrace(), presentation: pipeline as? any ImagePresentationPinning))
        canvas = CanvasInputBridge(frame: .zero, session: session)
        inspector = InspectorModel(reader: inspectorReader ?? WindowInspectorReader(services: accessServices))
        self.motionPolicy = motionPolicy
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
        inspectorHost = NSHostingView(rootView: inspectorRootView(overlay: false))
        inspectorHost.frame = InspectorPanelLayout.frame(in: content.bounds, grid: false)
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
        gridShell.onSelectFolder = { [weak self] folder in
            // A viewer page-22 tile has no grid root yet; the empty folder's scan root covers its children.
            guard let self, let rootID = self.gridFolderRoot ?? self.session.folderScan?.sourceSnapshot?.version.rootID
            else { return }
            self.openFolder(folder, rootID: rootID)
        }
        gridShell.session = session
        gridShell.onOpenRecent = { [weak self] folder in self?.openRecent(folder) }
        gridShell.onDropFolders = { [weak self] urls in self?.openInput(urls) }
        gridShell.mirrorEmptyFolderPage(to: stateHost)
        gridShell.onSort = { [weak self] action in self?.applyGridSort(action) }
        gridShell.onOpenSortMenu = { button, menu in
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button)
        }
        gridShell.sortConditions = { [weak self] in self?.session.folderConditions ?? .init() }
        content.addSubview(gridShell)
        gridView = GridBrowserView(frame: NSRect(origin: .zero, size: gridShell.mainFrame.size))
        gridView.thumbnailLoader = { [accessServices, pipeline] entry, rootID, coverage, priority in
            let services = try await accessServices.value
            let context = try await services.monitor.readContext(for: rootID)
            do {
                let source = try await AccessImageSource.open(.root(rootID, file: entry.url),
                    access: services.files, pipeline: pipeline, accessPermit: context.permit)
                do {
                    let result = try await source.image(covering: coverage, priority: priority)
                    await source.close()
                    try Task.checkCancellation()
                    try context.permit.check()
                    return result
                } catch { await source.close(); throw error }
            } catch {
                if !Task.isCancelled, !(error is CancellationError) { await services.monitor.reportReadFailure(rootID, from: context.stamp) }
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
            self.syncInspector()
            return self.session.selection
        }
        gridView.onClearSelection = { [weak self] in
            self?.session.clearSelection()
            self?.syncInspector()
            return self?.session.selection ?? BrowserSelection()
        }
        gridView.onCurrentChange = { [weak self] id in
            self?.session.focus(id)
            self?.syncInspector()
        }
        gridView.onDeselect = { [weak self] in
            guard let self else { return }
            self.session.clearSelection()
            self.gridView.synchronizeSelection(self.session.selection)
        }
        gridShell.mainContent.addSubview(gridView)
        lostAccessView = LostAccessStateView(frame: gridShell.mainContent.bounds)
        lostAccessView.autoresizingMask = [.width, .height]
        lostAccessView.isHidden = true
        lostAccessView.setAccessibilityHidden(true)
        lostAccessView.onReselectFolder = { [weak self] in self?.chooseAccessFolder(reselect: true) }
        lostAccessView.onChooseAnotherFolder = { [weak self] in self?.chooseAccessFolder(reselect: false) }
        gridShell.mainContent.addSubview(lostAccessView)
        observeAccessMotionPolicy()
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
        attachAccessMonitor()
    }

    private func observeAccessMotionPolicy() {
        withObservationTracking {
            lostAccessView.reduceMotion = motionPolicy.reduceMotion
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeAccessMotionPolicy() }
        }
    }

    private func attachAccessMonitor() {
        guard accessObserver == nil, accessAttachmentTask == nil else { return }
        let attachment = accessAttachmentGeneration
        accessAttachmentTask = Task { @MainActor [weak self, accessServices] in
            guard let services = try? await accessServices.value, let self,
                  !Task.isCancelled, self.accessAttachmentGeneration == attachment else { return }
            let monitor = services.monitor
            self.bindAccessMonitor(monitor)
            await monitor.start()
            guard !Task.isCancelled, self.accessAttachmentGeneration == attachment else { return }
            self.accessAttachmentTask = nil
            self.applyCurrentAccessState()
        }
    }
    private func bindAccessMonitor(_ monitor: AccessMonitor) {
        guard accessObserver == nil else { return }
        accessMonitor = monitor
        accessObserver = monitor.state.observe { [weak self] change in
            guard let self else { return }
            if case .lost(let id, let counter) = change { self.handleAccessLoss(id, counter: counter) }
        }
    }
    private func applyCurrentAccessState() {
        guard let root = gridFolderRoot ?? presentationRootID,
              let snapshot = accessMonitor?.state.snapshot(for: root),
              case .lost = snapshot.availability else { return }
        handleAccessLoss(root, counter: snapshot.counter)
    }
    private func leaveWaitingAccess() {
        accessAnnouncementTask?.cancel(); accessAnnouncementTask = nil
        waitingAccessPosition = nil
        accessLossCause = nil
        lostAccessView?.isHidden = true
        lostAccessView?.setAccessibilityHidden(true)
    }
    private func handleAccessLoss(_ rootID: AccessRootID, counter: UInt64,
                                  initialPosition: WaitingAccessPosition? = nil) {
        guard gridFolderRoot == rootID || presentationRootID == rootID || waitingAccessPosition?.rootID == rootID else { return }
        let cause: AccessLossCause
        if case .lost(let known)? = accessMonitor?.state.snapshot(for: rootID)?.availability { cause = known }
        else { cause = .unknown }
        if waitingAccessPosition?.rootID == rootID {
            // A cause refinement or another eject during recovery belongs to the
            // same waiting episode; retain the original private position.
            waitingAccessPosition?.counter = counter
            accessLossCause = cause
            showWaitingAccessState()
            return
        }
        let folder = gridFolderURL ?? session.folderScan?.sourceSnapshot?.version.folder
            ?? fileURL?.deletingLastPathComponent()
        guard let folder else { return }
        waitingAccessPosition = initialPosition ?? WaitingAccessPosition(rootID: rootID, folderURL: folder,
            currentItemID: session.currentItemID ?? session.folderScan?.currentItemID,
            currentImageURL: fileURL, wasViewing: session.mode == .viewing,
            conditions: session.folderConditions, recursive: session.folderRecursiveEnabled,
            loop: session.folderLoopEnabled, searchTerm: gridSearch.term,
            scrollOffset: gridView.contentOffset, counter: counter)
        accessLossCause = cause

        // Revoke every visible/AX value synchronously. Cancellation below only
        // retires I/O; it does not provide the presentation boundary.
        canvas.showFailure()
        inspector.select(itemID: nil, url: nil, access: nil)
        inspectorHost.isHidden = true
        gridView.clearPresentation()
        gridShell.folderTree.clear()
        gridShell.showFolder(nil)
        gridShell.setSearchTerm("")
        gridShell.showSearchEmpty(false)
        WindowImageTitle.apply(to: window, imageURL: nil)
        retryIntent = nil; retryFromFolderScan = false
        fileURL = nil
        gridProjection = FolderGridProjection()
        viewedRefreshVersion = nil
        pendingGridCurrentItemID = nil
        gridPreviewScrollOffset = nil
        gridFolderRoot = nil; gridFolderURL = nil
        folderEntryRestore = nil
        session.completeFolderEntry()
        accessIntent.invalidate()
        endInput()
        searchProjection.cancel()
        cancelSidebarTree()
        standaloneWatch?.cancel(); standaloneWatch = nil
        standaloneWatchTask?.cancel(); standaloneWatchTask = nil
        standaloneReconcileTask?.cancel(); standaloneReconcileTask = nil
        standaloneGrantURL = nil; standaloneReconcilePending = false; standaloneRecheckAfterOpen = false
        navigationTask?.cancel(); navigationTask = nil
        session.endFolderScan()
        session.enterFolderGrid(items: [], sourceVersion: .init(0))
        scanReadContext = nil; presentationReadContext = nil
        chromeOverlay.refresh(session: session)
        stateHost.refresh()
        showWaitingAccessState()
    }
    func showWaitingAccessState() {
        guard let position = waitingAccessPosition else { return }
        presentation.showGrid(reading: true)
        stateHost.isHidden = true
        stateHost.setAccessibilityHidden(true)
        inspectorHost.isHidden = true
        let copy = lostAccessCopy(position)
        lostAccessView.display(cause: accessLossCause ?? .unknown, text: copy)
        lostAccessView.isHidden = false
        lostAccessView.setAccessibilityHidden(false)
        gridShell.mainContent.addSubview(lostAccessView, positioned: .above, relativeTo: nil)
        layoutInspector()
        gridShell.layoutSubtreeIfNeeded()
        lostAccessView.layoutSubtreeIfNeeded()
        if let first = lostAccessView.buttons.first, let last = lostAccessView.buttons.last {
            gridShell.linkKeyViews(from: first, through: last)
            _ = window?.makeFirstResponder(first)
        }
        announceAccessLoss(position.rootID, title: copy.title)
    }
    private func lostAccessCopy(_ position: WaitingAccessPosition) -> LostAccessStateText {
        let disk = accessLossCause == .diskNotConnected
        let title: String
        if disk, let name = accessMonitor?.volumeName(for: position.rootID) {
            title = String(format: String(localized: "External Disk “%@” Is Not Connected"), name)
        } else {
            title = disk ? String(localized: "External Disk Is Not Connected") : String(localized: "Unable to Access This Folder")
        }
        let detail = disk
            ? String(localized: "“%@” is on an external disk.\nConnect the disk and picsee will verify access before restoring your place.")
            : String(localized: "picsee can’t read “%@” right now. Choose this folder again, or choose another folder to continue.")
        return LostAccessStateText(title: title, detail: String(format: detail, position.folderURL.lastPathComponent),
            waiting: String(localized: "Waiting for the disk…"), reselect: String(localized: "Choose Folder Again…"),
            chooseOther: String(localized: "Choose Another Folder…"))
    }
    private func announceAccessLoss(_ rootID: AccessRootID, title: String) {
        if let accessMonitor {
            guard accessMonitor.claimAnnouncement(for: rootID, recovered: false) else { return }
            postAccessAnnouncement(([title] + lostAccessView.buttons.map(\.title)).joined(separator: ". "))
        } else if accessAnnouncementTask == nil {
            accessAnnouncementTask = Task { @MainActor [weak self, accessServices] in
                guard let services = try? await accessServices.value, !Task.isCancelled,
                      let self, self.waitingAccessPosition?.rootID == rootID else { return }
                self.bindAccessMonitor(services.monitor)
                self.accessAnnouncementTask = nil
                self.announceAccessLoss(rootID, title: title)
            }
        }
    }
    private func postAccessAnnouncement(_ message: String) {
        accessAnnouncementObserver?(message)
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
    private func chooseAccessFolder(reselect: Bool) {
        guard let position = waitingAccessPosition, let window, window.attachedSheet == nil else { return }
        let operation = accessIntent.current
        let panel = NSOpenPanel()
        panel.title = String(localized: reselect ? "Reconnect Folder" : "Grant Folder Access")
        panel.prompt = String(localized: reselect ? "Choose Folder Again…" : "Grant Folder")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = position.folderURL.deletingLastPathComponent()
        panel.beginSheetModal(for: window) { [weak self] response in
            panel.orderOut(nil)
            DispatchQueue.main.async { [weak self] in
                guard let self, operation.isCurrent, self.waitingAccessPosition?.rootID == position.rootID else { return }
                guard response == .OK, let url = panel.url else { self.showWaitingAccessState(); return }
                if !reselect { self.openGrantedFolder(url); return }
                self.navigationTask?.cancel()
                self.navigationTask = Task { @MainActor [weak self, accessServices] in
                    do {
                        let services = try await operation.wait { try await accessServices.value }
                        let target = try await operation.wait { try await services.reconnect(position.rootID, folder: url) }
                        guard let self, operation.isCurrent, self.waitingAccessPosition?.rootID == position.rootID else { return }
                        self.refreshRecents()
                        self.openFolder(target.url, rootID: target.rootID)
                    } catch {
                        guard let self, operation.isCurrent else { return }
                        self.showWaitingAccessState()
                    }
                }
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    func windowDidResize(_ notification: Notification) {
        gridShell.layoutSubtreeIfNeeded()
        canvas.synchronizeViewport()
        layoutInspector()
    }
    func windowDidEnterFullScreen(_ notification: Notification) { canvas.synchronizeViewport(); session.activity() }
    func windowDidExitFullScreen(_ notification: Notification) { canvas.synchronizeViewport(); session.activity() }

    func open(_ url: URL, accessRequest: AccessRequest? = nil, fromFolderScan: Bool = false) {
        if fromFolderScan, waitingAccessPosition != nil { return }
        if !fromFolderScan {
            leaveWaitingAccess()
            if case .root(let id, _)? = accessRequest { presentationRootID = id }
            else { presentationRootID = nil }
            scanReadContext = nil
            presentationReadContext = nil
            searchProjection.cancel()
            standaloneWatch?.cancel(); standaloneWatch = nil
            standaloneWatchTask?.cancel(); standaloneWatchTask = nil
            standaloneReconcileTask?.cancel(); standaloneGrantURL = nil
            standaloneReconcilePending = false
            standaloneRecheckAfterOpen = false
            session.endFolderScan()
            session.leaveBrowsing()
            session.completeFolderEntry()
            folderEntryRestore = nil
            gridFolderRoot = nil
            gridFolderURL = nil
            cancelSidebarTree()
            gridShell.showFolder(nil)
            presentation.showViewer()
            inspectorHost.isHidden = !inspectorVisible
            layoutInspector()
        }
        retryIntent = ViewerRetryIntent(fileURL: url, accessRequest: accessRequest)
        retryFromFolderScan = fromFolderScan
        if !fromFolderScan { _ = accessIntent.begin() }
        refreshRecents()
        filesystemLogger.notice("Open file=\(url.lastPathComponent, privacy: .private)")
        fileURL = url
        window?.representedURL = url
        syncInspector(refresh: true)
        if !fromFolderScan { navigationTask?.cancel() }
        let scale = window?.backingScaleFactor ?? 1
        let maximum = max(1, Int(ceil(max(canvas.bounds.width, canvas.bounds.height) * scale)))
        session.openImage(url, maximumPixelSize: maximum, opener: ViewerImageLoader.accessOpener(intent: accessIntent) { [weak self, accessServices, pipeline] operation in
            let services = try await operation.wait { try await accessServices.value }
            let request: AccessRequest
            if let accessRequest { request = accessRequest }
            else {
                let root = try await operation.wait { await services.files.rootCovering(url) }
                request = root.map { .root($0, file: url) } ?? .fileGrant(url)
            }
            try operation.check()
            let context: AccessMonitor.ReadContext?
            if case .root(let id, _) = request {
                guard let self else { throw CancellationError() }
                self.bindAccessMonitor(services.monitor)
                self.presentationRootID = id
                self.applyCurrentAccessState()
                context = try await operation.wait { try await services.monitor.readContext(for: id) }
                self.presentationReadContext = context
                self.applyCurrentAccessState()
            } else { context = nil }
            try operation.check()
            do {
                return try await AccessImageSource.open(request, access: services.files, pipeline: pipeline,
                    accessPermit: context?.permit)
            } catch {
                if let context, !Task.isCancelled, case .root(let id, _) = request, !(error is CancellationError) {
                    await services.monitor.reportReadFailure(id, from: context.stamp)
                }
                throw error
            }
        })
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
        if !fromFolderScan {
            let operation = accessIntent.current
            let inputOperation = inputIntent.current
            let scanGeneration = UUID()
            Task { [weak self, accessServices] in
                guard let self, let services = try? await accessServices.value else { return }
                let root: AccessRootID?
                if case .root(let explicitRoot, _)? = accessRequest { root = explicitRoot }
                else { root = await services.files.rootCovering(url) }
                guard operation.isCurrent, self.fileURL == url else { return }
                if let root {
                    self.bindAccessMonitor(services.monitor)
                    self.presentationRootID = root
                    self.applyCurrentAccessState()
                    guard operation.isCurrent, self.rootScanAdmission.claim(scanGeneration) else { return }
                    let scan = self.folderScanner(services)
                    do {
                        let context = try await operation.wait { try await services.monitor.readContext(for: root) }
                        self.scanReadContext = context
                        try await scan.begin(folder: url.deletingLastPathComponent(), rootID: root,
                            input: url, canPresent: { operation.isCurrent && inputOperation.isCurrent && context.permit.isCurrent }).value
                    } catch {
                        self.filesystemLogger.error("Background folder scan outcome=failed error=\(String(describing: error), privacy: .private)")
                    }
                } else {
                    self.standaloneGrantURL = url
                    self.watchStandaloneFile(at: url)
                    self.reconcileStandaloneImage()
                }
            }
        }
    }

    private func watchStandaloneFile(at url: URL) {
        standaloneWatch?.cancel(); standaloneWatch = nil
        standaloneWatchTask?.cancel()
        guard let grant = standaloneGrantURL else { return }
        let operation = accessIntent.current
        standaloneWatchTask = Task { [weak self, accessServices] in
            guard let self, let services = try? await accessServices.value else { return }
            let descriptor: Int32
            do {
                descriptor = try await FileGrantWatchDescriptor.open(grant: grant, access: services.files) {
                    Darwin.open($0.path, O_EVTONLY)
                }
            } catch {
                self.reportStandaloneWatchFailure(grant)
                return
            }
            guard descriptor >= 0 else {
                self.reportStandaloneWatchFailure(grant)
                return
            }
            guard !Task.isCancelled, operation.isCurrent, self.standaloneGrantURL == grant else {
                _ = Darwin.close(descriptor)
                return
            }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete, .revoke], queue: .main)
            source.setEventHandler { [weak self] in self?.reconcileStandaloneImage() }
            source.setCancelHandler { _ = Darwin.close(descriptor) }
            self.standaloneWatch = source
            source.resume()
        }
    }

    private func reportStandaloneWatchFailure(_ grant: URL) {
        guard standaloneWatchFallback.recordFailure(grant) else { return }
        filesystemLogger.warning("File grant vnode watch unavailable; foreground reconciliation remains active file=\(grant.lastPathComponent, privacy: .private)")
    }

    func reconcileStandaloneImage() {
        guard let grant = standaloneGrantURL else { return }
        if standaloneReconcileTask != nil { standaloneReconcilePending = true; return }
        let operation = accessIntent.current
        standaloneReconcileTask = Task { [weak self, accessServices, pipeline] in
            defer {
                self?.standaloneReconcileTask = nil
                if self?.standaloneReconcilePending == true {
                    self?.standaloneReconcilePending = false
                    self?.reconcileStandaloneImage()
                }
            }
            guard let self, let services = try? await accessServices.value, operation.isCurrent else { return }
            var checkedURL = grant
            do {
                let resolved = try await services.files.resolveFileGrant(grant)
                checkedURL = resolved
                let scale = self.window?.backingScaleFactor ?? 1
                let maximum = max(1, Int(ceil(max(self.canvas.bounds.width, self.canvas.bounds.height) * scale)))
                let prepared = try await services.files.withLease(.fileGrant(grant)) { lease in
                    try await pipeline.request(for: lease.url, maximumPixelSize: maximum)
                }
                guard operation.isCurrent else { return }
                let opening = switch self.session.imageLoader.phase {
                case .opening, .refining: true
                default: false
                }
                if resolved == self.fileURL, self.session.imageLoader.presented == nil, opening {
                    self.standaloneRecheckAfterOpen = true
                    return
                }
                if resolved != self.fileURL || prepared.renderKey?.revision != self.session.imageLoader.presented?.key.revision {
                    self.open(resolved, accessRequest: .fileGrant(grant), fromFolderScan: true)
                    self.watchStandaloneFile(at: resolved)
                }
            } catch {
                guard operation.isCurrent else { return }
                var error = error
                // The file can move or reach the Trash between resolving the grant and reading it.
                if !(error is FileAccessError), !FileManager.default.fileExists(atPath: checkedURL.path) {
                    do {
                        let current = try await services.files.resolveFileGrant(grant)
                        guard operation.isCurrent else { return }
                        let follows = current != checkedURL && FileManager.default.fileExists(atPath: current.path)
                        self.filesystemLogger.notice("File grant re-resolved after failed read outcome=\(follows ? "moved" : "missing", privacy: .public) file=\(grant.lastPathComponent, privacy: .private)")
                        if follows {
                            self.open(current, accessRequest: .fileGrant(grant), fromFolderScan: true)
                            self.watchStandaloneFile(at: current)
                            return
                        }
                    } catch let resolution {
                        guard operation.isCurrent else { return }
                        self.filesystemLogger.notice("File grant re-resolved after failed read outcome=failed error=\(String(describing: resolution), privacy: .private) file=\(grant.lastPathComponent, privacy: .private)")
                        error = resolution
                    }
                }
                if let accessError = error as? FileAccessError, case .fileDeleted = accessError {
                    self.clearFolderImageForNoMatches()
                } else if error is FileAccessError || !FileManager.default.fileExists(atPath: checkedURL.path) {
                    self.clearFolderImageForNoMatches()
                    self.requestFileReconnection(grant)
                } else {
                    self.open(checkedURL, accessRequest: .fileGrant(grant), fromFolderScan: true)
                }
            }
        }
    }

    private func requestFileReconnection(_ original: URL) {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "This File Can’t Be Opened")
        alert.informativeText = String(localized: "Choose this image again to reconnect access.")
        alert.addButton(withTitle: String(localized: "Choose File Again…"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.directoryURL = original.deletingLastPathComponent()
            panel.beginSheetModal(for: window) { result in
                if result == .OK, let url = panel.url { self?.openInput([url]) }
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        accessAttachmentGeneration = UUID()
        accessAttachmentTask?.cancel(); accessAttachmentTask = nil
        if let accessObserver { accessMonitor?.state.removeObserver(accessObserver) }
        accessObserver = nil; accessMonitor = nil
        leaveWaitingAccess(); presentationRootID = nil; scanReadContext = nil; presentationReadContext = nil
        cancelSidebarTree()
        gridShell.showFolder(nil)
        standaloneWatch?.cancel(); standaloneWatch = nil
        standaloneWatchTask?.cancel(); standaloneWatchTask = nil
        standaloneReconcileTask?.cancel(); standaloneGrantURL = nil
        standaloneReconcilePending = false
        standaloneRecheckAfterOpen = false
        gridView.clearPresentation()
        gridShell.folderTree.clear()
        gridShell.setSearchTerm("")
        gridShell.showSearchEmpty(false)
        gridSearch.reset()
        gridProjection = FolderGridProjection()
        viewedRefreshVersion = nil
        pendingGridCurrentItemID = nil
        gridPreviewScrollOffset = nil
        folderEntryRestore = nil
        session.completeFolderEntry()
        session.enterFolderGrid(items: [], sourceVersion: .init(0))
        inspector.select(itemID: nil, url: nil, access: nil)
        gridFolderRoot = nil
        gridFolderURL = nil
        endInput()
        // A reused window starts fresh: Cancel Reading must not bring back what was shown before the close.
        folderEntryRestore = nil
        session.completeFolderEntry()
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
                latestRecents = folders
                updateEmptyFolderState()
            } catch { if operation.isCurrent { showAccessError(error) } }
        }
    }

    func openRecent(_ folder: RecentFolder) {
        // A folder entry records the File Preview Set before ending it, so Cancel Reading can walk it again.
        inputIntent.invalidate()
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
        inputIntent.invalidate()
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
        standaloneWatch?.cancel(); standaloneWatch = nil
        standaloneWatchTask?.cancel(); standaloneWatchTask = nil
        standaloneReconcileTask?.cancel(); standaloneGrantURL = nil
        standaloneReconcilePending = false
        standaloneRecheckAfterOpen = false
        if folderEntryRestore == nil { folderEntryRestore = makeFolderEntryRestore() }
        leaveWaitingAccess()
        presentationRootID = rootID
        scanReadContext = nil; presentationReadContext = nil
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
        inspector.select(itemID: nil, url: nil, access: nil)
        gridFolderRoot = rootID
        gridFolderURL = folder
        applyCurrentAccessState()
        if waitingAccessPosition != nil { return }
        sidebarKnownCounts.removeAll()
        loadSidebarTree(folder, rootID: rootID, count: nil)
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
                self.bindAccessMonitor(services.monitor)
                self.applyCurrentAccessState()
                try operation.check()
                let context = try await operation.wait { try await services.monitor.readContext(for: rootID) }
                self.scanReadContext = context
                self.applyCurrentAccessState()
                try operation.check()
                try await folderScanner(services).begin(folder: folder, rootID: rootID,
                    canPresent: { authority.isCurrent && context.permit.isCurrent }).value
            } catch {
                if operation.isCurrent, generation == current {
                    if error as? FileAccessError == .corruptStore { showAccessError(error) }
                    else { promptForFolder(folder, currentImage: nil, direction: .next) }
                }
            }
        }
    }

    private func loadSidebarTree(_ folder: URL, rootID: AccessRootID, count: Int?) {
        cancelSidebarTree()
        let generation = sidebarTreeGeneration
        gridShell.showFolderTree(current: GridSidebarFolder(url: folder, count: count), parent: nil, children: [])
        sidebarTreeTask = Task(priority: .utility) { [weak self, accessServices] in
            var failureContext: AccessMonitor.ReadContext?
            var monitor: AccessMonitor?
            do {
                let services = try await accessServices.value
                monitor = services.monitor
                let context = try await services.monitor.readContext(for: rootID)
                failureContext = context
                try Task.checkCancellation()
                try context.permit.check()
                guard let self, self.sidebarTreeGeneration == generation,
                    self.gridFolderURL == folder else { return }
                let browser = self.sidebarBrowserOverride ?? SidebarFolderBrowser(
                    access: services.files, enumerator: SystemSidebarFolderEnumerator())
                let loader = SidebarFolderLoadSession(browser: browser)
                self.sidebarLoader = loader
                loader.start(folder: folder, rootID: rootID, onRows: { [weak self] children, parentURL in
                    guard let self, self.sidebarTreeGeneration == generation,
                        self.gridFolderURL == folder, context.permit.isCurrent else { return }
                    self.gridShell.showFolderTree(current: GridSidebarFolder(url: folder, count: self.sidebarKnownCounts[folder] ?? count),
                        parent: parentURL.map { GridSidebarFolder(url: $0, count: self.sidebarKnownCounts[$0]) },
                        children: children.map { GridSidebarFolder(url: $0) })
                }, onCount: { [weak self] child, imageCount in
                    guard let self, self.sidebarTreeGeneration == generation,
                        self.gridFolderURL == folder, context.permit.isCurrent else { return }
                    self.sidebarKnownCounts[child] = imageCount
                    self.gridShell.updateFolderCount(imageCount, for: child)
                }, onFailure: { [weak self] _ in
                    guard let self, self.sidebarTreeGeneration == generation,
                          self.gridFolderURL == folder, context.permit.isCurrent else { return }
                    Task { await services.monitor.reportReadFailure(rootID, from: context.stamp) }
                })
                let watch = try await services.watch.subscribe(rootID: rootID, folder: folder,
                    recursive: true, onChange: { [weak self] in
                        Task { @MainActor [weak self] in
                            guard let self, self.sidebarTreeGeneration == generation,
                                self.gridFolderURL == folder else { return }
                            self.loadSidebarTree(folder, rootID: rootID, count: nil)
                        }
                    })
                guard !Task.isCancelled, self.sidebarTreeGeneration == generation, context.permit.isCurrent else {
                    await watch.cancel()
                    return
                }
                self.sidebarWatchSubscription = watch
            } catch {
                if let failureContext, !Task.isCancelled, !(error is CancellationError) {
                    await monitor?.reportReadFailure(rootID, from: failureContext.stamp)
                }
            }
        }
    }
    private func cancelSidebarTree() {
        sidebarTreeGeneration = UUID()
        sidebarTreeTask?.cancel()
        sidebarTreeTask = nil
        sidebarLoader?.cancel()
        sidebarLoader = nil
        if let watch = sidebarWatchSubscription { Task { await watch.cancel() } }
        sidebarWatchSubscription = nil
        sidebarKnownCounts.removeAll()
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
                    bindAccessMonitor(services.monitor)
                    presentationRootID = root
                    applyCurrentAccessState()
                    try operation.check()
                    let context = try await operation.wait { try await services.monitor.readContext(for: root) }
                    scanReadContext = context
                    try await folderScanner(services).begin(folder: file.deletingLastPathComponent(), rootID: root,
                        input: file, pending: direction, canPresent: { authority.isCurrent && context.permit.isCurrent }).value
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
                            bindAccessMonitor(services.monitor)
                            presentationRootID = id
                            applyCurrentAccessState()
                            try operation.check()
                            let context = try await operation.wait { try await services.monitor.readContext(for: id) }
                            scanReadContext = context
                            try await folderScanner(services).begin(folder: currentImage.deletingLastPathComponent(), rootID: id,
                                input: currentImage, pending: direction, canPresent: { authority.isCurrent && context.permit.isCurrent }).value
                        } else {
                            promptForFolder(folder, currentImage: currentImage, direction: direction, mismatch: true)
                        }
                    } else { inputIntent.invalidate(); openFolder(chosen, rootID: id) }
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
        if let view = window?.firstResponder as? NSView,
           view === gridView || view.isDescendant(of: gridView) { return .canvas }
        if isGridSearchFocused { return .textInput }
        if isGridShellFocused { return .tools }
        if window?.firstResponder is NSTextInputClient { return .textInput }
        return window?.firstResponder === canvas ? .canvas : .panel
    }
    private var isGridSearchFocused: Bool {
        guard gridShell != nil, !gridShell.isHidden, !gridShell.searchField.isHidden,
              let responder = window?.firstResponder else { return false }
        return responder === gridShell.searchField || responder === gridShell.searchField.currentEditor()
    }
    struct GridSearchEditorState {
        let selection: NSRange?
    }
    func captureGridSearchEditor() -> GridSearchEditorState? {
        guard isGridSearchFocused else { return nil }
        return GridSearchEditorState(selection: (gridShell.searchField.currentEditor() as? NSTextView)?.selectedRange)
    }
    func restoreGridSearchEditor(_ state: GridSearchEditorState) {
        gridShell.preserveRestoredSearchEditorThroughMenuDispatch()
        gridShell.focusSearch()
        if let selection = state.selection {
            (gridShell.searchField.currentEditor() as? NSTextView)?.selectedRange = selection
        }
    }
    private var isGridShellFocused: Bool {
        guard gridShell != nil, !gridShell.isHidden,
              let view = window?.firstResponder as? NSView else { return false }
        return view === gridShell || view.isDescendant(of: gridShell)
    }
    private var isInspectorFocused: Bool {
        guard inspectorHost != nil, let view = window?.firstResponder as? NSView else { return false }
        return view === inspectorHost || view.isDescendant(of: inspectorHost)
    }
    private func focusInspectorCloseButton() {
        func findClose(in view: NSView) -> NSView? {
            if view.accessibilityIdentifier() == "inspector.close" { return view }
            return view.subviews.lazy.compactMap(findClose).first
        }
        session.updateFocus(.panel)
        inspectorHost.layoutSubtreeIfNeeded()
        if let close = findClose(in: inspectorHost) { _ = window?.makeFirstResponder(close) }
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
        inspectorHost.isHidden = !visible
        layoutInspector()
        syncInspector()
    }
    /// Public toggle for the grid footer's later info button.
    func toggleInspector() { _ = route(.inspector, from: .button) }
    private func layoutInspector() {
        guard inspectorHost != nil else { return }
        if let width = window?.contentView?.bounds.width {
            let overlay = InspectorPanelLayout.overlaysContent(at: width)
            if overlay != inspectorOverlayMode {
                inspectorOverlayMode = overlay
                inspectorHost.rootView = inspectorRootView(overlay: overlay)
            }
        }
        presentation.layoutInspector(visible: inspectorVisible && !inspectorHost.isHidden)
        canvas.synchronizeViewport()
    }
    private func inspectorRootView(overlay: Bool) -> MotionPolicyContent<InspectorPanel> {
        MotionPolicyContent(policy: motionPolicy) {
            InspectorPanel(model: inspector, session: session, topInset: overlay ? 12 : 0,
                close: { [weak self] in _ = self?.route(.inspector, from: .button) },
                restoreCanvasFocus: { [weak self] in
                    guard let self else { return }
                    _ = self.window?.makeFirstResponder(self.gridView.isHidden ? self.canvas : self.gridView.collectionView)
                }, updateFocus: { [weak self] focus in self?.session.updateFocus(focus) },
                allowsCloseFocus: { [weak self] in self?.isGridSearchFocused != true })
        }
    }
    private func syncInspector(refresh: Bool = false) {
        guard waitingAccessPosition == nil, session.inspectorFocus.isVisible else {
            inspector.select(itemID: nil, url: nil, access: nil); return
        }
        if !gridView.isHidden {
            guard let id = session.selection.currentItemID, let entry = gridProjection.entry(for: id),
                  let root = gridFolderRoot else {
                inspector.select(itemID: nil, url: nil, access: nil); return
            }
            let revisionKey = "\(entry.resourceIdentifier.map { "id:\($0)" } ?? "id:nil")|" +
                "\(entry.fileSize.map { "bytes:\($0)" } ?? "bytes:nil")|" +
                "\(entry.modificationDate.map { "modified:\($0.timeIntervalSinceReferenceDate)" } ?? "modified:nil")"
            inspector.select(itemID: id, url: entry.url, access: .root(root, file: entry.url),
                revision: revisionKey, refresh: refresh)
        } else if let fileURL {
            let access = retryIntent?.accessRequest ?? gridFolderRoot.map { AccessRequest.root($0, file: fileURL) } ?? .fileGrant(fileURL)
            let revision = session.imageLoader.presented?.key.revision
            let revisionKey = revision.map { "\($0.resourceIdentifier ?? "")|\($0.byteCount)|\($0.modificationDate?.timeIntervalSinceReferenceDate ?? -1)" }
            inspector.select(itemID: session.currentItemID, url: fileURL, access: access,
                revision: revisionKey, refresh: refresh)
        } else { inspector.select(itemID: nil, url: nil, access: nil) }
    }
    func applyFocus(_ focus: FocusContext) {
        guard focus == .canvas else { return }
        _ = window?.makeFirstResponder(gridView.isHidden ? canvas : gridView.collectionView)
    }
    func presentGridItem(_ id: ItemID) {
        guard let entry = gridProjection.entry(for: id), let rootID = gridFolderRoot,
              gridProjection.snapshot?.version.rootID == rootID else { return }
        searchProjection.cancel()
        presentation.showViewer()
        inspectorHost.isHidden = !inspectorVisible
        layoutInspector()
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
    func showGrid(reading: Bool = false) {
        if waitingAccessPosition != nil { showWaitingAccessState(); return }
        presentation.showGrid(reading: reading)
        inspectorHost.isHidden = reading || !inspectorVisible
        layoutInspector()
        if reading {
            showReadingState()
        } else {
            let current = pendingGridCurrentItemID ?? session.selection.currentItemID
            pendingGridCurrentItemID = nil
            gridView.activate(currentItemID: current)
        }
        syncInspector(refresh: !reading)
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
        GridSearchReconciler.present(filtered, source: source, session: session,
            search: gridSearch, grid: gridView, shell: gridShell,
            onReconciled: { [weak self] in self?.syncInspectorAfterGridReconciliation() })
    }
    private func syncInspectorAfterGridReconciliation() { syncInspector() }
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
        navigationTask?.cancel()
        _ = accessIntent.begin()
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
        let priorPresentationRoot = presentationRootID
        let priorScanContext = scanReadContext, priorImageContext = presentationReadContext
        session.beginFolderEntry(shownImage: fileURL, hasCompleteGrid: completeGrid)
        return { [weak self] target in
            guard let self else { return }
            gridFolderRoot = root
            gridFolderURL = folder
            presentationRootID = priorPresentationRoot
            scanReadContext = priorScanContext
            presentationReadContext = priorImageContext
            applyCurrentAccessState()
            guard waitingAccessPosition == nil else { return }
            if let root, let folder { loadSidebarTree(folder, rootID: root, count: nil) }
            else { cancelSidebarTree() }
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
                inspectorHost.isHidden = !inspectorVisible
                layoutInspector()
                open(file, accessRequest: request, fromFolderScan: fromFolder || root != nil)
            case .empty:
                restoreEmptyFolderEntry()
            }
        }
    }
    private func restoreEmptyFolderEntry() {
        presentationRootID = nil; scanReadContext = nil; presentationReadContext = nil
        cancelSidebarTree()
        gridShell.showFolder(nil)
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
        if waitingAccessPosition != nil, window?.attachedSheet == nil, !menuTracking(), event.keyCode == 53 { return true }
        if event.keyCode == 34, event.modifierFlags.contains(.command),
           event.modifierFlags.intersection([.control, .option]).isEmpty,
           !menuTracking() {
            let searchEditor = captureGridSearchEditor()
            let handled = route(.inspector, from: .key)
            if handled, let searchEditor { restoreGridSearchEditor(searchEditor) }
            return handled
        }
        if !gridView.isHidden, !isGridSearchFocused, focusContext != .textInput,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if event.keyCode == 49 { return route(.preview, from: .key) }
            if event.keyCode == 36 || event.keyCode == 76 { return route(.enter, from: .key) }
        }
        if InspectorEscapePolicy.handlesEscape(inspectorVisible: inspectorVisible,
            menuTracking: menuTracking(), focus: focusContext, keyCode: event.keyCode,
            gridSearchFocused: isGridSearchFocused) {
            return route(.escape, from: .key)
        }
        guard !menuTracking(), inspectorVisible else { return false }
        if !gridView.isHidden, event.keyCode == 48 {
            let reverse = event.modifierFlags.contains(.shift)
            if isInspectorFocused {
                _ = window?.makeFirstResponder(reverse ? gridShell.lastFooterKeyView : gridView.collectionView)
                return true
            }
            if focusContext == .canvas {
                if reverse { focusInspectorCloseButton() }
                else { _ = window?.makeFirstResponder(gridShell.firstFooterKeyView) }
                return true
            }
            if isGridSearchFocused || isGridShellFocused {
                let current = isGridSearchFocused ? gridShell.searchField : window?.firstResponder as? NSView
                if let current, let adjacent = gridShell.adjacentFooterKeyView(to: current, reverse: reverse) {
                    _ = window?.makeFirstResponder(adjacent)
                } else if reverse {
                    _ = window?.makeFirstResponder(gridView.collectionView)
                } else {
                    focusInspectorCloseButton()
                }
                return true
            }
        }
        if event.keyCode == 48 && session.inspectorFocus.focus == .canvas {
            session.tab(reverse: event.modifierFlags.contains(.shift))
            return true
        }
        guard focusContext != .canvas else { return false }
        if event.keyCode == 48 && (focusContext == .tools || event.modifierFlags.contains(.shift)) {
            session.tab(reverse: event.modifierFlags.contains(.shift))
            return true
        }
        return false
    }
    func windowDidUpdate(_ notification: Notification) {
        stateHost.refresh()
        if waitingAccessPosition != nil {
            stateHost.isHidden = true
            stateHost.setAccessibilityHidden(true)
        }
        if inspectorVisible { syncInspector() }
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
        guard waitingAccessPosition == nil else { return }
        canvas.install(image)
        WindowImageTitle.apply(to: window, imageURL: fileURL)
        stateHost.refresh()
        if standaloneRecheckAfterOpen {
            standaloneRecheckAfterOpen = false
            reconcileStandaloneImage()
        }
    }
    func imageLoadFailed(_ error: any Error) {
        canvas.showFailure()
        WindowImageTitle.apply(to: window, imageURL: nil)
        let cancelled = session.dismissCancelledImageFailure(error)
        stateHost.refresh()
        if standaloneRecheckAfterOpen {
            standaloneRecheckAfterOpen = false
            reconcileStandaloneImage()
        }
        if cancelled { return }
        if let root = presentationRootID, let context = presentationReadContext, let monitor = accessMonitor {
            let operation = accessIntent.current
            Task { @MainActor [weak self] in
                await monitor.reportReadFailure(root, from: context.stamp)
                guard operation.isCurrent, let self else { return }
                if error is FileAccessError { self.showAccessError(error) }
            }
            return
        }
        if let accessError = error as? FileAccessError,
           case .needsFileReconnection(let original) = accessError {
            requestFileReconnection(original)
            return
        }
        if let original = standaloneGrantURL, let fileURL,
           !FileManager.default.fileExists(atPath: fileURL.path) {
            // A decode can be the first to find the file in the Trash, before reconcile does.
            if let accessError = error as? FileAccessError, case .fileDeleted = accessError {
                clearFolderImageForNoMatches()
            } else {
                requestFileReconnection(original)
            }
            return
        }
        if error is FileAccessError { showAccessError(error) }
    }
}

// Untested native recovery forwarding; the Application owns decision/host routing.
extension CanvasWindowController: AccessRecoveryHost {
    func browseRecoveredFolder(_ url: URL, rootID: AccessRootID) { openFolder(url, rootID: rootID) }
    func showAccessRecoveryError(_ error: any Error) { showAccessError(error) }
    func requestFolderReconnection(rootID: AccessRootID, lastKnownFolder: URL, displayName: String) {
        guard window?.attachedSheet == nil else { return }
        leaveWaitingAccess()
        presentationRootID = rootID
        gridFolderRoot = rootID
        gridFolderURL = lastKnownFolder
        let position = WaitingAccessPosition(rootID: rootID, folderURL: lastKnownFolder,
            currentItemID: nil, currentImageURL: nil, wasViewing: false,
            conditions: session.folderConditions, recursive: session.folderRecursiveEnabled,
            loop: session.folderLoopEnabled, searchTerm: "", scrollOffset: .zero,
            counter: accessMonitor?.state.snapshot(for: rootID)?.counter ?? 0)
        handleAccessLoss(rootID, counter: position.counter, initialPosition: position)
        let operation = accessIntent.current
        Task { @MainActor [weak self, accessServices] in
            guard let services = try? await accessServices.value, operation.isCurrent,
                  let self, self.waitingAccessPosition?.rootID == rootID else { return }
            self.bindAccessMonitor(services.monitor)
            await services.monitor.register(rootID)
            guard operation.isCurrent, self.waitingAccessPosition?.rootID == rootID else { return }
            // A vanished descendant only changes this window. A real scoped
            // root read must fail before other windows lose the Access Root.
            await services.monitor.reportReadFailure(rootID, from: services.monitor.state.stamp(for: rootID))
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
        open(url, accessRequest: accessRequest)
    }
    func showInputNotice(_ notice: ViewerInputNotice) { showInputMessage(notice) }
    func promptForInputFolder(_ folder: URL) { promptForFolder(folder, currentImage: nil, direction: .next) }
}

// Untested native scan effects; snapshot navigation policy is covered in PicseeApplication.
extension CanvasWindowController: FolderScanHost {
    private func folderScanner(_ services: AccessServices) -> FolderScanCoordinator {
        if let scan = session.folderScan {
            configureReadFailureReporting(scan, monitor: services.monitor)
            return scan
        }
        let scan = FolderScanCoordinator(access: services.files, scanner: services.browser,
            trace: NativeFolderScanTrace(), metadataReader: ImageFolderMetadataReader(), watcher: services.watch)
        scan.host = self
        configureReadFailureReporting(scan, monitor: services.monitor)
        session.folderScan = scan
        observeGridSnapshot(scan)
        return scan
    }
    private func configureReadFailureReporting(_ scan: FolderScanCoordinator, monitor: AccessMonitor) {
        scan.onReadFailure = { [weak self] rootID, _ in
            guard let self, self.presentationRootID == rootID,
                  let context = self.scanReadContext, context.permit.isCurrent else { return }
            Task { await monitor.reportReadFailure(rootID, from: context.stamp) }
        }
    }
    private func observeGridSnapshot(_ scan: FolderScanCoordinator) {
        withObservationTracking {
            gridView.setMetadataSortState(scan.metadataSortState)
            chromeOverlay.setMetadataSortState(scan.metadataSortState)
            if let snapshot = scan.snapshot { applyObservedGridSnapshot(snapshot) }
            updateEmptyFolderState()
            if let source = scan.sourceSnapshot, source.isComplete,
               viewedRefreshVersion != source.version {
                viewedRefreshVersion = source.version
                chromeOverlay.refresh(session: session)
                if session.mode == .viewing, session.filePreviewSet == nil,
                   let current = session.previewSet?.currentItemID ?? scan.currentItemID,
                   let entry = source.navigationEntries.first(where: { $0.itemID == current }) {
                    let revision = session.imageLoader.presented?.key.revision ?? session.imageLoader.preparedKey?.revision
                    let changed = revision.map { currentRevision in
                        entry.resourceIdentifier.map { $0 != currentRevision.resourceIdentifier } == true ||
                        entry.fileSize.map { Int($0) != currentRevision.byteCount } == true ||
                        entry.modificationDate.map { $0 != currentRevision.modificationDate } == true
                    } ?? (session.imageLoader.phase == .failed)
                    if session.imageLoader.fileURL?.standardizedFileURL != entry.url.standardizedFileURL ||
                       changed {
                        open(entry.url, accessRequest: .root(source.version.rootID, file: entry.url), fromFolderScan: true)
                        chromeOverlay.refresh(session: session)
                    }
                }
            }
        } onChange: { [weak self, weak scan] in
            Task { @MainActor [weak self, weak scan] in
                guard let self, let scan, self.session.folderScan === scan else { return }
                self.observeGridSnapshot(scan)
            }
        }
    }
    func applyObservedGridSnapshot(_ snapshot: FolderSnapshot) {
        guard waitingAccessPosition == nil, scanReadContext?.permit.isCurrent != false else { return }
        let previous = gridProjection.snapshot
        let movedFolder = previous?.version.rootID == snapshot.version.rootID &&
            previous?.version.folder != snapshot.version.folder
        let previousSelection = gridProjection.selectedItemID
        let previousAnchor = gridProjection.scrollAnchor
        // A restored source equals the projection already shown; repainting it would cover a restored viewer.
        if gridFolderRoot == snapshot.version.rootID,
           snapshot != gridProjection.snapshot, gridProjection.apply(snapshot), snapshot.isComplete {
            if movedFolder {
                if let previousSelection { gridProjection.select(previousSelection) }
                gridProjection.setScrollAnchor(previousAnchor)
            }
            if gridFolderURL != snapshot.version.folder {
                gridFolderURL = snapshot.version.folder
                loadSidebarTree(snapshot.version.folder, rootID: snapshot.version.rootID, count: nil)
                if session.mode == .browsing, let window {
                    GridWindowIdentity.showFolder(snapshot.version.folder, in: window)
                }
            }
            else if previous?.version != snapshot.version {
                loadSidebarTree(snapshot.version.folder, rootID: snapshot.version.rootID, count: nil)
            }
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
                    scheduler: searchProjection, grid: gridView, shell: gridShell, gridVisible: true,
                    onReconciled: { [weak self] in self?.syncInspectorAfterGridReconciliation() })
                gridView.restoreContentOffset(offset)
            } else {
                GridWatchedSearchRefresh.apply(snapshot, session: session, search: gridSearch,
                    scheduler: searchProjection, grid: gridView, shell: gridShell, gridVisible: false,
                    onReconciled: { [weak self] in self?.syncInspectorAfterGridReconciliation() })
            }
        }
    }
    func openFolderImage(_ url: URL, rootID: AccessRootID) {
        guard waitingAccessPosition == nil, scanReadContext?.permit.isCurrent != false else { return }
        if gridFolderRoot == rootID && session.mode == .browsing { return }
        if !session.allowsFolderScanPresentation { return }
        // A scan-owned move must not revoke the authority that admits its later batches.
        open(url, accessRequest: .root(rootID, file: url), fromFolderScan: true)
    }
    func clearFolderImageForNoMatches() {
        if session.folderScan != nil && !session.allowsFolderScanPresentation { return }
        retryIntent = nil
        retryFromFolderScan = false
        fileURL = nil
        session.closeImage()
        syncInspector()
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
    /// Page 22 (ADR-014) replaces the empty-folder alert once a complete scan finds no images.
    private func updateEmptyFolderState() {
        gridShell.setEmptyFolderState(session.isEmptyFolder, recents: latestRecents, now: Date())
        loadViewerEmptyFolderChildren()
    }
    /// Owner decision C (#137): a viewer folder session never loaded the sidebar tree, so page 22 on the viewer
    /// lists the empty folder's children itself.
    private func loadViewerEmptyFolderChildren() {
        guard session.isEmptyFolder, gridFolderRoot == nil,
              let version = session.folderScan?.sourceSnapshot?.version else { viewerEmptyFolderChildren = nil; return }
        guard viewerEmptyFolderChildren != version.folder else { return }
        viewerEmptyFolderChildren = version.folder
        Task { [weak self, accessServices] in
            guard let services = try? await accessServices.value, let self else { return }
            let browser = self.sidebarBrowserOverride ?? SidebarFolderBrowser(
                access: services.files, enumerator: SystemSidebarFolderEnumerator())
            guard let children = try? await browser.children(in: version.folder, rootID: version.rootID),
                  self.gridFolderRoot == nil, self.viewerEmptyFolderChildren == version.folder else { return }
            self.gridShell.showFolderTree(current: GridSidebarFolder(url: version.folder), parent: nil,
                                          children: children.map { GridSidebarFolder(url: $0) })
        }
    }
    func folderScanDidComplete(count: Int) { chromeOverlay.refresh(session: session) }
    func folderScanDidStart() {
        standaloneWatch?.cancel(); standaloneWatch = nil
        standaloneWatchTask?.cancel(); standaloneWatchTask = nil
        standaloneReconcileTask?.cancel(); standaloneGrantURL = nil
        standaloneReconcilePending = false
        standaloneRecheckAfterOpen = false
        chromeOverlay.refresh(session: session)
        // An Include Subfolders rescan from the grid; the Session already recorded what Cancel Reading returns to.
        guard presentation.showReadingOverGrid(session.folderScan?.isReadingFolder == true) else { return }
        if folderEntryRestore == nil { folderEntryRestore = makeFolderEntryRestore() }
        showReadingState()
    }
    func folderScanDidEnd() {
        chromeOverlay.refresh(session: session)
        if let context = scanReadContext, let root = presentationRootID,
           session.folderScan?.failure != nil, let monitor = accessMonitor {
            Task { await monitor.reportReadFailure(root, from: context.stamp) }
        }
        guard let scan = session.folderScan, scan.failure != nil, scan.sourceSnapshot?.isComplete == true,
              let source = scan.sourceSnapshot else { return }
        let folder = gridFolderURL ?? source.version.folder
        guard !FileManager.default.fileExists(atPath: folder.path) else { return }
        requestFolderReconnection(rootID: source.version.rootID, lastKnownFolder: folder,
                                  displayName: folder.lastPathComponent)
    }

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
