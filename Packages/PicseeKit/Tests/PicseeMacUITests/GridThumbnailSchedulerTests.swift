import AppKit
import Foundation
import Testing
import PicseeCore
@testable import PicseeMacUI

private func gridThumbnailSnapshot(rootID: AccessRootID, count: Int, generation: UInt64) -> FolderSnapshot {
    let folder = URL(fileURLWithPath: "/tmp/grid-thumbnail-s2")
    let root = ItemIdentityRoot(id: rootID, url: folder)
    return FolderSnapshot(version: .init(rootID: rootID, folder: folder, generation: generation),
        entries: (0..<count).map { FolderEntry(url: folder.appendingPathComponent(String(format: "%04d.jpg", $0)), root: root) },
        isComplete: true)
}

private actor HeldGridThumbnailPort {
    private(set) var started: Set<ItemID> = []
    private(set) var cancelled: Set<ItemID> = []
    func load(_ entry: FolderEntry) async throws -> (ImageDecodeRequest, DecodedImage) {
        started.insert(entry.itemID)
        do { try await Task.sleep(for: .seconds(60)) }
        catch {
            cancelled.insert(entry.itemID)
            throw error
        }
        throw CancellationError()
    }
}

@Test @MainActor func gridThumbnailRapidScrollKeepsOnlyVisibleAndTwoNearbyRows() {
    let root = AccessRootID(rawValue: UUID())
    let snapshot = gridThumbnailSnapshot(rootID: root, count: 5000, generation: 1)
    let scheduler = GridThumbnailScheduler()
    scheduler.setSnapshot(snapshot)
    let loader: GridThumbnailScheduler.Loader = { _, _, _, _ in throw CancellationError() }
    for visible in [Set(0..<12), Set(2400..<2412), Set(4988..<5000), Set(0..<12)] {
        scheduler.reconcile(visible: visible, columns: 4, pixelEdge: 424, loader: loader)
        let lower = max(0, visible.min()! - 8), upper = min(4999, visible.max()! + 8)
        let allowed = Set((lower...upper).map { snapshot.navigationEntries[$0].itemID })
        #expect(scheduler.activeItemIDs.isSubset(of: allowed))
        #expect(Set(visible.map { snapshot.navigationEntries[$0].itemID }).isSubset(of: scheduler.activeItemIDs))
        #expect(scheduler.activeItemIDs.count <= 28)
    }
    scheduler.stop()
    #expect(scheduler.activeItemIDs.isEmpty)
}

@Test @MainActor func gridThumbnailRootAndScaleReplacementRetireOldRequests() {
    let first = gridThumbnailSnapshot(rootID: AccessRootID(rawValue: UUID()), count: 20, generation: 1)
    let second = gridThumbnailSnapshot(rootID: AccessRootID(rawValue: UUID()), count: 20, generation: 2)
    let scheduler = GridThumbnailScheduler()
    let loader: GridThumbnailScheduler.Loader = { _, _, _, _ in throw CancellationError() }
    scheduler.setSnapshot(first)
    scheduler.reconcile(visible: [0, 1, 2], columns: 3, pixelEdge: 212, loader: loader)
    #expect(scheduler.activeItemIDs.contains(first.navigationEntries[0].itemID))
    scheduler.setSnapshot(second)
    #expect(scheduler.activeItemIDs.isEmpty)
    scheduler.reconcile(visible: [0, 1, 2], columns: 3, pixelEdge: 424, loader: loader)
    #expect(scheduler.activeItemIDs.contains(second.navigationEntries[0].itemID))
    #expect(!scheduler.activeItemIDs.contains(first.navigationEntries[0].itemID))
    scheduler.setSnapshot(nil)
    #expect(scheduler.activeItemIDs.isEmpty)
}

@Test func gridThumbnailPixelSizingRoundsUpForRetina() {
    #expect(GridThumbnailPixelSizing.edge(tile: NSSize(width: 212, height: 148), backingScale: 1) == 212)
    #expect(GridThumbnailPixelSizing.edge(tile: NSSize(width: 212, height: 148), backingScale: 2) == 424)
    #expect(GridThumbnailPixelSizing.edge(tile: NSSize(width: 211.5, height: 148), backingScale: 2) == 423)
    #expect(GridThumbnailPixelSizing.edge(tile: NSSize(width: 900, height: 700), backingScale: 2) == 1024)
}

@Test @MainActor func gridThumbnailScrollAndCloseCancelHeldFilePortWork() async {
    let snapshot = gridThumbnailSnapshot(rootID: AccessRootID(rawValue: UUID()), count: 30, generation: 1)
    let port = HeldGridThumbnailPort()
    let scheduler = GridThumbnailScheduler()
    scheduler.setSnapshot(snapshot)
    let loader: GridThumbnailScheduler.Loader = { entry, _, _, _ in try await port.load(entry) }
    scheduler.reconcile(visible: [0], columns: 1, pixelEdge: 212, loader: loader)
    let first = snapshot.navigationEntries[0].itemID
    for _ in 0..<500 {
        if await port.started.contains(first) { break }
        await Task.yield()
    }
    #expect(await port.started.contains(first))
    scheduler.reconcile(visible: [20], columns: 1, pixelEdge: 212, loader: loader)
    for _ in 0..<500 {
        if await port.cancelled.contains(first) { break }
        await Task.yield()
    }
    #expect(await port.cancelled.contains(first))
    let later = snapshot.navigationEntries[20].itemID
    for _ in 0..<500 {
        if await port.started.contains(later) { break }
        await Task.yield()
    }
    scheduler.stop()
    for _ in 0..<500 {
        if await port.cancelled.contains(later) { break }
        await Task.yield()
    }
    #expect(await port.cancelled.contains(later))
    #expect(scheduler.activeItemIDs.isEmpty)
}

@Test @MainActor func gridThumbnailInvalidDecodedIdentityShowsFailureInsteadOfPendingForever() async {
    let snapshot = gridThumbnailSnapshot(rootID: AccessRootID(rawValue: UUID()), count: 1, generation: 1)
    let scheduler = GridThumbnailScheduler()
    scheduler.setSnapshot(snapshot)
    var failed = false
    scheduler.onFailure = { _ in failed = true }
    let loader: GridThumbnailScheduler.Loader = { entry, _, edge, _ in
        let key = RenderKey(itemID: entry.itemID,
            revision: FileRevision(byteCount: 1, modificationDate: nil), maximumPixelSize: edge)
        let request = ImageDecodeRequest(fileURL: entry.url, maximumPixelSize: edge, renderKey: key)
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = DecodedImage(image: context.makeImage()!, sourcePixelSize: CGSize(width: 1, height: 1),
            revision: key.revision, itemID: .ephemeral(UUID()))
        return (request, image)
    }
    scheduler.reconcile(visible: [0], columns: 1, pixelEdge: 212, loader: loader)
    for _ in 0..<100 {
        if failed { break }
        await Task.yield()
    }
    #expect(failed)
    #expect(scheduler.result(at: 0) == nil)
}
