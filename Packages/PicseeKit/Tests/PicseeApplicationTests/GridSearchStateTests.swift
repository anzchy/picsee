import Foundation
import Testing
import PicseeCore
@testable import PicseeApplication

@Test @MainActor func gridSearchCurrentClearAndWindowReset() {
    let folder = URL(fileURLWithPath: "/tmp/picsee-grid-search-state")
    let rootID = AccessRootID(rawValue: UUID())
    let root = ItemIdentityRoot(id: rootID, url: folder)
    let alpha = FolderEntry(url: folder.appendingPathComponent("alpha.jpg"), root: root)
    let beta = FolderEntry(url: folder.appendingPathComponent("beta.png"), root: root)
    let source = FolderSnapshot(version: .init(rootID: rootID, folder: folder, generation: 1),
        entries: [alpha, beta], isComplete: true)
    let search = GridSearchState()
    search.setTerm("beta", currentItemID: alpha.itemID)
    let filtered = search.project(source)
    #expect(filtered.navigationEntries.map(\.itemID) == [beta.itemID])
    #expect(search.currentItemID(in: filtered, currentItemID: alpha.itemID) == beta.itemID)
    search.setTerm("unmatched", currentItemID: beta.itemID)
    #expect(search.currentItemID(in: search.project(source), currentItemID: beta.itemID) == nil)
    search.clear()
    #expect(search.project(source).navigationEntries.count == 2)
    #expect(search.currentItemID(in: source, currentItemID: nil) == alpha.itemID)
    search.setTerm("beta", currentItemID: nil)
    let rescan = FolderSnapshot(version: .init(rootID: rootID, folder: folder, generation: 2),
        entries: [beta, alpha], isComplete: true)
    #expect(search.project(rescan).navigationEntries.map(\.itemID) == [beta.itemID])
    let otherWindow = GridSearchState()
    #expect(otherWindow.term.isEmpty)
    #expect(otherWindow.project(source).navigationEntries.count == 2)
    search.reset()
    #expect(search.term.isEmpty)
    #expect(search.preferredCurrentItemID == nil)
}
