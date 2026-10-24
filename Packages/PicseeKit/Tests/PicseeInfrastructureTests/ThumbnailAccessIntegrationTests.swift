import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PicseeApplication
import PicseeCore
@testable import PicseeInfrastructure

private final class P303CountingDecoder: ImageDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func decode(_ request: ImageDecodeRequest) throws -> DecodedImage {
        lock.withLock { value += 1 }
        return try ImageIODecoder().decode(request)
    }
}

private func p303SolidTIFF(_ url: URL, red: CGFloat) throws {
    let context = try #require(CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8,
        bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: red, green: 0, blue: 1 - red, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
}

@Test func p303AccessSourceReopensFromDiskButDeniedAccessAndPublicPipelineDoNotHit() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("image.png")
    let cacheDirectory = folder.appendingPathComponent("cache")
    try FileManager.default.copyItem(at: fixture("coordinate-grid.png"), to: file)
    let scope = CountingScope()
    let access = try FileAccess(scope: scope, bookmarks: FakeBookmarks(),
                                store: BookmarkStore(url: folder.appendingPathComponent("roots.json")), buildSHA: "p303")
    let root = try await access.grant(folder: folder)
    let firstDecoder = P303CountingDecoder()
    let firstPipeline = ImageIOPipeline(decoder: firstDecoder, thumbnailCache: ThumbnailDiskCache(directory: cacheDirectory))
    let first = try await AccessImageSource.open(.root(root, file: file), access: access, pipeline: firstPipeline)
    let (_, firstImage) = try await first.image(maximumPixelSize: 128)
    await first.close()
    #expect(firstDecoder.count == 1)

    let reopenedDecoder = P303CountingDecoder()
    let reopenedPipeline = ImageIOPipeline(decoder: reopenedDecoder, thumbnailCache: ThumbnailDiskCache(directory: cacheDirectory))
    let reopened = try await AccessImageSource.open(.root(root, file: file), access: access, pipeline: reopenedPipeline)
    let (_, hit) = try await reopened.image(maximumPixelSize: 128)
    await reopened.close()
    #expect(try rgba(hit.image) == rgba(firstImage.image))
    #expect(reopenedDecoder.count == 0)

    scope.succeeds = false
    await #expect(throws: FileAccessError.startFailed) {
        try await AccessImageSource.open(.root(root, file: file), access: access, pipeline: reopenedPipeline)
    }
    #expect(reopenedDecoder.count == 0)
    let direct = try await reopenedPipeline.request(for: file, maximumPixelSize: 128,
        identityRoot: ItemIdentityRoot(id: root, url: folder))
    _ = try await reopenedPipeline.image(for: direct)
    #expect(reopenedDecoder.count == 1)
}

@Test func p303AccessSourceSameSizeSameTimeReplacementDecodesNewPixels() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("image.tiff")
    let replacement = folder.appendingPathComponent("replacement.tiff")
    let cacheDirectory = folder.appendingPathComponent("cache")
    try p303SolidTIFF(file, red: 1)
    try p303SolidTIFF(replacement, red: 0)
    #expect(try Data(contentsOf: file).count == Data(contentsOf: replacement).count)
    let timestamp = Date(timeIntervalSince1970: 1_000_000)
    try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: file.path)
    let scope = CountingScope()
    let access = try FileAccess(scope: scope, bookmarks: FakeBookmarks(),
                                store: BookmarkStore(url: folder.appendingPathComponent("roots.json")), buildSHA: "p303")
    let root = try await access.grant(folder: folder)
    let firstDecoder = P303CountingDecoder()
    let first = try await AccessImageSource.open(.root(root, file: file), access: access,
        pipeline: ImageIOPipeline(decoder: firstDecoder, thumbnailCache: ThumbnailDiskCache(directory: cacheDirectory)))
    let (_, old) = try await first.image(maximumPixelSize: 64)
    await first.close()
    #expect(firstDecoder.count == 1)
    try Data(contentsOf: replacement).write(to: file, options: .atomic)
    try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: file.path)
    let secondDecoder = P303CountingDecoder()
    let second = try await AccessImageSource.open(.root(root, file: file), access: access,
        pipeline: ImageIOPipeline(decoder: secondDecoder, thumbnailCache: ThumbnailDiskCache(directory: cacheDirectory)))
    let (_, fresh) = try await second.image(maximumPixelSize: 64)
    await second.close()
    #expect(secondDecoder.count == 1)
    #expect(try rgba(old.image) != rgba(fresh.image))
}

@Test func p303FileGrantNeverCreatesPersistentThumbnail() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("image.png")
    let cacheDirectory = folder.appendingPathComponent("cache")
    try FileManager.default.copyItem(at: fixture("coordinate-grid.png"), to: file)
    let scope = CountingScope()
    let access = try FileAccess(scope: scope, bookmarks: FakeBookmarks(),
                                store: BookmarkStore(url: folder.appendingPathComponent("roots.json")), buildSHA: "p303")
    let source = try await AccessImageSource.open(.fileGrant(file), access: access,
        pipeline: ImageIOPipeline(thumbnailCache: ThumbnailDiskCache(directory: cacheDirectory)))
    _ = try await source.image(maximumPixelSize: 128)
    await source.close()
    #expect(!FileManager.default.fileExists(atPath: cacheDirectory.path))
}
