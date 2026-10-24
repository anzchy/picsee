import CoreGraphics
import Foundation
import ImageIO
import SQLite3
import Testing
import UniformTypeIdentifiers
import PicseeCore
@testable import PicseeInfrastructure

@Test func p303DiskCacheReopensAndSeparatesSourceContent() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("image.tiff")
    let cacheDirectory = folder.appendingPathComponent("cache")
    let timestamp = Date(timeIntervalSince1970: 1_000_000)
    try Data(contentsOf: fixture("orientation-1.tiff")).write(to: file)
    try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: file.path)
    let root = ItemIdentityRoot(id: AccessRootID(), url: folder)
    let pipeline = ImageIOPipeline()
    let request = try await pipeline.request(for: file, maximumPixelSize: 128, identityRoot: root)
    let image = try await pipeline.image(for: request)
    let firstStore = ThumbnailDiskCache(directory: cacheDirectory)
    let ticket = try #require(try await firstStore.prepare(request))
    try await firstStore.store(image, for: ticket)
    let reopened = ThumbnailDiskCache(directory: cacheDirectory)
    let secondTicket = try #require(try await reopened.prepare(request))
    let hit = try #require(try await reopened.load(secondTicket))
    #expect(try rgba(hit.image) == rgba(image.image))
    #expect(hit.sourcePixelSize == image.sourcePixelSize)

    try Data(contentsOf: fixture("orientation-2.tiff")).write(to: file, options: .atomic)
    try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: file.path)
    let replaced = try await pipeline.request(for: file, maximumPixelSize: 128, identityRoot: root)
    let replacementTicket = try #require(try await reopened.prepare(replaced))
    #expect(replacementTicket.key.filename != ticket.key.filename)
    #expect(try await reopened.load(replacementTicket).map { _ in true } == nil)
    #expect(try await reopened.load(ticket).map { _ in true } == nil)
}

@Test func p303ValidForeignPayloadAndBrokenIndexAreCacheMisses() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("image.tiff")
    let cacheDirectory = folder.appendingPathComponent("cache")
    try FileManager.default.copyItem(at: fixture("orientation-1.tiff"), to: file)
    let root = ItemIdentityRoot(id: AccessRootID(), url: folder)
    let pipeline = ImageIOPipeline()
    let request = try await pipeline.request(for: file, maximumPixelSize: 128, identityRoot: root)
    let original = try await pipeline.image(for: request)
    let cache = ThumbnailDiskCache(directory: cacheDirectory)
    let ticket = try #require(try await cache.prepare(request))
    try await cache.store(original, for: ticket)
    let context = try #require(CGContext(data: nil, width: original.image.width, height: original.image.height,
        bitsPerComponent: 8, bytesPerRow: original.image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: original.image.width, height: original.image.height))
    let other = try #require(context.makeImage())
    let bytes = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, other, nil)
    #expect(CGImageDestinationFinalize(destination))
    #expect(other.width == original.image.width && other.height == original.image.height)
    #expect(try rgba(other) != rgba(original.image))
    try (bytes as Data).write(to: cacheDirectory.appendingPathComponent(ticket.key.filename + ".png"))
    #expect(try await cache.load(ticket).map { _ in true } == nil)
    try Data("not sqlite".utf8).write(to: cacheDirectory.appendingPathComponent("index.sqlite3"))
    #expect(try await ThumbnailDiskCache(directory: cacheDirectory).load(ticket).map { _ in true } == nil)
}

@Test func p303SourceEligibilityIsBoundedAndCancellationStopsHashing() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("large.bin")
    FileManager.default.createFile(atPath: file.path, contents: nil)
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: UInt64(ThumbnailDiskCache.maximumSourceBytes + 1))
    try handle.close()
    let revision = try FileRevisionReader.read(file)
    let render = RenderKey(itemID: .rootRelative(rootID: AccessRootID(), relativePath: file.lastPathComponent),
                           revision: revision, maximumPixelSize: 128)
    let request = ImageDecodeRequest(fileURL: file, maximumPixelSize: 128, renderKey: render)
    let cache = ThumbnailDiskCache(directory: folder.appendingPathComponent("cache"))
    #expect(try await cache.prepare(request).map { _ in true } == nil)
    let boundaryHandle = try FileHandle(forWritingTo: file)
    try boundaryHandle.truncate(atOffset: UInt64(ThumbnailDiskCache.maximumSourceBytes))
    try boundaryHandle.close()
    let boundaryRevision = try FileRevisionReader.read(file)
    let boundaryRender = RenderKey(itemID: render.itemID, revision: boundaryRevision, maximumPixelSize: 128)
    let boundaryRequest = ImageDecodeRequest(fileURL: file, maximumPixelSize: 128, renderKey: boundaryRender)
    #expect(try await cache.prepare(boundaryRequest).map { _ in true } == true)
    let cancelled = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await cache.prepare(request)
    }
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("cache").path))
}

