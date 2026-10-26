import AppKit
import Testing
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
@testable import PicseeMacUI

@Test @MainActor func gridFooterSearchSortAndEmptyStateFitCompactViewport() throws {
    _ = NSApplication.shared
    let shell = GridShellView(frame: NSRect(x: 0, y: 0, width: 800, height: 652),
        preferencesStore: InMemoryDisplayPreferencesStore())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 680),
        styleMask: [], backing: .buffered, defer: false)
    window.contentView!.addSubview(shell)
    shell.layoutSubtreeIfNeeded()
    #expect(shell.toggleButton.frame.maxX < shell.searchField.frame.minX)
    #expect(shell.searchField.frame.maxX < shell.sortButton.frame.minX)
    #expect(shell.sortButton.frame.maxX <= shell.footer.bounds.maxX)
    #expect(shell.searchField.accessibilityLabel() == "Search current folder")
    #expect(shell.sortButton.accessibilityLabel() == "Sort images")
    shell.focusSearch()
    #expect(window.firstResponder === shell.searchField || window.firstResponder is NSTextView)
    var observedTerm = ""
    shell.onSearchChange = { observedTerm = $0 }
    shell.setSearchTerm("café")
    shell.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: shell.searchField))
    #expect(observedTerm == "café")
    let anchor = NSView()
    shell.linkKeyViews(from: anchor)
    #expect(shell.searchField.nextKeyView === shell.sortButton)
    #expect(shell.sortButton.nextKeyView === anchor)
    shell.showSearchEmpty(true, term: "旅行")
    #expect(shell.searchEmptyVisible)
    #expect(shell.sortButton.nextKeyView === shell.clearSearchButton)
    #expect(shell.clearSearchButton.canBecomeKeyView)
    let empty = try #require(shell.mainContent.subviews.first { $0.accessibilityIdentifier() == "grid.search.empty" })
    #expect(empty.frame == shell.mainContent.bounds)
    #expect(empty.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("旅行") })
    #expect(shell.clearSearchButton.frame.midX == shell.mainContent.bounds.midX)
    var cleared = false
    shell.onClearSearch = { cleared = true }
    shell.clearSearchButton.performClick(nil)
    #expect(cleared)
    cleared = false
    shell.setSearchTerm("unmatched")
    #expect(shell.control(shell.searchField, textView: NSTextView(),
        doCommandBy: #selector(NSResponder.cancelOperation(_:))))
    #expect(cleared)
    #expect(shell.searchField.stringValue.isEmpty)
    shell.showSearchEmpty(false)
    #expect(shell.sortButton.nextKeyView === anchor)
    shell.setFooterActionsEnabled(false)
    #expect(!shell.searchField.isEnabled)
    #expect(!shell.sortButton.isEnabled)
    #expect(shell.toggleButton.nextKeyView?.nextKeyView === anchor)
    shell.setFooterActionsEnabled(true)
    #expect(shell.searchField.isEnabled)
}

@Test @MainActor func footerSortActionsUseFolderMenuActionsAndReflectCurrentConditions() throws {
    _ = NSApplication.shared
    let shell = GridShellView(frame: NSRect(x: 0, y: 0, width: 800, height: 652),
        preferencesStore: InMemoryDisplayPreferencesStore())
    shell.sortConditions = { FolderViewConditions(sort: .size, direction: .descending) }
    var chosen: FolderMenuAction?
    shell.onSort = { chosen = $0 }
    let menu = shell.makeSortMenu()
    var openedMenu: NSMenu?
    shell.onOpenSortMenu = { _, menu in openedMenu = menu }
    shell.sortButton.performClick(nil)
    #expect(openedMenu?.items.count == menu.items.count)
    let size = try #require(menu.items.first { $0.accessibilityIdentifier() == "folder.sort.size.menu" })
    let descending = try #require(menu.items.first { $0.accessibilityIdentifier() == "folder.order.descending.menu" })
    #expect(size.state == .on)
    #expect(descending.state == .on)
    menu.performActionForItem(at: menu.index(of: size))
    #expect(chosen == .sort(.size))
}

@Test @MainActor func gridCurrentItemSetterKeepsVisibleIdentityOrFallsBack() {
    _ = NSApplication.shared
    let folder = URL(fileURLWithPath: "/tmp/picsee-grid-current-search")
    let rootID = AccessRootID(rawValue: UUID())
    let root = ItemIdentityRoot(id: rootID, url: folder)
    let first = FolderEntry(url: folder.appendingPathComponent("a.jpg"), root: root)
    let second = FolderEntry(url: folder.appendingPathComponent("b.jpg"), root: root)
    let grid = GridBrowserView(frame: NSRect(x: 0, y: 0, width: 640, height: 600))
    grid.display(FolderSnapshot(version: .init(rootID: rootID, folder: folder, generation: 1),
        entries: [first, second], isComplete: true), selectedItemID: nil)
    grid.setCurrentItemID(second.itemID)
    #expect(grid.currentItemID == second.itemID)
    grid.setCurrentItemID(nil)
    #expect(grid.currentItemID == first.itemID)
}
