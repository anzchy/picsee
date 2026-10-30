import AppKit
import Testing
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
@testable import PicseeMacUI

@MainActor private func issue281Grid(width: CGFloat, count: Int = 12) throws -> (GridBrowserView, GridShellView, NSWindow) {
    _ = NSApplication.shared
    let store = InMemoryDisplayPreferencesStore()
    let shell = GridShellView(frame: NSRect(x: 0, y: 0, width: width, height: 772), preferencesStore: store)
    let grid = GridBrowserView(frame: NSRect(origin: .zero, size: shell.mainFrame.size))
    grid.autoresizingMask = [.width, .height]
    shell.mainContent.addSubview(grid)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 800),
                          styleMask: [], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = shell
    let folder = URL(fileURLWithPath: "/tmp/picsee-grid-281")
    let root = ItemIdentityRoot(id: AccessRootID(rawValue: UUID()), url: folder)
    let entries = (0..<count).map { FolderEntry(url: folder.appendingPathComponent("DSC_\($0).jpg"), root: root) }
    grid.display(FolderSnapshot(version: .init(rootID: root.id, folder: folder, generation: 1),
        entries: entries, isComplete: true), selectedItemID: nil)
    grid.activate()
    shell.layoutSubtreeIfNeeded()
    grid.layoutSubtreeIfNeeded()
    grid.collectionView.layoutSubtreeIfNeeded()
    return (grid, shell, window)
}

@Test @MainActor func issue281ThumbnailFramesAndPitchUseWindowViewportAtBreakpoints() throws {
    let design = try PinnedDesign.page("grid-light")
    let cases: [(width: CGFloat, height: CGFloat, columns: Int, inset: CGFloat, gap: CGFloat, rowGap: CGFloat)] = [
        (1600, 200, 5, 32, 22, 22), (1599, 225, 5, 24, 16, 18),
        (1280, 188.16, 4, 24, 16, 18), (1051, 154.497, 3, 24, 16, 18),
        (1050, 165, 3, 16, 12, 12), (721, 165, 2, 16, 12, 12),
        (720, 150, 3, 16, 12, 12), (481, 150, 1, 16, 12, 12), (480, 150, 1, 16, 12, 12),
    ]
    for item in cases {
        let (grid, shell, window) = try issue281Grid(width: item.width)
        defer { window.close() }
        let layout = try #require(grid.collectionView.collectionViewLayout as? NSCollectionViewFlowLayout)
        let cell = try #require(grid.collectionView.item(at: IndexPath(item: 0, section: 0)) as? GridPhotoItem)
        let tile = try #require(cell.tileLayer)
        let expected = try design.length(".thumbnail-wrap", "height", viewport: Double(item.width))
        #expect(abs(expected - item.height) < 0.01, "CSS fixture at \(item.width)")
        #expect(abs(tile.frame.height - item.height) <= 1, "thumbnail height at \(item.width): \(tile.frame)")
        let cssGaps = try design.edges(".photo-grid", "gap", viewport: Double(item.width))
        #expect(cssGaps.right == item.gap && cssGaps.top == item.rowGap, "horizontal CSS at \(item.width)")
        // grid-light.html: @media switches .grid-scroll padding-left/right and .photo-grid gap/grid-template-columns on viewport width.
        #expect(abs(layout.sectionInset.left - item.inset) <= 1, "inset at \(item.width)")
        #expect(abs(layout.minimumInteritemSpacing - item.gap) <= 1, "column gap at \(item.width)")
        #expect(abs(layout.minimumLineSpacing - item.rowGap) <= 1, "row gap at \(item.width)")
        let first = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        let lastInRow = try #require(layout.layoutAttributesForItem(at: IndexPath(item: item.columns - 1, section: 0)))
        let nextRow = try #require(layout.layoutAttributesForItem(at: IndexPath(item: item.columns, section: 0)))
        let contentWidth = shell.mainFrame.width
        let expectedWidth = (contentWidth - 2 * item.inset - CGFloat(item.columns - 1) * item.gap) / CGFloat(item.columns)
        #expect(abs(layout.itemSize.width - expectedWidth) <= 1, "columns at \(item.width)")
        #expect(abs(first.frame.minX - item.inset) <= 1, "first tile x at \(item.width)")
        #expect(abs(lastInRow.frame.minX - first.frame.minX
            - CGFloat(item.columns - 1) * (expectedWidth + item.gap)) <= 1, "last tile x at \(item.width)")
        #expect(abs(nextRow.frame.minY - first.frame.minY - layout.itemSize.height - item.rowGap) <= 1, "row pitch at \(item.width)")
        if item.width == 1280 {
            #expect(abs(tile.frame.width - 239) <= 1, "1280 thumbnail width")
            #expect(abs(nextRow.frame.minY - first.frame.minY - 242.16) <= 1, "1280 row pitch")
            #expect(abs(shell.mainFrame.minX + first.frame.minX + 4 - 224) <= 1, "1280 first tile x")
        }
    }
}

private func issue281Image(width: Int, height: Int) -> CGImage {
    let data = Data(repeating: 80, count: width * height * 4)
    let provider = CGDataProvider(data: data as CFData)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

@Test @MainActor func issue281ThumbnailCoverFillHandlesLandscapePortraitAndSinglePixelImages() throws {
    for (width, height) in [(3, 2), (2, 3), (1, 1)] {
        let cell = GridPhotoItem()
        let folder = URL(fileURLWithPath: "/tmp/picsee-grid-281-cover")
        let root = ItemIdentityRoot(id: AccessRootID(rawValue: UUID()), url: folder)
        let entry = FolderEntry(url: folder.appendingPathComponent("\(width)x\(height).jpg"), root: root)
        cell.configure(entry)
        let edge = max(width, height)
        cell.beginThumbnail(generation: 1, pixelEdge: edge)
        let revision = FileRevision(byteCount: 1, modificationDate: nil)
        let key = RenderKey(itemID: entry.itemID, revision: revision, maximumPixelSize: edge)
        let request = ImageDecodeRequest(fileURL: entry.url, maximumPixelSize: edge, renderKey: key)
        let image = DecodedImage(image: issue281Image(width: width, height: height),
            sourcePixelSize: CGSize(width: width, height: height), revision: revision, itemID: entry.itemID)
        #expect(cell.installThumbnail(request, image: image, token: cell.thumbnailToken,
            generation: 1, pixelEdge: edge), "install \(width)x\(height)")
        let tile = try #require(cell.tileLayer)
        #expect(tile.contents != nil)
        #expect(tile.contentsGravity == .resizeAspectFill, "cover fill \(width)x\(height)")
        #expect(tile.frame == NSRect(x: 4, y: 32, width: cell.view.bounds.width - 8,
            height: cell.view.bounds.height - 36), "thumbnail fills its box \(width)x\(height)")
    }
}
