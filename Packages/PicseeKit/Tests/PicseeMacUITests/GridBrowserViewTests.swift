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

@Test @MainActor func gridViewSelectionAndScrollUseCurrentIdentity() throws {
    _ = NSApplication.shared
    let folder = URL(fileURLWithPath: "/tmp/picsee-grid-secondary")
    let rootID = AccessRootID(rawValue: UUID())
    let entry = FolderEntry(url: folder.appendingPathComponent("Current.heic"),
        root: .init(id: rootID, url: folder))
    let snapshot = FolderSnapshot(version: .init(rootID: rootID, folder: folder, generation: 1),
        entries: [entry], isComplete: true)
    let grid = GridBrowserView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
        styleMask: [], backing: .buffered, defer: false)
    window.contentView = grid
    grid.display(snapshot, selectedItemID: nil)
    grid.layoutSubtreeIfNeeded()
    grid.collectionView.layoutSubtreeIfNeeded()
    #expect(grid.collectionView.selectionIndexPaths.isEmpty)
    #expect(grid.entry(for: entry.itemID) == entry)
    #expect(grid.itemID(at: 9) == nil)
    var selected: ItemID?
    grid.onSelect = { selected = $0 }
    grid.collectionView(grid.collectionView, didSelectItemsAt: [IndexPath(item: 0, section: 0)])
    #expect(selected == entry.itemID)
    let item = grid.collectionView(grid.collectionView, itemForRepresentedObjectAt: IndexPath(item: 0, section: 0))
    #expect((item as? GridPhotoItem)?.filename == "Current.heic")
    grid.scrollTo(entry.itemID)
    #expect(grid.firstVisibleItemID() == entry.itemID)
    grid.scrollTo(.ephemeral(UUID()))
    #expect(GridBrowserView(coder: NSCoder()) == nil)
}

@Test @MainActor func gridSelectedCellUsesSemanticAccentAndFilenameFillAcrossAppearances() throws {
    _ = NSApplication.shared
    let folder = URL(fileURLWithPath: "/tmp/picsee-grid-colors")
    let id = AccessRootID(rawValue: UUID())
    let entry = FolderEntry(url: folder.appendingPathComponent("A.jpg"), root: .init(id: id, url: folder))
    let cell = GridPhotoItem()
    cell.configure(entry)
    cell.view.appearance = NSAppearance(named: .aqua)
    cell.isSelected = true
    let filename = try #require(cell.view.subviews.compactMap { $0 as? NSTextField }
        .first { $0.stringValue == "A.jpg" })
    func rgba(_ color: CGColor?) -> [CGFloat] { color?.components ?? [] }
    let lightBorder = rgba(cell.view.layer?.borderColor)
    let lightFill = rgba(filename.layer?.backgroundColor)
    #expect(lightBorder == DesignColor.accent.components(.light).map { CGFloat($0) })
    #expect(lightFill == DesignColor.selectionFill.components(.light).map { CGFloat($0) })
    cell.view.appearance = NSAppearance(named: .darkAqua)
    let darkBorder = rgba(cell.view.layer?.borderColor)
    let darkFill = rgba(filename.layer?.backgroundColor)
    #expect(darkBorder == DesignColor.accent.components(.dark).map { CGFloat($0) })
    #expect(darkFill == DesignColor.selectionFill.components(.dark).map { CGFloat($0) })
    #expect(lightBorder != darkBorder && lightFill != darkFill)
    #expect(cell.isSelected && cell.view.window?.firstResponder !== cell.view)
}
