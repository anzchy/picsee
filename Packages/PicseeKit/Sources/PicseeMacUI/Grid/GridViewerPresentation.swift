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
    /// Begins a folder preview from the visible grid's ordered snapshot.
    public func beginPreview(_ session: ViewerSession, snapshot: FolderSnapshot?, scrollAnchor: ItemID?) {
        session.beginBrowsing(items: snapshot?.navigationEntries.map(\.itemID) ?? [],
            sourceVersion: .init(snapshot?.version.generation ?? 0), scrollAnchor: scrollAnchor)
    }
    public func showViewer() {
        shell?.isHidden = true
        state.autoresizingMask = [.width, .height]
        if let parent = state.superview { state.frame = parent.bounds }
        (grid as? GridBrowserView)?.setThumbnailsActive(false)
        grid.isHidden = true
        grid.setAccessibilityHidden(true)
        canvas.isHidden = false
        chrome.isHidden = false
        state.isHidden = false
        state.setAccessibilityHidden(false)
    }
    public func showGrid(reading: Bool) {
        shell?.isHidden = false
        shell?.setFooterActionsEnabled(!reading)
        shell?.layoutSubtreeIfNeeded()
        if let grid = grid as? GridBrowserView { shell?.linkKeyViews(from: grid.collectionView) }
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
        state.isHidden = !reading
        state.setAccessibilityHidden(!reading)
    }
    /// A folder read that starts while the grid is shown (an Include Subfolders rescan) covers it with the Reading State.
    public func showReadingOverGrid(_ reading: Bool) -> Bool {
        guard reading, isGridVisible else { return false }
        showGrid(reading: true)
        return true
    }
    /// Restores the native grid after a preview with the Session's reconciled selection.
    public func restoreGrid(_ snapshot: FolderSnapshot, selection: BrowserSelection, offset: NSPoint?) {
        (grid as? GridBrowserView)?.display(snapshot, selection: selection)
        showGrid(reading: false)
        if let offset { (grid as? GridBrowserView)?.restoreContentOffset(offset) }
    }
    /// What Cancel Reading returns to.
    public func show(_ target: FolderEntryRestoreTarget) {
        if target == .grid { showGrid(reading: false) } else { showViewer() }
    }
}
