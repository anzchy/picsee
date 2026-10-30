import AppKit
import Testing
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
@testable import PicseeMacUI

@MainActor private func issue282FooterView(_ id: String, in root: NSView) -> NSView? {
    if root.accessibilityIdentifier() == id { return root }
    for child in root.subviews {
        if let match = issue282FooterView(id, in: child) { return match }
    }
    return nil
}

@Test @MainActor func issue282ReadingFooterShowsReadingStatusAndPreservesRealSidebarCount() throws {
    _ = NSApplication.shared
    let shell = GridShellView(frame: NSRect(x: 0, y: 0, width: 1280, height: 772),
        preferencesStore: InMemoryDisplayPreferencesStore())
    let grid = GridBrowserView(frame: NSRect(origin: .zero, size: shell.mainFrame.size))
    grid.autoresizingMask = [.width, .height]
    shell.mainContent.addSubview(grid)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
        styleMask: [], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = shell
    let folder = URL(fileURLWithPath: "/tmp/picsee-reading-282")
    let current = GridSidebarFolder(url: folder, count: 20000)
    shell.showFolderTree(current: current, parent: nil, children: [])
    let presentation = GridViewerPresentation(canvas: NSView(), chrome: NSView(), state: NSView(),
        grid: grid, inspector: NSView(), shell: shell)
    presentation.showGrid(reading: true)
    shell.layoutSubtreeIfNeeded()

    let status = try #require(issue282FooterView("grid.current-file-status", in: shell) as? NSTextField)
    // folder-loading.html: footer .grid-file-status is “Reading…”, not the heading “Reading Folder…”.
    #expect(status.stringValue == "Reading…")
    #expect(!status.isHidden)
    #expect(status.frame.minX == 62)
    #expect(status.frame.height == 28)
    let count = try #require(issue282FooterView("grid.folder-count", in: shell) as? NSTextField)
    #expect(count.isHidden)
    let hint = try #require(issue282FooterView("grid.keyboard-hint", in: shell))
    #expect(hint.isHidden)
    let row = try #require(shell.folderTree.rows.first)
    #expect(row.countLabel.stringValue == "20000")
}
