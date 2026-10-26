import AppKit
import Testing
import PicseeCore
@testable import PicseeMacUI

/// Counts loader calls per item and priority; each item's outcome is chosen by the test.
private actor PressureLoaderLog {
    private(set) var calls: [ItemID: [DecodePriority]] = [:]
    private var waiters: [(condition: @Sendable ([ItemID: [DecodePriority]]) -> Bool, continuation: CheckedContinuation<Void, Never>)] = []
    func record(_ id: ItemID, _ priority: DecodePriority) {
        calls[id, default: []].append(priority)
        let ready = waiters.indices.filter { waiters[$0].condition(calls) }
        for index in ready.reversed() { waiters.remove(at: index).continuation.resume() }
    }
    func until(_ condition: @escaping @Sendable ([ItemID: [DecodePriority]]) -> Bool) async {
        if condition(calls) { return }
        await withCheckedContinuation { waiters.append((condition, $0)) }
    }
    var priorities: Set<DecodePriority> { Set(calls.values.flatMap { $0 }) }
}

private func pressureDecoded(_ entry: FolderEntry, coverage: ThumbnailCoverage) -> (ImageDecodeRequest, DecodedImage) {
    let key = RenderKey(itemID: entry.itemID, revision: FileRevision(byteCount: 4, modificationDate: nil),
                        maximumPixelSize: coverage.fallbackEdge)
    let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return (ImageDecodeRequest(fileURL: entry.url, maximumPixelSize: key.maximumPixelSize, renderKey: key),
            DecodedImage(image: context.makeImage()!, sourcePixelSize: CGSize(width: 1, height: 1), revision: key.revision, itemID: entry.itemID))
}

private let pressureTile = ThumbnailCoverage(width: 212, height: 212)

