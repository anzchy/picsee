import AppKit
import PicseeApplication

/// One owner for which surface the window shows: viewer (canvas, chrome, states), Reading State, or grid.
@MainActor public final class GridViewerPresentation {
    private let canvas: NSView, chrome: NSView, state: NSView, grid: NSView, inspector: NSView
    public init(canvas: NSView, chrome: NSView, state: NSView, grid: NSView, inspector: NSView) {
        self.canvas = canvas; self.chrome = chrome; self.state = state; self.grid = grid; self.inspector = inspector
    }
    public var isGridVisible: Bool { !grid.isHidden }
    public func showViewer() {
        grid.isHidden = true
        grid.setAccessibilityHidden(true)
        canvas.isHidden = false
        chrome.isHidden = false
        state.isHidden = false
        state.setAccessibilityHidden(false)
    }
    public func showGrid(reading: Bool) {
        canvas.isHidden = true
        chrome.isHidden = true
        inspector.isHidden = true
        grid.isHidden = reading
        grid.setAccessibilityHidden(reading)
        state.isHidden = !reading
        state.setAccessibilityHidden(!reading)
    }
    /// What Cancel Reading returns to.
    public func show(_ target: FolderEntryRestoreTarget) {
        if target == .grid { showGrid(reading: false) } else { showViewer() }
    }
}
