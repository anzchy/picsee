import AppKit
import Testing
import PicseeCore
import PicseeApplication
@testable import PicseeMacUI

@MainActor private final class CurrentItemHost: ViewerSessionHost {
    var hasImage = true
    var opened: [ItemID] = []
    var returns = 0
    func performCanvas(_ command: CommandID, from entry: CommandEntry) {}
    func requestOpen() {}
    func applyFocus(_ focus: FocusContext) {}
    func showInspector(_ visible: Bool) {}
    func presentGridItem(_ id: ItemID) { opened.append(id) }
    func returnToGrid() { returns += 1 }
}

@MainActor private struct CurrentItemScene {
    let folder = URL(fileURLWithPath: "/tmp/picsee-grid-current")
    let rootID = AccessRootID(rawValue: UUID())
    let grid = GridBrowserView(frame: NSRect(x: 0, y: 0, width: 760, height: 480))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
        styleMask: [.titled], backing: .buffered, defer: false)
    init() { window.contentView = grid }
    func entry(_ name: String) -> FolderEntry {
        FolderEntry(url: folder.appendingPathComponent(name), root: .init(id: rootID, url: folder))
    }
    func snapshot(_ entries: [FolderEntry], generation: UInt64 = 1) -> FolderSnapshot {
        FolderSnapshot(version: .init(rootID: rootID, folder: folder, generation: generation), entries: entries, isComplete: true)
    }
    /// The App's wiring: grid selection and Current Item both reach the Session.
    func wire(_ session: ViewerSession) {
        grid.onSelect = { session.select($0) }
        grid.onCurrentChange = { session.focus($0) }
    }
}

@Test @MainActor func gridCurrentItemReachesSessionForSpaceAndFallsBackToFirst() throws {
    _ = NSApplication.shared
    let scene = CurrentItemScene(), router = CommandRouter()
    let a = scene.entry("A.jpg"), b = scene.entry("B.jpg"), c = scene.entry("C.jpg")
    let ids = [a, b, c].map(\.itemID)

    let host = CurrentItemHost(), session = ViewerSession(host: host)
    scene.wire(session)
    session.beginBrowsing(items: ids, sourceVersion: .init(1), scrollAnchor: nil)
    scene.grid.display(scene.snapshot([a, b, c]), selectedItemID: nil)
    scene.grid.activate(currentItemID: b.itemID)
    #expect(session.selection.currentItemID == b.itemID)
    #expect(session.selection.selectedItemIDs.isEmpty)
    #expect(scene.grid.collectionView.selectionIndexPaths.isEmpty)
    #expect(router.route(.preview, from: .key, to: session))
    #expect(host.opened == [b.itemID], "Space opens the image the user came from")
    #expect(router.route(.escape, from: .key, to: session))
    #expect(host.returns == 1)
    #expect(session.selection.currentItemID == b.itemID)
    #expect(session.selection.selectedItemIDs.isEmpty)

    let missingHost = CurrentItemHost(), missing = ViewerSession(host: missingHost)
    scene.wire(missing)
    missing.beginBrowsing(items: ids, sourceVersion: .init(1), scrollAnchor: nil)
    scene.grid.activate(currentItemID: .ephemeral(UUID()))
    #expect(scene.grid.currentItemID == a.itemID)
    #expect(missing.selection.currentItemID == a.itemID)
    #expect(router.route(.enter, from: .key, to: missing))
    #expect(missingHost.opened == [a.itemID])

    let removalHost = CurrentItemHost(), removal = ViewerSession(host: removalHost)
    scene.wire(removal)
    removal.beginBrowsing(items: ids, sourceVersion: .init(1), scrollAnchor: nil)
    scene.grid.activate(currentItemID: b.itemID)
    #expect(removal.selection.currentItemID == b.itemID)
    let z = scene.entry("0.jpg")
    removal.updateItems([z, a, c].map(\.itemID), sourceVersion: .init(2))
    scene.grid.display(scene.snapshot([z, a, c], generation: 2), selectedItemID: nil)
    #expect(scene.grid.currentItemID == z.itemID)
    #expect(removal.selection.currentItemID == z.itemID)
    #expect(router.route(.preview, from: .key, to: removal))
    #expect(removalHost.opened == [z.itemID])

    let kept = ViewerSession()
    kept.beginBrowsing(items: ids, sourceVersion: .init(1), scrollAnchor: nil)
    kept.select(a.itemID)
    kept.focus(c.itemID)
    #expect(kept.selection.currentItemID == c.itemID)
    #expect(kept.selection.selectedItemIDs == [a.itemID])
    #expect(kept.selection.anchorItemID == a.itemID)
    kept.focus(.ephemeral(UUID()))
    #expect(kept.selection.currentItemID == c.itemID)
}
