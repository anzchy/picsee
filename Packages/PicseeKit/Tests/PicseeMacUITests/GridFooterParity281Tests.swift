import AppKit
import Testing
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
@testable import PicseeMacUI

@MainActor private func issue281FooterView(_ id: String, in root: NSView) -> NSView? {
    if root.accessibilityIdentifier() == id { return root }
    for child in root.subviews {
        if let match = issue281FooterView(id, in: child) { return match }
    }
    return nil
}

@MainActor private func issue281FooterScene(width: CGFloat, appearance: NSAppearance.Name = .aqua) throws -> (GridShellView, GridBrowserView, NSWindow) {
    _ = NSApplication.shared
    let shell = GridShellView(frame: NSRect(x: 0, y: 0, width: width, height: 772),
        preferencesStore: InMemoryDisplayPreferencesStore())
    shell.appearance = NSAppearance(named: appearance)
    let grid = GridBrowserView(frame: NSRect(origin: .zero, size: shell.mainFrame.size))
    grid.autoresizingMask = [.width, .height]
    shell.mainContent.addSubview(grid)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 800),
        styleMask: [], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = shell
    let presentation = GridViewerPresentation(canvas: NSView(), chrome: NSView(), state: NSView(),
        grid: grid, inspector: NSView(), shell: shell)
    let folder = URL(fileURLWithPath: "/tmp/picsee-grid-281-footer")
    let root = ItemIdentityRoot(id: AccessRootID(rawValue: UUID()), url: folder)
    let entries = (0..<12).map { index in
        let name = index == 1 ? String(repeating: "Long旅行FileName", count: 12) + ".jpg" : "DSC_034\(index).jpg"
        return FolderEntry(url: folder.appendingPathComponent(name), root: root)
    }
    let snapshot = FolderSnapshot(version: .init(rootID: root.id, folder: folder, generation: 1),
        entries: entries, isComplete: true)
    presentation.showCompletedGrid(snapshot, selection: BrowserSelection(),
        currentItemID: entries[1].itemID, offset: nil)
    shell.layoutSubtreeIfNeeded()
    return (shell, grid, window)
}

@Test @MainActor func issue281FooterLeftStatusAndSpaceHintMatchPinnedFrames() throws {
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        let (shell, grid, window) = try issue281FooterScene(width: 1280, appearance: appearance)
        defer { window.close() }
        // grid-light.html: 30x30 filled toggle, 1px divider at x52, then current filename and count.
        #expect(shell.toggleButton.frame == NSRect(x: 12, y: 5, width: 30, height: 30))
        #expect(shell.toggleButton.layer?.backgroundColor != nil)
        #expect(Double(shell.toggleButton.layer?.cornerRadius ?? 0) == DesignMetrics.radii["control"]!)
        let divider = try #require(issue281FooterView("grid.footer.leading-divider", in: shell))
        #expect(divider.frame == NSRect(x: 52, y: 10, width: 1, height: 20))
        let file = try #require(issue281FooterView("grid.current-file-status", in: shell) as? NSTextField)
        #expect(file.frame.minX == 62)
        #expect(file.frame.width <= 240)
        #expect(file.lineBreakMode == .byTruncatingTail)
        #expect(file.stringValue.hasPrefix("Long旅行FileName"))
        let count = try #require(issue281FooterView("grid.folder-count", in: shell) as? NSTextField)
        #expect(count.stringValue == "12 images")
        #expect(count.frame.minX - file.frame.maxX == 12)
        let hint = try #require(issue281FooterView("grid.keyboard-hint", in: shell))
        #expect(!hint.isHidden)
        #expect(hint.frame.maxX + 16 == shell.searchButton.frame.minX)
        #expect(hint.subviews.compactMap { $0 as? NSTextField }.map(\.stringValue) == ["Space", "Quick Look"])

        let other = try #require(grid.displayedItemIDs.first)
        grid.activate(currentItemID: other)
        #expect(file.stringValue == "DSC_0340.jpg")
    }
}

@Test @MainActor func issue281SpaceHintUsesPinnedMaxWidthBreakpoint() throws {
    for (width, visible) in [(801.0, true), (800.0, false)] {
        let (shell, _, window) = try issue281FooterScene(width: width)
        defer { window.close() }
        let hint = try #require(issue281FooterView("grid.keyboard-hint", in: shell))
        #expect(!hint.isHidden == visible, "Space hint at \(width)")
    }
}
