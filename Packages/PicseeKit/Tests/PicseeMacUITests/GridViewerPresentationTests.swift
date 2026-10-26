import AppKit
import Testing
import PicseeApplication
@testable import PicseeMacUI

@Test @MainActor func cancelReadingRestoresVisibleViewerForFolderNavigatedImage() {
    _ = NSApplication.shared
    let canvas = NSView(), chrome = NSView(), state = NSView(), grid = NSView(), inspector = NSView()
    let presentation = GridViewerPresentation(canvas: canvas, chrome: chrome, state: state, grid: grid, inspector: inspector)
    func expectViewer(_ label: String) {
        #expect(!canvas.isHidden, "\(label): canvas")
        #expect(!chrome.isHidden, "\(label): chrome")
        #expect(!state.isHidden && !state.isAccessibilityHidden(), "\(label): state host")
        #expect(grid.isHidden && grid.isAccessibilityHidden(), "\(label): grid")
        #expect(!presentation.isGridVisible)
    }
    presentation.showViewer()
    expectViewer("viewer")
    inspector.isHidden = false
    presentation.showGrid(reading: true)
    #expect(canvas.isHidden && chrome.isHidden && inspector.isHidden)
    #expect(grid.isHidden && grid.isAccessibilityHidden())
    #expect(!state.isHidden && !state.isAccessibilityHidden())

    presentation.show(.viewer(URL(fileURLWithPath: "/root/A/b.png")))
    expectViewer("cancel to viewer")
    #expect(inspector.isHidden)

    presentation.showGrid(reading: false)
    presentation.show(.viewer(URL(fileURLWithPath: "/root/A/b.png")))
    expectViewer("grid to viewer")
    presentation.showGrid(reading: true)
    presentation.show(.grid)
    #expect(presentation.isGridVisible && !grid.isAccessibilityHidden())
    #expect(state.isHidden && state.isAccessibilityHidden() && canvas.isHidden && chrome.isHidden)
    presentation.showGrid(reading: true)
    presentation.show(.empty)
    expectViewer("cancel to empty")
}

@Test @MainActor func p204R4ShowReadingOverGridOnlyWhenGridVisible() {
    _ = NSApplication.shared
    let canvas = NSView(), chrome = NSView(), state = NSView(), grid = NSView(), inspector = NSView()
    let presentation = GridViewerPresentation(canvas: canvas, chrome: chrome, state: state, grid: grid, inspector: inspector)
    presentation.showViewer()
    #expect(!presentation.showReadingOverGrid(true))
    #expect(!canvas.isHidden && grid.isHidden && !state.isHidden)
    presentation.showGrid(reading: false)
    #expect(!presentation.showReadingOverGrid(false))
    #expect(presentation.isGridVisible && state.isHidden)
    #expect(presentation.showReadingOverGrid(true))
    #expect(grid.isHidden && grid.isAccessibilityHidden())
    #expect(!state.isHidden && !state.isAccessibilityHidden() && canvas.isHidden && chrome.isHidden)
}
