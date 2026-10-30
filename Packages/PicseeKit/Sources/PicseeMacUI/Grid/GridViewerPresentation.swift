import AppKit
import PicseeApplication
import PicseeCore

/// One owner for which surface the window shows: viewer (canvas, chrome, states), Reading State, or grid.
@MainActor public final class GridViewerPresentation {
    private let canvas: NSView, chrome: NSView, state: NSView, grid: NSView, inspector: NSView
    private let shell: GridShellView?
    public init(canvas: NSView, chrome: NSView, state: NSView, grid: NSView, inspector: NSView,
                shell: GridShellView? = nil) {
        self.canvas = canvas; self.chrome = chrome; self.state = state; self.grid = grid; self.inspector = inspector
        self.shell = shell
        shell?.onMainFrameChange = { [weak shell, weak state] main in
            guard let shell, !shell.isHidden, let state, !state.isHidden,
                  let parent = state.superview else { return }
            state.frame = shell.convert(main, to: parent)
        }
    }
    public var isGridVisible: Bool { !grid.isHidden }
    public func layoutInspector(visible: Bool) {
        guard let parent = canvas.superview else { return }
        let bounds = parent.bounds
        let panelWidth: CGFloat = visible && !InspectorPanelLayout.overlaysContent(at: bounds.width)
            ? min(InspectorPanelLayout.width(for: bounds.width), bounds.width) : 0
        let contentWidth = max(0, bounds.width - panelWidth)
        let content = NSRect(x: bounds.minX, y: bounds.minY, width: contentWidth, height: bounds.height)
        canvas.frame = content
        chrome.frame = content
        if let shell {
            shell.frame = NSRect(x: bounds.minX, y: bounds.minY, width: contentWidth,
                                 height: max(0, bounds.height - 28))
            shell.layoutSubtreeIfNeeded()
            if !state.isHidden && !shell.isHidden {
                state.frame = shell.convert(shell.mainFrame, to: parent)
            } else if shell.isHidden {
                state.frame = content
            }
        } else {
            state.frame = content
        }
        inspector.frame = InspectorPanelLayout.frame(in: bounds, grid: !grid.isHidden)
    }
    /// Begins a folder preview from the visible grid's ordered snapshot.
    public func beginPreview(_ session: ViewerSession, snapshot: FolderSnapshot?, scrollAnchor: ItemID?) {
        session.beginBrowsing(items: snapshot?.navigationEntries.map(\.itemID) ?? [],
            sourceVersion: .init(snapshot?.version.generation ?? 0), scrollAnchor: scrollAnchor)
    }
    public func showViewer() {
        shell?.isHidden = true
        shell?.setReadingStatus(false)
        state.autoresizingMask = [.width, .height]
        if let parent = state.superview { state.frame = parent.bounds }
        (grid as? GridBrowserView)?.setThumbnailsActive(false)
        grid.isHidden = true
        grid.setAccessibilityHidden(true)
        canvas.isHidden = false
        chrome.isHidden = false
        setStateSurface(.viewer)
    }
    public func showGrid(reading: Bool) {
        shell?.isHidden = false
        shell?.setFooterActionsEnabled(!reading)
        if let grid = grid as? GridBrowserView {
            shell?.linkKeyViews(from: grid.collectionView)
            grid.onCurrentFileChange = { [weak shell] name in shell?.setCurrentFile(name ?? "") }
            shell?.setCurrentFile(grid.currentItemID.flatMap { grid.entry(for: $0) }?.url.lastPathComponent ?? "")
            shell?.setReadingStatus(reading)
        }
        shell?.layoutSubtreeIfNeeded()
        if reading, let shell, let parent = state.superview {
            state.autoresizingMask = []
            state.frame = shell.convert(shell.mainFrame, to: parent)
        }
        canvas.isHidden = true
        chrome.isHidden = true
        inspector.isHidden = true
        grid.isHidden = reading
        (grid as? GridBrowserView)?.setThumbnailsActive(!reading)
        grid.setAccessibilityHidden(reading)
        setStateSurface(reading ? .gridReading : .grid)
    }
    private func setStateSurface(_ surface: ViewerStateHost.Surface) {
        if let host = state as? ViewerStateHost { host.surface = surface; return }
        state.isHidden = surface == .grid
        state.setAccessibilityHidden(state.isHidden)
    }
    /// A folder read that starts while the grid is shown (an Include Subfolders rescan) covers it with the Reading State.
    public func showReadingOverGrid(_ reading: Bool) -> Bool {
        guard reading, isGridVisible else { return false }
        showGrid(reading: true)
        layoutInspector(visible: false)
        return true
    }
    /// A folder read that starts on the shell's reading or failed surface (Retry) shows the reading footer again.
    /// A viewer-entry read keeps the shell hidden.
    public func resumeReadingFooter(_ reading: Bool) {
        guard reading, let shell, !shell.isHidden, grid.isHidden else { return }
        shell.setReadingStatus(true)
    }
    /// Restores the native grid after a preview with the Session's reconciled selection.
    public func restoreGrid(_ snapshot: FolderSnapshot, selection: BrowserSelection, offset: NSPoint?) {
        (grid as? GridBrowserView)?.display(snapshot, selection: selection)
        showGrid(reading: false)
        if let offset { (grid as? GridBrowserView)?.restoreContentOffset(offset) }
    }
    public func showCompletedGrid(_ snapshot: FolderSnapshot, selection: BrowserSelection,
                                  currentItemID: ItemID?, offset: NSPoint?) {
        guard let grid = grid as? GridBrowserView else { return }
        grid.display(snapshot, selection: selection)
        if let shell {
            shell.setSearchStatus(resultCount: snapshot.navigationEntries.count,
                term: shell.searchField.stringValue)
        }
        showGrid(reading: false)
        grid.activate(currentItemID: currentItemID)
        if let offset { grid.restoreContentOffset(offset) }
    }
    /// What Cancel Reading returns to.
    public func show(_ target: FolderEntryRestoreTarget) {
        if target == .grid { showGrid(reading: false) } else { showViewer() }
    }
}
