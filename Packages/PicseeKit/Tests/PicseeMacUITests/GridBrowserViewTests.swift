import AppKit
import Foundation
import Testing
import PicseeCore
@testable import PicseeMacUI

@Test @MainActor func gridCellReuseAndSnapshotOrderKeepTruthfulIdentity() throws {
    _ = NSApplication.shared
    let folder = URL(fileURLWithPath: "/tmp/picsee-grid-ui")
    let rootID = AccessRootID(rawValue: UUID())
    let root = ItemIdentityRoot(id: rootID, url: folder)
    let a = FolderEntry(url: folder.appendingPathComponent("A.jpg"), root: root)
    let b = FolderEntry(url: folder.appendingPathComponent("B.png"), root: root)
    let cell = GridPhotoItem()
    cell.configure(a)
    #expect(cell.representedItemID == a.itemID)
    #expect(cell.filename == "A.jpg")
    #expect(cell.view.accessibilityLabel() == "A.jpg, thumbnail pending")
    cell.configure(b)
    #expect(cell.representedItemID == b.itemID)
    #expect(cell.filename == "B.png")
    #expect(cell.view.accessibilityLabel() == "B.png, thumbnail pending")
    let grid = GridBrowserView(frame: NSRect(x: 0, y: 0, width: 700, height: 550))
    let first = FolderSnapshot(version: .init(rootID: rootID, folder: folder, generation: 1), entries: [a, b], isComplete: true)
    grid.display(first, selectedItemID: b.itemID)
    #expect(grid.itemID(at: 1) == b.itemID)
    let zero = FolderEntry(url: folder.appendingPathComponent("0.jpg"), root: root)
    let next = FolderSnapshot(version: .init(rootID: rootID, folder: folder, generation: 2), entries: [zero, a, b], isComplete: true)
    grid.display(next, selectedItemID: b.itemID)
    #expect(grid.index(for: b.itemID) == 2)
    #expect(grid.collectionView.selectionIndexPaths == [IndexPath(item: 2, section: 0)])
}
