import Observation
import PicseeCore

/// Native effects only; command policy and window state belong to the Session.
@MainActor public protocol ViewerSessionHost: AnyObject {
    var hasImage: Bool { get }
    func performCanvas(_ command: CommandID, from entry: CommandEntry)
    func performCanvasZoom(_ command: CommandID, from entry: CommandEntry) -> Double?
    func requestOpen()
    func applyFocus(_ focus: FocusContext)
    func showInspector(_ visible: Bool)
}

public enum ViewerMode: Sendable { case browsing, viewing }

/// One state owner per window. It never creates a native window.
@MainActor @Observable public final class ViewerSession: DisplayPreferencesObserver {
    public let imageLoader: ViewerImageLoader
    private let preferencesStore: any DisplayPreferencesStore
    private let clock: any ViewerClock
    public weak var host: (any ViewerSessionHost)?
    public private(set) var zoomMode: ViewerZoomMode = .fit
    public func beginCanvasImage() { zoomMode = .fit }
    public func reportCanvasZoom(_ value: Double) { zoomMode = .custom(value) }
    public var searchTerm = ""
    public var displayPreferences: DisplayPreferences { preferencesStore.value }
    public private(set) var selection = BrowserSelection()
    public private(set) var previewSet: PreviewSet?
    public private(set) var mode: ViewerMode = .viewing
    public private(set) var scrollAnchor: ItemID?
    public private(set) var inspectorFocus = InspectorFocus()
    public private(set) var chrome: ViewerChromeState
    public private(set) var isMenuTracking = false
    private var orderedItemIDs: [ItemID] = []
    private var sourceVersion = PreviewSourceVersion(0)
    public var currentItemID: ItemID? {
        mode == .viewing ? previewSet?.currentItemID : selection.currentItemID
    }
    public weak var chromeHost: (any ViewerChromeHost)? { didSet { synchronizeChrome() } }
    private var pointerAtTop = false
    public var trafficLightsVisible: Bool { !chrome.isHidden || pointerAtTop }
    public func pointerMoved(in region: ChromePointerRegion) {
        pointerAtTop = region == .top
        if region == .bottom || (!chrome.isHidden && region != .outside) { activity() }
        else { synchronizeChrome() }
    }
    private var chromeScheduler: (any ViewerChromeScheduling)?
    private var scheduledChromeDeadline: Double?
    private var chromeWakeupConsumed = false
    public func installChromeScheduler(_ scheduler: any ViewerChromeScheduling) {
        chromeScheduler = scheduler
        chromeWakeupConsumed = true
        synchronizeChrome()
    }
    private func synchronizeChrome() {
        chromeHost?.applyChrome(toolsVisible: !chrome.isHidden, trafficLightsVisible: trafficLightsVisible)
        guard let chromeScheduler else { return }
        let deadline = nextHideDeadline
        guard chromeWakeupConsumed || deadline != scheduledChromeDeadline else { return }
        chromeWakeupConsumed = false
        scheduledChromeDeadline = deadline
        chromeScheduler.replace(deadline: deadline) { [weak self] in
            self?.chromeWakeupConsumed = true
            self?.advanceChrome()
        }
    }
    public var nextHideDeadline: Double? { chrome.nextHideDeadline }
    public init(preferencesStore: any DisplayPreferencesStore = InMemoryDisplayPreferencesStore(),
                clock: any ViewerClock = MonotonicViewerClock(), hideDelay: Double = 2.5,
                host: (any ViewerSessionHost)? = nil, imageLoader: ViewerImageLoader = ViewerImageLoader()) {
        self.imageLoader = imageLoader
        self.preferencesStore = preferencesStore
        self.clock = clock
        self.host = host
        chrome = ViewerChromeState(now: clock.now, hideDelay: hideDelay)
        preferencesDidChange(preferencesStore.value)
        preferencesStore.observe(self)
    }
    public func beginBrowsing(items: [ItemID], sourceVersion: PreviewSourceVersion, scrollAnchor: ItemID?) {
        mode = .browsing
        previewSet = nil
        self.scrollAnchor = scrollAnchor
        updateItems(items, sourceVersion: sourceVersion)
    }
    /// Caller reports authoritative available IDs; filtered-out items alone are not deletions.
    public func updateItems(_ items: [ItemID], sourceVersion: PreviewSourceVersion) {
        orderedItemIDs = items
        self.sourceVersion = sourceVersion
        selection.reconcile(with: items)
        previewSet?.reconcile(availableItemIDs: items)
        if let scrollAnchor, !items.contains(scrollAnchor) { self.scrollAnchor = nil }
    }
    public func select(_ id: ItemID, modifier: SelectionModifier = .plain) {
        selection.click(id, modifier: modifier, in: orderedItemIDs)
    }
    public func contextMenuTarget(for id: ItemID) -> ContextMenuTarget {
        ContextMenuTarget(clickedItemID: id, selection: selection, items: orderedItemIDs)
    }
    public func resolve(_ target: ContextMenuTarget) -> [ItemID] {
        target.resolve(availableItemIDs: orderedItemIDs)
    }
    public func setMenuTracking(_ tracking: Bool) {
        isMenuTracking = tracking
        chrome.setLock(.menu, active: tracking, at: clock.now)
        synchronizeChrome()
    }
    public func updateFocus(_ context: FocusContext) {
        inspectorFocus.updateFocus(context)
        syncFocusLock()
    }
    public func setInspectorVisible(_ visible: Bool) {
        inspectorFocus.setVisible(visible)
        chrome.setLock(.inspector, active: visible, at: clock.now)
        syncFocusLock()
        host?.showInspector(visible)
        host?.applyFocus(inspectorFocus.focus)
    }
    public func tab(reverse: Bool) {
        activity()
        if let chromeHost {
            let focus = inspectorFocus.focus
            if focus == .canvas || focus == .tools || reverse {
                if chromeHost.focusChromeTool(reverse: reverse, entering: focus != .tools) {
                    inspectorFocus.updateFocus(.tools)
                } else {
                    inspectorFocus.updateFocus(focus == .tools && !reverse && inspectorFocus.isVisible ? .textInput : .canvas)
                }
            } else { inspectorFocus.escape() }
        } else { inspectorFocus.tab(reverse: reverse) }
        syncFocusLock()
        host?.applyFocus(inspectorFocus.focus)
    }
    private func syncFocusLock() {
        chrome.setLock(.keyboardFocus, active: inspectorFocus.focus != .canvas, at: clock.now)
        synchronizeChrome()
    }
    public func preferencesDidChange(_ preferences: DisplayPreferences) {
        chrome.setPinned(preferences.alwaysShowTools, at: clock.now)
        // Unchanged true values must not count as a new Filmstrip interaction.
        if chrome.locks.contains(.filmstrip) != preferences.filmstripExpanded {
            chrome.setLock(.filmstrip, active: preferences.filmstripExpanded, at: clock.now)
        }
        synchronizeChrome()
    }
    public func activity() { chrome.activity(at: clock.now); synchronizeChrome() }
    public func advanceChrome() { chrome.advance(to: clock.now); synchronizeChrome() }
    public func isEnabled(_ command: CommandID) -> Bool {
        switch command {
        case .fit, .actualPixels, .zoomIn, .zoomOut: host?.hasImage == true
        case .escape: inspectorFocus.focus != .canvas || previewSet != nil
        case .open, .inspector: true
        case .preview, .enter: mode == .browsing && !orderedItemIDs.isEmpty
        case .previous, .next:
            mode == .viewing && (previewSet != nil || (host as? any ViewerSessionNavigationHost)?.canNavigate == true)
        case .search: false
        }
    }
    func perform(_ command: CommandID, from entry: CommandEntry) {
        activity()
        if command == .open {
            host?.requestOpen()
        } else if command == .inspector {
            setInspectorVisible(!inspectorFocus.isVisible)
        } else if command == .escape {
            if inspectorFocus.focus != .canvas {
                inspectorFocus.escape()
                syncFocusLock()
                host?.applyFocus(.canvas)
            } else if let origin = previewSet?.origin {
                selection = origin.selection
                scrollAnchor = origin.scrollAnchor
                previewSet = nil
                mode = .browsing
            }
        } else if command == .preview || command == .enter {
            previewSet = PreviewSet(items: orderedItemIDs, sourceVersion: sourceVersion,
                origin: PreviewOrigin(selection: selection, scrollAnchor: scrollAnchor))
            mode = .viewing
            updateFocus(.canvas)
            host?.applyFocus(.canvas)
        } else if command == .next || command == .previous {
            if previewSet != nil {
                previewSet?.move(forward: command == .next)
            } else {
                (host as? any ViewerSessionNavigationHost)?.navigate(command == .next ? .next : .previous)
            }
        } else {
            if command == .fit { zoomMode = .fit }
            if command == .actualPixels { zoomMode = .actualPixels }
            let finalZoom = host?.performCanvasZoom(command, from: entry)
            if (command == .zoomIn || command == .zoomOut), let finalZoom {
                reportCanvasZoom(finalZoom)
            }
        }
    }
}
