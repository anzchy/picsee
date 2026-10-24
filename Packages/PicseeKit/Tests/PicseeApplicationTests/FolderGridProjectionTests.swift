import Foundation
import Testing
import PicseeCore
import PicseeApplication

@Test @MainActor func gridProjectionPreservesIdentityAcrossGenerationsAndRejectsLateSnapshot() throws {
    let rootID = AccessRootID(rawValue: UUID())
    let folder = URL(fileURLWithPath: "/tmp/picsee-grid-projection")
    let root = ItemIdentityRoot(id: rootID, url: folder)
    let a = FolderEntry(url: folder.appendingPathComponent("A.jpg"), root: root)
    let b = FolderEntry(url: folder.appendingPathComponent("B.jpg"), root: root)
    let inserted = FolderEntry(url: folder.appendingPathComponent("0.jpg"), root: root)
    func snapshot(_ generation: UInt64, _ entries: [FolderEntry]) -> FolderSnapshot {
        FolderSnapshot(version: SnapshotVersion(rootID: rootID, folder: folder, generation: generation), entries: entries, isComplete: true)
    }
    let grid = FolderGridProjection()
    #expect(grid.apply(snapshot(8, [a, b])))
    grid.select(b.itemID)
    grid.setScrollAnchor(a.itemID)
    #expect(grid.apply(snapshot(9, [inserted, a, b])))
    #expect(grid.selectedItemID == b.itemID)
    #expect(grid.scrollAnchor == a.itemID)
    #expect(grid.entry(for: b.itemID)?.url == b.url)
    #expect(!grid.apply(snapshot(8, [a])))
    #expect(grid.selectedItemID == b.itemID)
    #expect(grid.apply(snapshot(10, [inserted, a])))
    #expect(grid.selectedItemID == nil)
    #expect(grid.scrollAnchor == a.itemID)
}
