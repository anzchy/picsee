import CoreGraphics
import Foundation
import ImageIO
import SQLite3
import Testing
import UniformTypeIdentifiers
import PicseeCore
@testable import PicseeInfrastructure

private func pngPaddedToExactLength(_ source: Data, targetLength: Int) throws -> Data {
    let input = [UInt8](source)
    let iend: [UInt8] = [0, 0, 0, 0, 73, 69, 78, 68]
    guard input.count >= 12, Array(input.suffix(12).prefix(8)) == iend,
          targetLength >= input.count + 12 else {
        throw ImageDecodeError.invalidRequest
    }
    let paddingCount = targetLength - input.count - 12
    let type: [UInt8] = [110, 112, 65, 68] // npAD: ancillary, private PNG chunk.
    let body = type + [UInt8](repeating: 0, count: paddingCount)
    var crc: UInt32 = 0xffffffff
    for byte in body {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
    }
    crc ^= 0xffffffff
    let length = UInt32(paddingCount).bigEndian
    let checksum = crc.bigEndian
    var result = Data(input.dropLast(12))
    withUnsafeBytes(of: length) { result.append(contentsOf: $0) }
    result.append(contentsOf: body)
    withUnsafeBytes(of: checksum) { result.append(contentsOf: $0) }
    result.append(contentsOf: input.suffix(12))
    return result
}

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
    let storedPayload = try Data(contentsOf: cacheDirectory.appendingPathComponent(ticket.key.filename + ".png"))
    bytes.setData(try pngPaddedToExactLength(bytes as Data, targetLength: storedPayload.count))
    let foreignSource = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
    #expect(CGImageSourceGetStatusAtIndex(foreignSource, 0) == .statusComplete)
    let foreignPixels = try #require(CGImageSourceCreateImageAtIndex(foreignSource, 0, nil))
    #expect(foreignPixels.width == original.image.width && foreignPixels.height == original.image.height)
    #expect(try rgba(foreignPixels) != rgba(original.image))
    #expect((bytes as Data).count == storedPayload.count)
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
    do {
        try await cache.store(decoded, for: ticket)
        Issue.record("changed source was accepted for store")
    } catch let error as ImageLoadError {
        #expect(error.kind == .sourceChanged)
    }
    #expect(try Data(contentsOf: payload) == oldPayload)
    #expect(try await cache.load(ticket).map { _ in true } == nil)
    let rejectedDirectory = folder.appendingPathComponent("rejected-cache")
    do {
        try await ThumbnailDiskCache(directory: rejectedDirectory).store(decoded, for: ticket)
        Issue.record("changed source was accepted for another store")
    } catch let error as ImageLoadError {
        #expect(error.kind == .sourceChanged)
    }
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
    do {
        try await cache.store(decoded, for: ticket)
        Issue.record("changed source was accepted after payload write")
    } catch let error as ImageLoadError {
        #expect(error.kind == .sourceChanged)
    }
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

@Test func p304NextAccessRepairsOrphanAndDamagedRowWithoutChangingSource() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("image.tiff")
    let cacheDirectory = folder.appendingPathComponent("cache")
    try FileManager.default.copyItem(at: fixture("orientation-1.tiff"), to: file)
    let sourceBytes = try Data(contentsOf: file)
    let root = ItemIdentityRoot(id: AccessRootID(), url: folder)
    let pipeline = ImageIOPipeline()
    let request = try await pipeline.request(for: file, maximumPixelSize: 128, identityRoot: root)
    let decoded = try await pipeline.image(for: request)
    let cache = ThumbnailDiskCache(directory: cacheDirectory)
    let ticket = try #require(try await cache.prepare(request))
    try await cache.store(decoded, for: ticket)
    let payload = cacheDirectory.appendingPathComponent(ticket.key.filename + ".png")
    let orphan = cacheDirectory.appendingPathComponent(String(repeating: "a", count: 64) + ".png")
    try Data(contentsOf: payload).write(to: orphan)
    try Data("bad PNG".utf8).write(to: payload)

    let reopened = ThumbnailDiskCache(directory: cacheDirectory)
    #expect(try await reopened.load(ticket).map { _ in true } == nil)
    #expect(!FileManager.default.fileExists(atPath: orphan.path))
    #expect(!FileManager.default.fileExists(atPath: payload.path))
    var db: OpaquePointer?
    #expect(sqlite3_open_v2(cacheDirectory.appendingPathComponent("index.sqlite3").path,
                            &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    defer { if let db { sqlite3_close(db) } }
    var statement: OpaquePointer?
    #expect(sqlite3_prepare_v2(db, "SELECT count(*) FROM thumbnails", -1, &statement, nil) == SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    #expect(sqlite3_step(statement) == SQLITE_ROW)
    #expect(sqlite3_column_int(statement, 0) == 0)
    #expect(try Data(contentsOf: file) == sourceBytes)
    #expect(try await reopened.load(ticket).map { _ in true } == nil)
}

