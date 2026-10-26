import AppKit
import Testing
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
@testable import PicseeMacUI

/// grid-light.html / grid-dark.html `.grid-bottom-bar` (40px, 12px inset;
/// 7px only at max-width:480px), `.grid-toolbar-tools` (6px gap;
/// 2px at max-width:800px), and primitives.css `.ds-icon-button` (30x28).
/// search-empty.html `.empty-state` and its h2/p/.mock-primary rules.
@Test @MainActor func pinnedSearchFooterFramesAndPage23AtBothSizesAndAppearances() throws {
    _ = NSApplication.shared
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        for size in [NSSize(width: 1280, height: 800), NSSize(width: 800, height: 680)] {
            let shell = GridShellView(frame: NSRect(origin: .zero, size: size),
                preferencesStore: InMemoryDisplayPreferencesStore())
            shell.appearance = NSAppearance(named: appearance)
            shell.layoutSubtreeIfNeeded()
            #expect(shell.footer.frame.height == 40)
            #expect(shell.sortButton.frame.size == NSSize(width: 30, height: 28))
            #expect(shell.sortButton.frame.maxX == size.width - 12)
            #expect(shell.searchButton.frame.size == NSSize(width: 30, height: 28))
            let toolGap: CGFloat = size.width <= 800 ? 2 : 6
            #expect(shell.searchButton.frame.maxX + toolGap == shell.sortButton.frame.minX)
            #expect(shell.searchField.isHidden)
            #expect(shell.searchStatus.font?.pointSize == 12)
            #expect(shell.searchStatus.textColor == DesignColor.textSecondary.nsColor)
            shell.effectiveAppearance.performAsCurrentDrawingAppearance {
                #expect(shell.footer.layer?.backgroundColor == DesignColor.sidebarBackground.nsColor.cgColor)
            }
            #expect(shell.footer.frame.minX == 0)
            shell.focusSearch()
            shell.layoutSubtreeIfNeeded()
            #expect(!shell.searchField.isHidden)
            #expect(shell.searchButton.isHidden)
            #expect(shell.searchField.frame.height == 28)
            #expect(shell.searchField.frame.maxX + toolGap == shell.sortButton.frame.minX)
            #expect(shell.searchField.frame.minX > shell.toggleButton.frame.maxX)
            shell.setSearchTerm("旅行")
            shell.setSearchStatus(resultCount: 4, term: "旅行")
            #expect(shell.searchStatus.stringValue.contains("4"))
            #expect(shell.searchStatus.stringValue.contains("旅行"))
            #expect(!shell.searchStatus.isHidden)
            shell.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification,
                object: shell.searchField))
            #expect(shell.searchField.isHidden)
            #expect(!shell.searchButton.isHidden)
            #expect(shell.searchButton.state == .on)
            shell.focusSearch()
            shell.showSearchEmpty(true, term: String(repeating: "long-name-", count: 40))
            let title = try #require(shell.emptyStateTitle)
            let detail = try #require(shell.emptyStateDetail)
            #expect(title.font?.pointSize == 16)
            #expect(detail.font?.pointSize == 13)
            #expect(title.frame.midX == shell.mainContent.bounds.midX)
            #expect(detail.frame.midX == shell.mainContent.bounds.midX)
            #expect(shell.clearSearchButton.frame.midX == shell.mainContent.bounds.midX)
            #expect(title.frame.minY > shell.mainContent.bounds.minY)
            #expect(shell.clearSearchButton.frame.maxY < shell.mainContent.bounds.maxY)
            #expect(detail.frame.minX >= shell.mainContent.bounds.minX)
            #expect(detail.frame.maxX <= shell.mainContent.bounds.maxX)
            #expect(shell.clearSearchButton.isBordered)
            #expect(shell.clearSearchButton.bezelColor != nil)
            #expect((title.frame.maxY + shell.clearSearchButton.frame.minY) / 2 - shell.mainContent.bounds.midY < 80)
        }
    }
}

/// grid-light.html `.grid-bottom-bar` switches to 7px only at
/// `@media (max-width:480px)`; its tools keep the `max-width:800px` 2px gap.
@Test @MainActor func pinnedFooterUsesNarrowMediaInsetAt480Points() {
    _ = NSApplication.shared
    let shell = GridShellView(frame: NSRect(x: 0, y: 0, width: 480, height: 680),
        preferencesStore: InMemoryDisplayPreferencesStore())
    shell.layoutSubtreeIfNeeded()
    #expect(shell.sortButton.frame.maxX == CGFloat(480 - 7))
    #expect(shell.searchButton.frame.maxX + 2 == shell.sortButton.frame.minX)
    shell.focusSearch()
    shell.layoutSubtreeIfNeeded()
    #expect(shell.searchField.frame.maxX + 2 == shell.sortButton.frame.minX)
}

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

@Test @MainActor func nativeSearchClearAndReadingStateKeepFieldAndResultsInStep() {
    _ = NSApplication.shared
    let shell = GridShellView(frame: NSRect(x: 0, y: 0, width: 800, height: 652),
        preferencesStore: InMemoryDisplayPreferencesStore())
    var changes: [String] = []
    shell.onSearchChange = { changes.append($0) }
    shell.setSearchTerm("missing")
    shell.showSearchEmpty(true, term: "missing")
    shell.searchField.stringValue = "" // NSSearchField's built-in clear button has emptied the cell.
    shell.searchFieldDidEndSearching(shell.searchField)
    #expect(changes == [""])
    shell.setFooterActionsEnabled(false)
    #expect(shell.searchEmptyVisible == false)
    #expect(shell.searchField.isEnabled == false)
}

@Test @MainActor func searchFieldNativeActionAndClickOutsideCollapse() throws {
    _ = NSApplication.shared
    let shell = GridShellView(frame: NSRect(x: 0, y: 0, width: 800, height: 680),
        preferencesStore: InMemoryDisplayPreferencesStore())
    var terms: [String] = []
    shell.onSearchChange = { terms.append($0) }
    shell.searchButton.performClick(nil)
    #expect(!shell.searchField.isHidden)
    #expect(!shell.searchField.isHidden)
    shell.setSearchTerm("cafe")
    let action = try #require(shell.searchField.action)
    #expect(shell.searchField.target === shell)
    #expect(action == #selector(GridShellView.searchFieldAction))
    shell.searchFieldAction()
    #expect(terms == ["cafe"])
    shell.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification,
        object: shell.searchField))
    #expect(shell.searchField.isHidden)
    #expect(shell.searchButton.state == .on)
    shell.searchButton.performClick(nil)
    #expect(shell.searchField.stringValue == "cafe")
    shell.searchField.stringValue = ""
    shell.searchFieldAction()
    #expect(terms == ["cafe", ""])
    #expect(shell.searchButton.state == .off)
    #expect(shell.searchField.isHidden && !shell.searchButton.isHidden)
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
    #expect(grid.displayedItemIDs == [first.itemID, second.itemID])
    grid.setCurrentItemID(second.itemID)
    #expect(grid.currentItemID == second.itemID)
    grid.setCurrentItemID(nil)
    #expect(grid.currentItemID == first.itemID)
}
