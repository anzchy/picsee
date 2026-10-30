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

@Test @MainActor func issue281SearchEditorDoesNotOverlapHintOrStatusInEnglishAndChinese() throws {
    for language in ["en", "zh-Hans"] {
        let (shell, _, window) = try issue281FooterScene(width: 1280)
        defer { window.close() }
        let longName = language == "en" ? String(repeating: "LongEnglishFileName", count: 20) + ".jpg"
            : String(repeating: "旅行照片文件名", count: 20) + ".jpg"
        shell.setCurrentFile(longName)
        shell.setSearchStatus(resultCount: 12, term: "")
        let hint = try #require(issue281FooterView("grid.keyboard-hint", in: shell))
        let file = try #require(issue281FooterView("grid.current-file-status", in: shell))
        let count = try #require(issue281FooterView("grid.folder-count", in: shell))
        shell.focusSearch()
        shell.layoutSubtreeIfNeeded()
        // grid-light.html: editing uses searchField's frame, not the hidden searchButton or the Space hint.
        #expect(!shell.searchField.isHidden)
        #expect(hint.isHidden, "\(language) Space hint overlaps the editor")
        for status in [file, count] {
            #expect(!status.isHidden, "\(language) status should remain visible")
            #expect(!NSIntersectsRect(status.frame, shell.searchField.frame),
                    "\(language) status overlaps the editor")
        }
        shell.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification,
            object: shell.searchField))
        #expect(!hint.isHidden, "Space hint returns after editing ends")
    }
}

@Test @MainActor func issue281FooterStatusUsesPinnedResponsiveWidths() throws {
    let cases: [(width: CGFloat, fileWidth: CGFloat, countGap: CGFloat, countHidden: Bool)] = [
        (1280, 240, 12, false), (801, 240, 12, false), (800, 180, 7, false),
        (721, 180, 7, false), (720, 140, 7, false), (481, 140, 7, false), (480, 90, 7, true),
    ]
    for item in cases {
        let (shell, _, window) = try issue281FooterScene(width: item.width)
        defer { window.close() }
        let file = try #require(issue281FooterView("grid.current-file-status", in: shell) as? NSTextField)
        let count = try #require(issue281FooterView("grid.folder-count", in: shell) as? NSTextField)
        // grid-light.html: .grid-file-status>span:first-child max-width is 240/180/140/90px; .grid-file-status gap becomes 7px at 800px.
        #expect(abs(file.frame.width - item.fileWidth) <= 1, "filename width at \(item.width)")
        #expect(count.isHidden == item.countHidden, "count visibility at \(item.width)")
        #expect(abs(count.frame.minX - file.frame.maxX - item.countGap) <= 1, "count gap at \(item.width)")
    }
}

@Test @MainActor func issue281FooterCountFollowsShortNameWithoutTruncation() throws {
    let (shell, grid, window) = try issue281FooterScene(width: 1280)
    defer { window.close() }
    let other = try #require(grid.displayedItemIDs.first)
    grid.activate(currentItemID: other)
    shell.layoutSubtreeIfNeeded()
    let file = try #require(issue281FooterView("grid.current-file-status", in: shell) as? NSTextField)
    let count = try #require(issue281FooterView("grid.folder-count", in: shell) as? NSTextField)
    // grid-light.html: span:first-child hugs `DSC_0342.jpg` (x 63–143) and the count follows 12px later (x 155).
    #expect(file.stringValue == "DSC_0340.jpg")
    #expect(abs(file.frame.width - ceil(file.intrinsicContentSize.width)) <= 1)
    #expect(count.frame.minX - file.frame.maxX == 12)
    #expect(count.frame.minX < 180, "count sits after the name, not in a 240pt column")
    #expect(count.frame.width >= count.intrinsicContentSize.width, "\(count.stringValue) is truncated")

    // A larger count after the last layout must still fit in full (device: `20000 张…`).
    shell.setSearchStatus(resultCount: 20000, term: "")
    shell.layoutSubtreeIfNeeded()
    #expect(count.stringValue == "20000 images")
    #expect(count.frame.width >= count.intrinsicContentSize.width, "\(count.stringValue) is truncated")
    #expect(count.frame.minX - file.frame.maxX == 12)
}

@Test @MainActor func issue281FooterTextIsCentredInFortyPointFooter() throws {
    let (shell, _, window) = try issue281FooterScene(width: 1280)
    defer { window.close() }
    let file = try #require(issue281FooterView("grid.current-file-status", in: shell) as? NSTextField)
    let count = try #require(issue281FooterView("grid.folder-count", in: shell) as? NSTextField)
    // grid-light.html: .grid-bottom-bar align-items:center; text box y 772–789 in the 760–800 footer (device 768–778).
    for field in [file, count] {
        let frame = shell.footer.convert(field.bounds, from: field)
        #expect(abs(frame.height - ceil(field.intrinsicContentSize.height)) <= 1, "\(field.stringValue) one line high")
        #expect(abs(frame.midY - shell.footer.bounds.midY) <= 1, "\(field.stringValue) centred")
    }
}