@Test func p304RecentReadSurvivesHighLowWaterEviction() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let cacheDirectory = folder.appendingPathComponent("cache")
    let root = ItemIdentityRoot(id: AccessRootID(), url: folder)
    let pipeline = ImageIOPipeline()
    let seed = ThumbnailDiskCache(directory: cacheDirectory)
    var tickets: [ThumbnailCacheTicket] = []
    var images: [DecodedImage] = []
    for index in 0..<3 {
        let file = folder.appendingPathComponent("image-\(index).tiff")
        try FileManager.default.copyItem(at: fixture("orientation-1.tiff"), to: file)
        let request = try await pipeline.request(for: file, maximumPixelSize: 128, identityRoot: root)
        tickets.append(try #require(try await seed.prepare(request)))
        images.append(try await pipeline.image(for: request))
    }
    try await seed.store(images[0], for: tickets[0])
    try await seed.store(images[1], for: tickets[1])
    let firstPayload = cacheDirectory.appendingPathComponent(tickets[0].key.filename + ".png")
    let secondPayload = cacheDirectory.appendingPathComponent(tickets[1].key.filename + ".png")
    let bytes = try Data(contentsOf: firstPayload).count
    #expect(try Data(contentsOf: secondPayload).count == bytes)
    let limited = ThumbnailDiskCache(directory: cacheDirectory,
                                     highWaterBytes: 2 * bytes + 1, lowWaterBytes: 2 * bytes)
    #expect(try await limited.load(tickets[0]).map { _ in true } == true)
    try await limited.store(images[2], for: tickets[2])
    #expect(FileManager.default.fileExists(atPath: firstPayload.path))
    #expect(!FileManager.default.fileExists(atPath: secondPayload.path))
    #expect(FileManager.default.fileExists(atPath: cacheDirectory.appendingPathComponent(tickets[2].key.filename + ".png").path))
    #expect(try await limited.load(tickets[0]).map { _ in true } == true)
    #expect(try await limited.load(tickets[1]).map { _ in true } == nil)
}

private actor P304ReadGate {
    private var entered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func pause() async {
        entered = true
        entryWaiter?.resume()
        await withCheckedContinuation { releaseWaiter = $0 }
    }
    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }
    func release() { releaseWaiter?.resume() }
}

@Test func p304HeldReaderKeepsPayloadDuringOtherCacheEviction() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let cacheDirectory = folder.appendingPathComponent("cache")
    let root = ItemIdentityRoot(id: AccessRootID(), url: folder)
    let pipeline = ImageIOPipeline()
    let seed = ThumbnailDiskCache(directory: cacheDirectory)
    var tickets: [ThumbnailCacheTicket] = []
    var images: [DecodedImage] = []
    for index in 0..<3 {
        let file = folder.appendingPathComponent("image-\(index).tiff")
        try FileManager.default.copyItem(at: fixture("orientation-1.tiff"), to: file)
        let request = try await pipeline.request(for: file, maximumPixelSize: 128, identityRoot: root)
        tickets.append(try #require(try await seed.prepare(request)))
        images.append(try await pipeline.image(for: request))
    }
    try await seed.store(images[0], for: tickets[0])
    try await seed.store(images[1], for: tickets[1])
    let heldPayload = cacheDirectory.appendingPathComponent(tickets[0].key.filename + ".png")
    let bytes = try Data(contentsOf: heldPayload).count
    let gate = P304ReadGate()
    let reader = ThumbnailDiskCache(directory: cacheDirectory, afterReadLeaseAcquired: { await gate.pause() })
    let heldTicket = tickets[0]
    let pending = Task { try await reader.load(heldTicket).map { _ in true } }
    await gate.waitForEntry()
    let evictor = ThumbnailDiskCache(directory: cacheDirectory,
                                     highWaterBytes: 2 * bytes + 1, lowWaterBytes: 2 * bytes)
    try await evictor.store(images[2], for: tickets[2])
    #expect(FileManager.default.fileExists(atPath: heldPayload.path))
    await gate.release()
    #expect(try await pending.value == true)
}

@Test func p304CorruptIndexRebuildsFromUnchangedSource() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("image.tiff")
    let cacheDirectory = folder.appendingPathComponent("cache")
    try FileManager.default.copyItem(at: fixture("orientation-1.tiff"), to: file)
    let sourceBytes = try Data(contentsOf: file)
    let root = ItemIdentityRoot(id: AccessRootID(), url: folder)
    let pipeline = ImageIOPipeline()
    let request = try await pipeline.request(for: file, maximumPixelSize: 128, identityRoot: root)
    let decoded = try await pipeline.image(for: request)
    let cache = ThumbnailDiskCache(directory: cacheDirectory)
    let ticket = try #require(try await cache.prepare(request))
    try await cache.store(decoded, for: ticket)
    let index = cacheDirectory.appendingPathComponent("index.sqlite3")
    try Data("broken database".utf8).write(to: index)
    let reopened = ThumbnailDiskCache(directory: cacheDirectory)
    #expect(try await reopened.load(ticket).map { _ in true } == nil)
    try await reopened.store(decoded, for: ticket)
    #expect(try await reopened.load(ticket).map { _ in true } == true)
    #expect(try Data(contentsOf: file) == sourceBytes)
}
