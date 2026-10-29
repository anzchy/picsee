import AppKit
import Testing
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
@testable import PicseeMacUI

@MainActor @Test func t229ClearingGridAndTreeRemovesPrivateSelectionRowsAndAccessibility() throws {
    _ = NSApplication.shared
    let snapshot = pinningSnapshot(count: 2, names: ["private-one.png", "private-two.png"])
    let grid = GridBrowserView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    grid.display(snapshot, selectedItemID: snapshot.entries[0].itemID)
    #expect(grid.displayedItemIDs.count == 2)
    grid.clearPresentation()
    #expect(grid.displayedItemIDs.isEmpty)
    #expect(grid.currentItemID == nil)
    #expect(grid.selection.selectedItemIDs.isEmpty)
    #expect(grid.collectionView.selectionIndexPaths.isEmpty)
    #expect(grid.collectionView.numberOfItems(inSection: 0) == 0)
    let tree = GridSidebarTreeView(frame: NSRect(x: 0, y: 0, width: 196, height: 600))
    let root = snapshot.version.folder
    tree.show(current: .init(url: root), parent: nil,
        children: [.init(url: root.appendingPathComponent("PrivateChild"))])
    let detachedRows = tree.rows
    #expect(detachedRows.count == 2)
    tree.clear()
    tree.layoutSubtreeIfNeeded()
    #expect(tree.rows.isEmpty)
    #expect(tree.guide.isHidden)
    #expect(detachedRows.allSatisfy { $0.superview == nil })
    tree.clear(); grid.clearPresentation()
    #expect(tree.rows.isEmpty && grid.displayedItemIDs.isEmpty)
}
