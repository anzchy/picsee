import AppKit
import Testing
import PicseeCore
import PicseeApplication
@testable import PicseeMacUI

@MainActor private final class WatchRefreshHost: ViewerSessionHost {
    var hasImage = true
    func performCanvas(_ command: CommandID, from entry: CommandEntry) {}
    func requestOpen() {}
    func applyFocus(_ focus: FocusContext) {}
    func showInspector(_ visible: Bool) {}
    func presentGridItem(_ id: ItemID) {}
    func returnToGrid() {}
}

/// Holds every thumbnail request until it is cancelled, and records starts and cancellations.
private actor WatchRefreshThumbnailLog {
    private(set) var started: [ItemID] = []
    private(set) var cancelled: Set<ItemID> = []
    func start(_ id: ItemID) { started.append(id) }
    func cancel(_ id: ItemID) { cancelled.insert(id) }
    func starts(of id: ItemID) -> Int { started.filter { $0 == id }.count }
}

@MainActor private func watchRefreshPoll(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<2000 {
        if await condition() { return true }
        await Task.yield()
    }
    return await condition()
}

/// Mirrors the App's grid observer: the session reconciles first, then the grid shows the session's selection.
@Test @MainActor func watchedRefreshReconcilesMultiSelectionAndCancelsRemovedThumbnails() async throws {
    _ = NSApplication.shared
    let folder = URL(fileURLWithPath: "/tmp/picsee-grid-watch-refresh")
    let root = ItemIdentityRoot(id: AccessRootID(rawValue: UUID()), url: folder)
    let entries = ["A.jpg", "B.jpg", "C.jpg", "D.jpg"].map { FolderEntry(url: folder.appendingPathComponent($0), root: root) }
    let ids = entries.map(\.itemID)
    let (a, b, c, d) = (ids[0], ids[1], ids[2], ids[3])
    func snapshot(_ kept: [FolderEntry], generation: UInt64) -> FolderSnapshot {
        FolderSnapshot(version: .init(rootID: root.id, folder: folder, generation: generation), entries: kept, isComplete: true)
    }
    let grid = GridBrowserView(frame: NSRect(x: 0, y: 0, width: 1200, height: 700))
    let window = NSWindow(contentRect: grid.bounds, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = grid
    let log = WatchRefreshThumbnailLog()
    grid.thumbnailLoader = { entry, _, _, _ in
        await log.start(entry.itemID)
        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(1)) }
        await log.cancel(entry.itemID)
        throw CancellationError()
    }
    let session = ViewerSession(host: WatchRefreshHost())
    session.beginBrowsing(items: ids, sourceVersion: .init(1), scrollAnchor: a)
    session.select(b)
    session.select(d, modifier: .command)
    #expect(session.selection.selectedItemIDs == [b, d])
    #expect(session.selection.currentItemID == d)
    grid.display(snapshot(entries, generation: 1), selection: session.selection)
    grid.setThumbnailsActive(true)
    grid.layoutSubtreeIfNeeded()
    #expect(await watchRefreshPoll { await log.started.count == 4 })

    // R1: the selected Current Item is deleted. Current moves to its predecessor; the selection only shrinks.
    let first = snapshot(Array(entries.prefix(3)), generation: 2)
    session.updateItems(first.navigationEntries.map(\.itemID), sourceVersion: .init(2))
    grid.display(first, selection: session.selection)
    #expect(session.selection.selectedItemIDs == [b])
    #expect(session.selection.currentItemID == c)
    #expect(grid.selection == session.selection)
    #expect(grid.currentItemID == c)
    #expect(grid.collectionView.selectionIndexPaths == [IndexPath(item: 1, section: 0)])
    #expect(await watchRefreshPoll { await log.cancelled.contains(d) })
    #expect(await watchRefreshPoll { await log.starts(of: c) == 2 })
    #expect(await log.starts(of: d) == 1)

    // R2: a selected non-current item is deleted. Current stays; the selection empties without adopting Current.
    let second = snapshot([entries[0], entries[2]], generation: 3)
    session.updateItems(second.navigationEntries.map(\.itemID), sourceVersion: .init(3))
    grid.display(second, selection: session.selection)
    #expect(session.selection.selectedItemIDs.isEmpty)
    #expect(session.selection.currentItemID == c)
    #expect(grid.currentItemID == c)
    #expect(grid.collectionView.selectionIndexPaths.isEmpty)
    #expect(await watchRefreshPoll { await log.cancelled.contains(b) })
    #expect(await watchRefreshPoll { await log.starts(of: c) == 3 })
    #expect(await log.starts(of: b) == 2)
    #expect(await log.starts(of: d) == 1)
    grid.stopThumbnails()
}
