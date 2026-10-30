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
    let cases: [(CGFloat, CGFloat)] = [
        (1600, 200), (1599, 225), (1280, 188.16), (1051, 154.497),
        (1050, 165), (721, 165), (720, 150), (481, 150), (480, 150),
    ]
    for (width, expectedHeight) in cases {
        let (grid, shell, window) = try issue281Grid(width: width)
        defer { window.close() }
        let layout = try #require(grid.collectionView.collectionViewLayout as? NSCollectionViewFlowLayout)
        let cell = try #require(grid.collectionView.item(at: IndexPath(item: 0, section: 0)) as? GridPhotoItem)
        let tile = try #require(cell.tileLayer)
        let expected = try design.length(".thumbnail-wrap", "height", viewport: Double(width))
        #expect(abs(expected - expectedHeight) < 0.01, "CSS fixture at \(width)")
        #expect(abs(tile.frame.height - expectedHeight) <= 1, "thumbnail height at \(width): \(tile.frame)")
        if width == 1280 {
            #expect(abs(tile.frame.width - 239) <= 1, "1280 thumbnail width")
            let first = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
            let nextRow = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 4, section: 0)))
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
