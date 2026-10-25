import AppKit
import Testing
import PicseeCore
@testable import PicseeMacUI

@MainActor private func parityGrid(width: CGFloat, count: Int = 12) -> (GridBrowserView, [FolderEntry], NSWindow) {
    _ = NSApplication.shared
    let folder = URL(fileURLWithPath: "/tmp/picsee-grid-parity")
    let rootID = AccessRootID(rawValue: UUID())
    let root = ItemIdentityRoot(id: rootID, url: folder)
    let entries = (0..<count).map { FolderEntry(url: folder.appendingPathComponent("\($0).jpg"), root: root) }
    let grid = GridBrowserView(frame: NSRect(x: 0, y: 0, width: width, height: 800))
    let window = NSWindow(contentRect: grid.bounds, styleMask: [], backing: .buffered, defer: false)
    window.contentView = grid
    grid.display(FolderSnapshot(version: .init(rootID: rootID, folder: folder, generation: 1),
        entries: entries, isComplete: true), selectedItemID: nil)
    grid.activate()
    grid.layoutSubtreeIfNeeded()
    grid.collectionView.layoutSubtreeIfNeeded()
    return (grid, entries, window)
}

@MainActor private func parityArrow(_ code: UInt16, in grid: GridBrowserView, window: NSWindow) throws {
    let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
        timestamp: 0, windowNumber: window.windowNumber, context: nil,
        characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
    grid.collectionView.keyDown(with: event)
}

@Test @MainActor func gridArrowSequenceDrawsOnlyModelSelection() throws {
    let (grid, entries, window) = parityGrid(width: 700)
    var modelSelection: ItemID?
    grid.onSelect = { modelSelection = $0 }
    for key in [UInt16(124), 125, 125, 126] {
        try parityArrow(key, in: grid, window: window)
        let selected = try #require(modelSelection)
        let index = try #require(grid.index(for: selected))
        #expect(grid.collectionView.selectionIndexPaths == [IndexPath(item: index, section: 0)])
        #expect(grid.currentItemID == selected)
        for case let cell as GridPhotoItem in grid.collectionView.visibleItems() {
            let shouldSelect = cell.representedItemID == selected
            #expect(cell.isSelected == shouldSelect)
            let outline = cell.view.layer?.sublayers?.first { $0.borderWidth == 2 }
            #expect(outline?.isHidden == !shouldSelect)
        }
    }
    #expect(entries.contains { $0.itemID == modelSelection })
}

@Test @MainActor func gridResponsiveGeometryMatchesPageElevenAndTwelve() throws {
    let (grid, _, window) = parityGrid(width: 1280)
    let cases: [(CGFloat, Int, CGFloat, CGFloat, CGFloat)] = [
        (1280.0, 5, 16.0, 24.0, 188.16),
        (1036.0, 4, 12.0, 16.0, 165.0),
        (720.0, 4, 12.0, 16.0, 150.0),
        (480.0, 1, 12.0, 16.0, 150.0),
        (1600.0, 6, 22.0, 32.0, 200.0)
    ]
    for (width, columns, gap, inset, tileHeight) in cases {
        window.setContentSize(NSSize(width: width, height: 800))
        grid.frame = NSRect(x: 0, y: 0, width: width, height: 800)
        grid.layoutSubtreeIfNeeded()
        grid.collectionView.layoutSubtreeIfNeeded()
        let layout = try #require(grid.collectionView.collectionViewLayout as? NSCollectionViewFlowLayout)
        let cellWidth = (width - 2 * inset - CGFloat(columns - 1) * gap) / CGFloat(columns)
        #expect(abs(layout.itemSize.width - cellWidth) < 0.02)
        #expect(abs(layout.itemSize.height - (tileHeight + 36)) < 0.02)
        #expect(abs(layout.sectionInset.left - inset) < 0.02)
        #expect(abs(layout.sectionInset.top - 16) < 0.02)
        #expect(abs(layout.minimumInteritemSpacing - gap) < 0.02)
        #expect(abs(layout.minimumLineSpacing - (width >= 1600 ? 22 : (width > 1050 ? 18 : 12))) < 0.02)
        let cell = try #require(grid.collectionView.visibleItems().compactMap { $0 as? GridPhotoItem }.first)
        let tile = try #require(cell.tileLayer)
        #expect(abs(tile.frame.width - (cellWidth - 8)) < 0.02)
        #expect(abs(tile.frame.height - tileHeight) < 0.02)
    }
}

@Test @MainActor func gridSelectionOutlinesTileOnlyAndCurrentRingIsDistinct() throws {
    let cell = GridPhotoItem()
    _ = cell.view
    cell.view.frame = NSRect(x: 0, y: 0, width: 233.6, height: 224.16)
    cell.view.layoutSubtreeIfNeeded()
    cell.isCurrent = true
    cell.isSelected = true
    let tile = try #require(cell.tileLayer)
    let outline = try #require(cell.view.layer?.sublayers?.first { $0.borderWidth == 2 && !$0.isHidden })
    #expect(cell.view.layer?.borderWidth == 0)
    #expect(outline !== cell.currentRingLayer)
    #expect(outline.frame == tile.frame.insetBy(dx: -4, dy: -4))
    #expect(cell.currentRingLayer.frame == tile.bounds.insetBy(dx: 3, dy: 3))
    #expect(!cell.currentRingLayer.isHidden)
    cell.isSelected = false
    #expect(outline.isHidden)
    #expect(!cell.currentRingLayer.isHidden)
}

@Test @MainActor func gridFilenameTruncatesAtEnd() throws {
    let cell = GridPhotoItem()
    _ = cell.view
    let name = try #require(cell.view.subviews.compactMap { $0 as? NSTextField }
        .first { $0.stringValue.isEmpty })
    #expect(name.lineBreakMode == .byTruncatingTail)
    #expect(name.maximumNumberOfLines == 1)
}
