import Foundation
import Testing
import PicseeCore
import PicseeApplication

@MainActor private final class GridRouteHost: ViewerSessionHost {
    var hasImage = true
    var opened: [ItemID] = []
    var returned = 0
    func performCanvas(_ command: CommandID, from entry: CommandEntry) {}
    func requestOpen() {}
    func applyFocus(_ focus: FocusContext) {}
    func showInspector(_ visible: Bool) {}
    func presentGridItem(_ id: ItemID) { opened.append(id) }
    func returnToGrid() { returned += 1 }
}

@Test @MainActor func gridViewerRouteOpensStableCurrentAndReturnsAfterUpdate() {
    let a = ItemID.ephemeral(UUID()), b = ItemID.ephemeral(UUID()), inserted = ItemID.ephemeral(UUID())
    let host = GridRouteHost()
    let session = ViewerSession(host: host)
    let router = CommandRouter(implementedCommands: Set(CommandID.allCases))
    session.beginBrowsing(items: [a, b], sourceVersion: .init(1), scrollAnchor: a)
    session.select(b)
    #expect(router.route(.preview, from: .key, to: session))
    #expect(host.opened == [b])
    session.updateItems([inserted, a, b], sourceVersion: .init(2))
    #expect(router.route(.escape, from: .key, to: session))
    #expect(host.returned == 1)
    #expect(session.selection.currentItemID == b)
    #expect(session.scrollAnchor == a)
    #expect(router.route(.enter, from: .key, to: session))
    #expect(host.opened == [b, b])
}

@Test @MainActor func defaultRouterEnablesGridPreviewKeysOnlyWhenBrowseHasItems() {
    let session = ViewerSession(host: GridRouteHost())
    let router = CommandRouter()
    #expect(!router.route(.preview, from: .key, to: session))
    let id = ItemID.ephemeral(UUID())
    session.beginBrowsing(items: [id], sourceVersion: .init(1), scrollAnchor: id)
    session.select(id)
    #expect(router.route(.preview, from: .key, to: session))
    #expect(router.route(.escape, from: .key, to: session))
    #expect(router.route(.enter, from: .key, to: session))
}
