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
    let root = ItemIdentityRoot(id: AccessRootID(rawValue: UUID()), url: folder)
    let entries = (0..<3).map { FolderEntry(url: folder.appendingPathComponent("DSC_000\($0).jpg"), root: root) }
    let snapshot = FolderSnapshot(version: .init(rootID: root.id, folder: folder, generation: 1),
        entries: entries, isComplete: true)
    presentation.showCompletedGrid(snapshot, selection: BrowserSelection(), currentItemID: entries[0].itemID, offset: nil)
    presentation.showGrid(reading: true)
    shell.layoutSubtreeIfNeeded()

    let status = try #require(issue282FooterView("grid.current-file-status", in: shell) as? NSTextField)
    let count = try #require(issue282FooterView("grid.folder-count", in: shell) as? NSTextField)
    // folder-loading.html: `<span>—</span><span class="grid-folder-count">正在读取…</span>` at x 63 and 82, gap 12.
    #expect(status.stringValue == "—")
    #expect(!status.isHidden)
    #expect(status.frame.minX == 62)
    #expect(abs(status.frame.width - ceil(status.intrinsicContentSize.width)) <= 1)
    #expect(count.stringValue == "Reading…")
    #expect(!count.isHidden)
    #expect(count.font == .monospacedSystemFont(ofSize: 12, weight: .regular))
    #expect(count.frame.minX - status.frame.maxX == 12)
    #expect(count.frame.width >= count.intrinsicContentSize.width)
    for field in [status, count] {
        #expect(abs(field.frame.midY - shell.footer.bounds.midY) <= 1, "\(field.stringValue) centred")
    }
    let hint = try #require(issue282FooterView("grid.keyboard-hint", in: shell))
    #expect(hint.isHidden)
    let row = try #require(shell.folderTree.rows.first)
    #expect(row.countLabel.stringValue == "20000")

    // Cancel Reading back to the grid restores the current name and the image count.
    presentation.showGrid(reading: false)
    shell.layoutSubtreeIfNeeded()
    #expect(status.stringValue == "DSC_0000.jpg")
    #expect(count.stringValue == "3 images")
    #expect(!count.isHidden)
}
