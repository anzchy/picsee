import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PicseeApplication
import PicseeCore
@testable import PicseeInfrastructure

private final class DiskCountingDecoder: ImageDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func decode(_ request: ImageDecodeRequest) throws -> DecodedImage {
        lock.withLock { value += 1 }
        return try ImageIODecoder().decode(request)
    }
}

/// One granted folder holding a real 1280×960 PNG and a durable thumbnail cache directory.
private struct DiskRig {
    let folder: URL, file: URL, cacheDirectory: URL
    let access: FileAccess
    let root: AccessRootID
    init(source: URL = fixture("coordinate-grid.png")) async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        file = folder.appendingPathComponent("image.png")
        cacheDirectory = folder.appendingPathComponent("cache")
        try FileManager.default.copyItem(at: source, to: file)
        access = try FileAccess(scope: CountingScope(), bookmarks: FakeBookmarks(),
            store: BookmarkStore(url: folder.appendingPathComponent("roots.json")), buildSHA: "p306-r1")
        root = try await access.grant(folder: folder)
    }
    func load(_ pipeline: ImageIOPipeline, edge: Int, priority: DecodePriority) async throws -> (ImageDecodeRequest, DecodedImage) {
        let source = try await AccessImageSource.open(.root(root, file: file), access: access, pipeline: pipeline)
        do {
            let result = try await source.image(maximumPixelSize: edge, priority: priority)
            await source.close()
            return result
        } catch { await source.close(); throw error }
    }
    func remove() { try? FileManager.default.removeItem(at: folder) }
}

/// Holds every disk payload read at its lease until `open()`; counts reads that reached it.
private actor DiskReadGate {
    private(set) var reads = 0
    private var isOpen = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var readWaiters: [CheckedContinuation<Void, Never>] = []
    func pass() async {
        reads += 1
        for waiter in readWaiters { waiter.resume() }
        readWaiters.removeAll()
        if !isOpen { await withCheckedContinuation { held.append($0) } }
    }
    func untilRead() async {
        if reads > 0 { return }
        await withCheckedContinuation { readWaiters.append($0) }
    }
    func open() {
        isOpen = true
        for waiter in held { waiter.resume() }
        held.removeAll()
    }
}

private func waitUntilWaiting(_ pipeline: ImageIOPipeline, _ count: Int) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while await pipeline.admission.activity().waiting != count, ContinuousClock.now < deadline { await Task.yield() }
}