@Test func p303MissingPayloadRebuildsAndChangedSourceCannotPublishOldTicket() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("image.tiff")
    let cacheDirectory = folder.appendingPathComponent("cache")
    let time = Date(timeIntervalSince1970: 1_000_000)
    try Data(contentsOf: fixture("orientation-1.tiff")).write(to: file)
    try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path)
    let root = ItemIdentityRoot(id: AccessRootID(), url: folder)
    let pipeline = ImageIOPipeline()
    let request = try await pipeline.request(for: file, maximumPixelSize: 128, identityRoot: root)
    let decoded = try await pipeline.image(for: request)
    let cache = ThumbnailDiskCache(directory: cacheDirectory)
    let ticket = try #require(try await cache.prepare(request))
    try await cache.store(decoded, for: ticket)
    let payload = cacheDirectory.appendingPathComponent(ticket.key.filename + ".png")
    try FileManager.default.removeItem(at: payload)
    #expect(try await cache.load(ticket).map { _ in true } == nil)
    try await cache.store(decoded, for: ticket)
    #expect(try await cache.load(ticket).map { _ in true } == true)

    try Data(contentsOf: fixture("orientation-2.tiff")).write(to: file, options: .atomic)
    try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path)
    let oldPayload = try Data(contentsOf: payload)
    try await cache.store(decoded, for: ticket)
    #expect(try Data(contentsOf: payload) == oldPayload)
    #expect(try await cache.load(ticket).map { _ in true } == nil)
    let rejectedDirectory = folder.appendingPathComponent("rejected-cache")
    try await ThumbnailDiskCache(directory: rejectedDirectory).store(decoded, for: ticket)
    #expect(!FileManager.default.fileExists(atPath: rejectedDirectory.path))
}

@Test func p303SourceChangedDuringPayloadPublicationLeavesNoIndexedImage() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("image.tiff")
    let cacheDirectory = folder.appendingPathComponent("cache")
    let time = Date(timeIntervalSince1970: 1_000_000)
    try Data(contentsOf: fixture("orientation-1.tiff")).write(to: file)
    try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path)
    let root = ItemIdentityRoot(id: AccessRootID(), url: folder)
    let pipeline = ImageIOPipeline()
    let request = try await pipeline.request(for: file, maximumPixelSize: 128, identityRoot: root)
    let decoded = try await pipeline.image(for: request)
    let cache = ThumbnailDiskCache(directory: cacheDirectory, afterPayloadWrite: {
        try Data(contentsOf: fixture("orientation-2.tiff")).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: time], ofItemAtPath: file.path)
    })
    let ticket = try #require(try await cache.prepare(request))
    try await cache.store(decoded, for: ticket)
    #expect(!FileManager.default.fileExists(atPath: cacheDirectory.appendingPathComponent(ticket.key.filename + ".png").path))
    #expect(!FileManager.default.fileExists(atPath: cacheDirectory.appendingPathComponent("index.sqlite3").path))
}

@Test func p303UnopenableIndexCannotDeliverPixels() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("image.tiff")
    let cacheDirectory = folder.appendingPathComponent("cache")
    try FileManager.default.copyItem(at: fixture("orientation-1.tiff"), to: file)
    let root = ItemIdentityRoot(id: AccessRootID(), url: folder)
    let pipeline = ImageIOPipeline()
    let request = try await pipeline.request(for: file, maximumPixelSize: 128, identityRoot: root)
    let decoded = try await pipeline.image(for: request)
    let cache = ThumbnailDiskCache(directory: cacheDirectory)
    let ticket = try #require(try await cache.prepare(request))
    try FileManager.default.createDirectory(at: cacheDirectory.appendingPathComponent("index.sqlite3"),
        withIntermediateDirectories: true)
    await #expect(throws: Error.self) { try await cache.store(decoded, for: ticket) }
    #expect(try await cache.load(ticket).map { _ in true } == nil)
}

@Test func p303DamagedIndexDimensionsCannotAlterDeliveredSourceSize() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("image.tiff")
    let cacheDirectory = folder.appendingPathComponent("cache")
    try FileManager.default.copyItem(at: fixture("orientation-1.tiff"), to: file)
    let root = ItemIdentityRoot(id: AccessRootID(), url: folder)
    let pipeline = ImageIOPipeline()
    let request = try await pipeline.request(for: file, maximumPixelSize: 128, identityRoot: root)
    let decoded = try await pipeline.image(for: request)
    let cache = ThumbnailDiskCache(directory: cacheDirectory)
    let ticket = try #require(try await cache.prepare(request))
    try await cache.store(decoded, for: ticket)
    var db: OpaquePointer?
    #expect(sqlite3_open_v2(cacheDirectory.appendingPathComponent("index.sqlite3").path,
                            &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
    defer { if let db { sqlite3_close(db) } }
    #expect(sqlite3_exec(db, "UPDATE thumbnails SET source_width=999", nil, nil, nil) == SQLITE_OK)
    #expect(try await cache.load(ticket).map { _ in true } == nil)
}
