import AppKit
import Testing
import PicseeCore
import PicseeApplication
@testable import PicseeMacUI

@Test @MainActor func gridAllowsMultipleNativeSelection() {
    _ = NSApplication.shared
    let grid = GridBrowserView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
    #expect(grid.collectionView.allowsMultipleSelection)
}

@Test @MainActor func gridMouseModifiersDrawExactlyTheSessionSelection() throws {
    _ = NSApplication.shared
    let folder = URL(fileURLWithPath: "/tmp/picsee-grid-multi")
    let root = ItemIdentityRoot(id: AccessRootID(rawValue: UUID()), url: folder)
    let entries = (0..<5).map { FolderEntry(url: folder.appendingPathComponent("\($0).jpg"), root: root) }
    let ids = entries.map(\.itemID)
    let snapshot = FolderSnapshot(version: .init(rootID: root.id, folder: folder, generation: 1),
        entries: entries, isComplete: true)
    let grid = GridBrowserView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
    let window = NSWindow(contentRect: grid.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = grid
    let session = ViewerSession()
    session.beginBrowsing(items: ids, sourceVersion: .init(1), scrollAnchor: ids[0])
    grid.onSelectionGesture = { id, modifier in
        session.select(id, modifier: modifier)
        return session.selection
    }
    grid.display(snapshot, selection: session.selection)
    grid.layoutSubtreeIfNeeded()
    grid.collectionView.layoutSubtreeIfNeeded()

    func sendMouse(at point: NSPoint, flags: NSEvent.ModifierFlags = []) throws {
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        grid.collectionView.mouseDown(with: event)
    }
    func click(_ index: Int, _ flags: NSEvent.ModifierFlags = []) throws {
        let attributes = try #require(grid.collectionView.collectionViewLayout?
            .layoutAttributesForItem(at: IndexPath(item: index, section: 0)))
        #expect(grid.collectionView.indexPathForItem(at: NSPoint(x: attributes.frame.midX,
            y: attributes.frame.midY)) == IndexPath(item: index, section: 0))
        let point = grid.collectionView.convert(NSPoint(x: attributes.frame.midX, y: attributes.frame.midY), to: nil)
        try sendMouse(at: point, flags: flags)
        let drawn = Set(grid.collectionView.selectionIndexPaths.compactMap { grid.itemID(at: $0.item) })
        #expect(drawn == grid.selection.selectedItemIDs)
        #expect(drawn == session.selection.selectedItemIDs)
        for case let photo as GridPhotoItem in grid.collectionView.visibleItems() {
            let id = try #require(photo.representedItemID)
            #expect(photo.isSelected == grid.selection.selectedItemIDs.contains(id))
            #expect(photo.isSelectionBadgeVisible == photo.isSelected)
        }
    }
    try click(1)
    try click(3, .command)
    #expect(session.selection.selectedItemIDs == [ids[1], ids[3]])
    #expect(session.selection.anchorItemID == ids[3])
    try click(1, .command)
    #expect(session.selection.selectedItemIDs == [ids[3]])
    #expect(session.selection.currentItemID == ids[1])
    try click(4, .shift)
    #expect(session.selection.selectedItemIDs == Set(ids[1...4]))
    #expect(session.selection.anchorItemID == ids[1])
    let added = FolderEntry(url: folder.appendingPathComponent("new.jpg"), root: root)
    let nextIDs = [ids[4], ids[3], ids[1], added.itemID]
    session.updateItems(nextIDs, sourceVersion: .init(2))
    grid.display(FolderSnapshot(version: .init(rootID: root.id, folder: folder, generation: 2),
        entries: [entries[4], entries[3], entries[1], added], isComplete: true), selection: session.selection)
    grid.layoutSubtreeIfNeeded()
    grid.collectionView.layoutSubtreeIfNeeded()
    grid.synchronizeSelection(session.selection)
    #expect(grid.collectionView.selectionIndexPaths.count == 3)
    #expect(session.selection.selectedItemIDs == [ids[4], ids[3], ids[1]])
    grid.onClearSelection = { session.clearSelection(); return session.selection }
    try sendMouse(at: grid.collectionView.convert(NSPoint(x: 2, y: 2), to: nil))
    #expect(session.selection.selectedItemIDs.isEmpty)
    #expect(session.selection.currentItemID == ids[4])
    #expect(grid.collectionView.selectionIndexPaths.isEmpty)
}

@Test @MainActor func gridStandaloneMouseSelectionAndEmptyClick() throws {
    _ = NSApplication.shared
    let folder = URL(fileURLWithPath: "/tmp/picsee-grid-standalone")
    let root = ItemIdentityRoot(id: AccessRootID(rawValue: UUID()), url: folder)
    let entry = FolderEntry(url: folder.appendingPathComponent("A.jpg"), root: root)
    let grid = GridBrowserView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let window = NSWindow(contentRect: grid.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = grid
    grid.display(FolderSnapshot(version: .init(rootID: root.id, folder: folder, generation: 1),
        entries: [entry], isComplete: true), selectedItemID: nil)
    grid.layoutSubtreeIfNeeded()
    grid.collectionView.layoutSubtreeIfNeeded()
    func click(_ point: NSPoint) throws {
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown,
            location: grid.collectionView.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        grid.collectionView.mouseDown(with: event)
    }
    let frame = try #require(grid.collectionView.collectionViewLayout?
        .layoutAttributesForItem(at: IndexPath(item: 0, section: 0))).frame
    try click(NSPoint(x: frame.midX, y: frame.midY))
    #expect(grid.selection.selectedItemIDs == [entry.itemID])
    #expect(grid.collectionView.selectionIndexPaths == [IndexPath(item: 0, section: 0)])
    try click(NSPoint(x: 2, y: 2))
    #expect(grid.selection.selectedItemIDs.isEmpty)
    #expect(grid.collectionView.selectionIndexPaths.isEmpty)
}

@Test @MainActor func gridMultiPreviewFreezesOrderAndRestoresSelection() {
    let session = ViewerSession()
    let ids = (0..<5).map { _ in ItemID.ephemeral(UUID()) }
    session.beginBrowsing(items: ids, sourceVersion: .init(1), scrollAnchor: ids[0])
    session.select(ids[3])
    session.select(ids[1], modifier: .command)
    session.select(ids[4], modifier: .command)
    session.focus(ids[0])
    let origin = session.selection
    #expect(CommandRouter().route(.preview, from: .key, to: session))
    #expect(session.previewSet?.itemIDs == [ids[1], ids[3], ids[4]])
    #expect(session.previewSet?.currentItemID == ids[1])
    session.updateItems([ids[4], ids[3], ids[2], ids[0]], sourceVersion: .init(2))
    #expect(session.previewSet?.itemIDs == [ids[3], ids[4]])
    #expect(CommandRouter().route(.escape, from: .key, to: session))
    #expect(session.selection.selectedItemIDs == origin.selectedItemIDs.subtracting([ids[1]]))
    #expect(session.selection.currentItemID == ids[0])
    #expect(session.scrollAnchor == ids[0])
}