@Suite(.timeLimit(.minutes(1))) struct MemoryBudgetDiskTests {
    /// A 16-pixel thumbnail of the fixture; the warm load reserves the square bound for that edge.
    private static let edge = 16
    private static func squareCost() throws -> Int {
        try DecodeBudget.outputCost(width: edge, height: edge, maximumPixelSize: edge, bytesPerPixel: 4, budget: .max)
    }

    // R1 2.1 (gpt F2): a warm disk-cache decode waits for the square bound of room, even when its real payload would fit,
    // holds that reservation while it decodes, and completes from disk once room frees.
    @Test func warmDiskLoadWaitsForTheSharedBudgetAndProceedsWhenRoomFrees() async throws {
        let rig = try await DiskRig()
        defer { rig.remove() }
        let square = try Self.squareCost(), limit = 2 * square, decoder = DiskCountingDecoder(), gate = DiskReadGate()
        let pipeline = ImageIOPipeline(decoder: decoder, configuration: DecodeConfiguration(budget: limit, cacheCapacity: limit),
            thumbnailCache: ThumbnailDiskCache(directory: rig.cacheDirectory, afterReadLeaseAcquired: { await gate.pass() }))
        let budget = try #require(pipeline.cache.budget)
        let (_, source) = try await rig.load(pipeline, edge: Self.edge, priority: .visible)
        try #require(decoder.count == 1)
        let payload = source.image.bytesPerRow * source.image.height
        try #require(payload < square && (limit - payload) % 16 == 0)
        // Leaves exactly the real payload's bytes free: enough for the pixels, not for the bound.
        let filler = cacheKey(900)
        await pipeline.pin(filler, image: cacheImage(try cachePixels(rows: (limit - payload) / 16), key: filler))
        try #require(budget.usage == MemoryBudget.Usage(pinned: limit - payload, evictable: 0, reserved: 0))
        let warm = Task { try await rig.load(pipeline, edge: Self.edge, priority: .visible) }
        await waitUntilWaiting(pipeline, 1)
        #expect(await pipeline.admission.activity().waiting == 1)
        #expect(await pipeline.admission.activity().reservedBytes == 0)
        #expect(await gate.reads == 0)
        await pipeline.unpin(filler)
        await gate.untilRead()
        #expect(await pipeline.admission.activity().reservedBytes == square)
        #expect(budget.usage.reserved == square)
        await gate.open()
        let (_, image) = try await warm.value
        #expect(image.image.width == Self.edge)
        #expect(decoder.count == 1)
        #expect(budget.peak <= limit)
        #expect(budget.usage.reserved == 0)
        #expect(await pipeline.admission.activity().waiting == 0)
    }

    // R1 2.1b: a damaged payload releases its reservation and the source decode that replaces it is admitted.
    @Test func warmDiskLoadOfADamagedPayloadReleasesItsReservation() async throws {
        let rig = try await DiskRig()
        defer { rig.remove() }
        let limit = 2 * (try Self.squareCost()), decoder = DiskCountingDecoder()
        let pipeline = ImageIOPipeline(decoder: decoder, configuration: DecodeConfiguration(budget: limit, cacheCapacity: limit),
            thumbnailCache: ThumbnailDiskCache(directory: rig.cacheDirectory))
        let budget = try #require(pipeline.cache.budget)
        _ = try await rig.load(pipeline, edge: Self.edge, priority: .visible)
        let payloads = try FileManager.default.contentsOfDirectory(at: rig.cacheDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }
        try #require(payloads.count == 1)
        try Data(repeating: 7, count: 64).write(to: payloads[0])
        let (_, image) = try await rig.load(pipeline, edge: Self.edge, priority: .visible)
        #expect(image.image.width == Self.edge)
        #expect(decoder.count == 2)
        #expect(budget.usage.reserved == 0)
        #expect(await pipeline.admission.activity().running == 0)
    }

    // R1 2.1c: a budget smaller than the square bound caps the reservation instead of refusing the load.
    // An 8×8 source asked at edge 16 costs 512 bytes to decode from source but 1024 as a square bound.
    @Test func warmDiskLoadCostIsCappedAtTheBudget() async throws {
        let small = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: small) }
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let destination = try #require(CGImageDestinationCreateWithURL(small as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        try #require(CGImageDestinationFinalize(destination))
        let rig = try await DiskRig(source: small)
        defer { rig.remove() }
        let warmer = ImageIOPipeline(thumbnailCache: ThumbnailDiskCache(directory: rig.cacheDirectory))
        _ = try await rig.load(warmer, edge: Self.edge, priority: .visible)
        let limit = 600, decoder = DiskCountingDecoder()
        try #require(limit < (try Self.squareCost()))
        let pipeline = ImageIOPipeline(decoder: decoder, configuration: DecodeConfiguration(budget: limit, cacheCapacity: limit),
            thumbnailCache: ThumbnailDiskCache(directory: rig.cacheDirectory))
        let (_, image) = try await rig.load(pipeline, edge: Self.edge, priority: .visible)
        #expect(image.image.width == 8)
        #expect(decoder.count == 0)
        #expect(try #require(pipeline.cache.budget).peak == limit)
    }

    // R1 2.2: a warm load cancelled while it waits for room leaves nothing queued or reserved.
    @Test func warmDiskLoadCancelledWhileWaitingLeavesNoStaging() async throws {
        let rig = try await DiskRig()
        defer { rig.remove() }
        let limit = 2 * (try Self.squareCost())
        let pipeline = ImageIOPipeline(configuration: DecodeConfiguration(budget: limit, cacheCapacity: limit),
            thumbnailCache: ThumbnailDiskCache(directory: rig.cacheDirectory))
        let budget = try #require(pipeline.cache.budget)
        _ = try await rig.load(pipeline, edge: Self.edge, priority: .visible)
        let filler = cacheKey(901)
        await pipeline.pin(filler, image: cacheImage(try cachePixels(rows: limit / 16), key: filler))
        let warm = Task { try await rig.load(pipeline, edge: Self.edge, priority: .prefetch) }
        await waitUntilWaiting(pipeline, 1)
        #expect(await pipeline.admission.activity().waiting == 1)
        warm.cancel()
        await #expect(throws: CancellationError.self) { try await warm.value }
        #expect(await pipeline.admission.activity().waiting == 0)
        #expect(budget.usage.reserved == 0)
        await pipeline.unpin(filler)
        #expect(budget.usage.pinned == 0)
    }
}