@Suite(.timeLimit(.minutes(1))) @MainActor struct GridThumbnailPressureTests {
    // 4.1, 4.2: pressure keeps only visible cells; held prefetched results are released, visible ones stay.
    @Test func pressureDropsPrefetchedResultsAndRequestsOnlyVisibleCells() async {
        let snapshot = pinningSnapshot(count: 20), fake = RecordingPinning(), log = PressureLoaderLog()
        let ids = snapshot.navigationEntries.map(\.itemID)
        let scheduler = GridThumbnailScheduler()
        scheduler.pinning = fake
        scheduler.setSnapshot(snapshot)
        let loader: GridThumbnailScheduler.Loader = { entry, _, coverage, priority in
            await log.record(entry.itemID, priority)
            return pressureDecoded(entry, coverage: coverage)
        }
        scheduler.reconcile(visible: [5], columns: 1, coverage: pressureTile, loader: loader)
        for index in 3...7 { await scheduler.waitForTerminal(at: index) }
        await scheduler.settlePins()
        #expect(await fake.held == 5)
        scheduler.setMemoryPressure(true)
        scheduler.reconcile(visible: [5], columns: 1, coverage: pressureTile, loader: loader)
        await scheduler.settlePins()
        #expect(scheduler.activeItemIDs == [ids[5]])
        #expect(scheduler.result(at: 5) != nil)
        #expect(await fake.held == 1)
        scheduler.reconcile(visible: [10, 11], columns: 1, coverage: pressureTile, loader: loader)
        for index in 10...11 { await scheduler.waitForTerminal(at: index) }
        #expect(scheduler.activeItemIDs == [ids[10], ids[11]])
        let underPressure = await log.calls
        #expect(underPressure[ids[9]] == nil && underPressure[ids[12]] == nil)
        #expect(await log.calls[ids[10]] == [.visible])
        scheduler.setMemoryPressure(false)
        scheduler.reconcile(visible: [10, 11], columns: 1, coverage: pressureTile, loader: loader)
        await log.until { $0[ids[13]] == [.prefetch] && $0[ids[8]] == [.prefetch] }
        scheduler.stop()
    }

    // 4.3, 4.3c, 4.5: a prefetch the pipeline refuses is deferred, not failed, and only the next reconcile retries it.
    @Test func refusedPrefetchIsDeferredUntilTheNextReconcile() async {
        let snapshot = pinningSnapshot(count: 5), log = PressureLoaderLog()
        let ids = snapshot.navigationEntries.map(\.itemID)
        let refusing = Refusal()
        let scheduler = GridThumbnailScheduler()
        scheduler.setSnapshot(snapshot)
        var failures: [Int] = []
        scheduler.onFailure = { failures.append($0) }
        let loader: GridThumbnailScheduler.Loader = { entry, _, coverage, priority in
            await log.record(entry.itemID, priority)
            if await refusing.on { throw ImageLoadError(.cancelled, itemID: entry.itemID) }
            return pressureDecoded(entry, coverage: coverage)
        }
        await refusing.set(true)
        scheduler.reconcile(visible: [0], columns: 1, coverage: pressureTile, loader: loader)
        for index in 0...2 { await scheduler.waitForTerminal(at: index) }
        #expect(failures == [0])
        #expect(scheduler.shouldDisplayFailure(at: 0))
        for index in 1...2 {
            #expect(!scheduler.shouldDisplayFailure(at: index))
            #expect(scheduler.result(at: index) == nil)
        }
        #expect(scheduler.activeItemIDs == [ids[0]])
        #expect(await log.calls[ids[1]] == [.prefetch])
        await refusing.set(false)
        scheduler.reconcile(visible: [0], columns: 1, coverage: pressureTile, loader: loader)
        for index in 1...2 { await scheduler.waitForTerminal(at: index) }
        #expect(scheduler.result(at: 1) != nil && scheduler.result(at: 2) != nil)
        #expect(await log.calls[ids[1]] == [.prefetch, .prefetch])
        #expect(failures == [0])
        scheduler.stop()
    }

    // 4.3b: a real prefetch failure still shows and is not retried while the cell stays off screen.
    @Test func failedPrefetchStillFailsAndIsNotRetriedOffScreen() async {
        let snapshot = pinningSnapshot(count: 3), log = PressureLoaderLog()
        let ids = snapshot.navigationEntries.map(\.itemID)
        let scheduler = GridThumbnailScheduler()
        scheduler.setSnapshot(snapshot)
        var failures: [Int] = []
        scheduler.onFailure = { failures.append($0) }
        let loader: GridThumbnailScheduler.Loader = { entry, _, coverage, priority in
            await log.record(entry.itemID, priority)
            if entry.itemID == ids[2] { throw ImageLoadError(.corruptImage, itemID: entry.itemID) }
            return pressureDecoded(entry, coverage: coverage)
        }
        scheduler.reconcile(visible: [0], columns: 1, coverage: pressureTile, loader: loader)
        for index in 0...2 { await scheduler.waitForTerminal(at: index) }
        #expect(failures == [2])
        #expect(scheduler.shouldDisplayFailure(at: 2))
        scheduler.reconcile(visible: [0], columns: 1, coverage: pressureTile, loader: loader)
        #expect(await log.calls[ids[2]] == [.prefetch])
        scheduler.stop()
    }

    // 4.4: the view drops margin rows under pressure and requests them again as soon as it ends, without a scroll.
    @Test func gridViewResumesPrefetchWhenPressureEnds() async throws {
        _ = NSApplication.shared
        let snapshot = pinningSnapshot(count: 200), log = PressureLoaderLog()
        let grid = GridBrowserView(frame: NSRect(x: 0, y: 0, width: 700, height: 550))
        let window = NSWindow(contentRect: grid.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = grid
        grid.thumbnailLoader = { entry, _, coverage, priority in
            await log.record(entry.itemID, priority)
            return pressureDecoded(entry, coverage: coverage)
        }
        grid.display(snapshot, selectedItemID: nil)
        window.layoutIfNeeded()
        grid.layoutSubtreeIfNeeded()
        grid.setMemoryPressure(true)
        grid.setThumbnailsActive(true)
        await grid.waitForThumbnail(at: 0)
        #expect(await log.priorities == [.visible])
        grid.setMemoryPressure(false)
        await log.until { $0.values.contains { $0.contains(.prefetch) } }
        grid.stopThumbnails()
    }
}

private actor Refusal {
    private(set) var on = false
    func set(_ value: Bool) { on = value }
}
