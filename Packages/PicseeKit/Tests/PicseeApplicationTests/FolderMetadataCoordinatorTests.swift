import Foundation
import Testing
import PicseeCore
@testable import PicseeApplication

private final class HeldFolderMetadataReader: FolderMetadataReading, @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var names: [String] = []
    func read(_ url: URL) throws -> FolderImageMetadata {
        lock.lock(); names.append(url.lastPathComponent); lock.unlock()
        gate.wait()
        return .init(captureDate: Date(timeIntervalSince1970: url.lastPathComponent == "b.jpg" ? 1 : 2))
    }
    func release() { gate.signal() }
    var requested: [String] { lock.lock(); defer { lock.unlock() }; return names }
}

private final class ImmediateFolderMetadataReader: FolderMetadataReading, @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []
    func read(_ url: URL) throws -> FolderImageMetadata {
        lock.lock(); names.append(url.lastPathComponent); lock.unlock()
        return .init(captureDate: Date(timeIntervalSince1970: url.lastPathComponent == "b.jpg" ? 1 : 2))
    }
    var requested: [String] { lock.lock(); defer { lock.unlock() }; return names }
}

private struct FailingFolderMetadataReader: FolderMetadataReading {
    func read(_ url: URL) throws -> FolderImageMetadata { throw FolderScanTestError.expected }
}

private struct PartialFolderMetadataReader: FolderMetadataReading {
    func read(_ url: URL) throws -> FolderImageMetadata { .init(pixelWidth: 4) }
}

@MainActor private final class CancelledRememberHost: FolderScanHost {
    func openFolderImage(_ url: URL, rootID: AccessRootID) {}
    func rememberFolder(_ folder: URL, rootID: AccessRootID) async throws { throw CancellationError() }
    func showEmptyFolder() {}
}

@Test @MainActor func issue108MetadataSortPendingInvalidatesStaleRepliesAndKeepsBaseList() async throws {
    let fixture = FolderScanFixture(), reader = HeldFolderMetadataReader()
    let coordinator = FolderScanCoordinator(access: fixture.access, scanner: fixture.scanner, metadataReader: reader)
    let task = coordinator.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    try await fixture.scanner.deliver(["a.jpg", "b.jpg"])
    await fixture.scanner.finish(); try await task.value
    #expect(reader.requested.isEmpty)
    coordinator.setConditions(.init(sort: .captureDate))
    #expect(coordinator.isMetadataSortPending)
    #expect(coordinator.snapshot?.entries.count == 2)
    for _ in 0..<100 where reader.requested.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    #expect(reader.requested.count == 1)
    coordinator.setConditions(.init(sort: .name))
    reader.release()
    #expect(!coordinator.isMetadataSortPending)
    #expect(coordinator.snapshot?.entries.map(\.url.lastPathComponent) == ["a.jpg", "b.jpg"])
    #expect(coordinator.currentItemID == coordinator.snapshot?.entries.first?.itemID)
}

@Test @MainActor func issue108LateMetadataBatchExtendsPendingAndPreservesCurrentIdentity() async throws {
    let fixture = FolderScanFixture(), reader = ImmediateFolderMetadataReader()
    let coordinator = FolderScanCoordinator(access: fixture.access, scanner: fixture.scanner, metadataReader: reader)
    let task = coordinator.begin(folder: fixture.folder, rootID: fixture.id,
        input: fixture.folder.appendingPathComponent("a.jpg"))
    await fixture.scanner.waitForStart()
    coordinator.setConditions(.init(sort: .captureDate))
    try await fixture.scanner.deliver(["a.jpg"])
    #expect(coordinator.isMetadataSortPending)
    let originalID = coordinator.currentItemID
    try await fixture.scanner.deliver(["b.jpg"])
    await fixture.scanner.finish(); try await task.value
    for _ in 0..<100 where coordinator.isMetadataSortPending { try await Task.sleep(for: .milliseconds(5)) }
    #expect(!coordinator.isMetadataSortPending)
    #expect(coordinator.snapshot?.entries.map(\.url.lastPathComponent) == ["b.jpg", "a.jpg"])
    #expect(coordinator.currentItemID == originalID)
    #expect(Set(reader.requested) == ["a.jpg", "b.jpg"])
}

@Test @MainActor func issue108FolderReplacementRejectsHeldMetadataAndReleasesLeases() async throws {
    let fixture = FolderScanFixture(), reader = HeldFolderMetadataReader()
    let coordinator = FolderScanCoordinator(access: fixture.access, scanner: fixture.scanner, metadataReader: reader)
    let old = coordinator.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    try await fixture.scanner.deliver(["old.jpg"])
    await fixture.scanner.finish(); try await old.value
    coordinator.setConditions(.init(sort: .captureDate))
    for _ in 0..<100 where reader.requested.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    let replacement = fixture.root.appendingPathComponent("B")
    let new = coordinator.begin(folder: replacement, rootID: fixture.id)
    reader.release()
    await fixture.scanner.waitForStart(1)
    try await fixture.scanner.deliver(["new.jpg"], at: 1)
    await fixture.scanner.finish(1); try await new.value
    #expect(coordinator.snapshot?.version.folder == replacement)
    #expect(coordinator.snapshot?.entries.map(\.url.lastPathComponent) == ["new.jpg"])
    #expect(coordinator.conditions.sort == .captureDate)
    for _ in 0..<100 where reader.requested.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
    #expect(reader.requested.contains("new.jpg"))
    reader.release()
    for _ in 0..<100 {
        let balance = await fixture.access.balance
        if balance[0] == balance[1] { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    let balance = await fixture.access.balance
    #expect(balance[0] == balance[1])
}

@Test @MainActor func issue108MetadataReadFailureSettlesAsExplicitUnknown() async throws {
    let fixture = FolderScanFixture()
    let coordinator = FolderScanCoordinator(access: fixture.access, scanner: fixture.scanner,
        metadataReader: FailingFolderMetadataReader())
    let task = coordinator.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    try await fixture.scanner.deliver(["a.jpg"])
    await fixture.scanner.finish(); try await task.value
    let itemID = try #require(coordinator.snapshot?.entries.first?.itemID)
    coordinator.setConditions(.init(sort: .pixelDimensions))
    for _ in 0..<100 where coordinator.metadataSortState == .pending { try await Task.sleep(for: .milliseconds(5)) }
    #expect(coordinator.metadataSortState == .incomplete)
    #expect(coordinator.metadataUnknownItemIDs == [itemID])
    #expect(coordinator.snapshot?.entries.first?.itemID == itemID)
}

@Test @MainActor func issue108MissingChosenFieldRemainsIncomplete() async throws {
    let fixture = FolderScanFixture()
    let coordinator = FolderScanCoordinator(access: fixture.access, scanner: fixture.scanner,
        metadataReader: PartialFolderMetadataReader())
    let task = coordinator.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    try await fixture.scanner.deliver(["a.jpg"])
    await fixture.scanner.finish(); try await task.value
    for sort in [FolderSortKey.captureDate, .pixelDimensions] {
        coordinator.setConditions(.init(sort: sort))
        for _ in 0..<100 where coordinator.metadataSortState == .pending { try await Task.sleep(for: .milliseconds(5)) }
        #expect(coordinator.metadataSortState == .incomplete)
    }
}

@Test @MainActor func issue108PartialScanFailureKeepsReadMetadata() async throws {
    let fixture = FolderScanFixture(), reader = ImmediateFolderMetadataReader()
    let coordinator = FolderScanCoordinator(access: fixture.access, scanner: fixture.scanner, metadataReader: reader)
    let task = coordinator.begin(folder: fixture.folder, rootID: fixture.id, input: fixture.folder.appendingPathComponent("a.jpg"))
    await fixture.scanner.waitForStart()
    coordinator.setConditions(.init(sort: .captureDate))
    try await fixture.scanner.deliver(["a.jpg", "b.jpg"])
    for _ in 0..<100 where reader.requested.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
    for _ in 0..<100 where coordinator.metadataProjectionCount == 0 { try await Task.sleep(for: .milliseconds(5)) }
    await fixture.scanner.finish(failing: true)
    await #expect(throws: FolderScanTestError.expected) { try await task.value }
    #expect(coordinator.snapshot?.entries.map(\.url.lastPathComponent) == ["b.jpg", "a.jpg"])
}

@Test @MainActor func issue108StaleReplyCannotPopulateNewSortAfterDrain() async throws {
    let fixture = FolderScanFixture(), reader = HeldFolderMetadataReader()
    let coordinator = FolderScanCoordinator(access: fixture.access, scanner: fixture.scanner, metadataReader: reader)
    let task = coordinator.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    try await fixture.scanner.deliver(["a.jpg"])
    await fixture.scanner.finish(); try await task.value
    coordinator.setConditions(.init(sort: .captureDate))
    for _ in 0..<100 where reader.requested.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    coordinator.setConditions(.init(sort: .name))
    coordinator.setConditions(.init(sort: .captureDate))
    reader.release()
    for _ in 0..<100 where reader.requested.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
    #expect(coordinator.metadataSortState == .pending)
    reader.release()
    for _ in 0..<100 where coordinator.metadataSortState == .pending { try await Task.sleep(for: .milliseconds(5)) }
    #expect(coordinator.metadataSortState == .complete)
}

@Test @MainActor func issue108CancelledScanDropsSourceAndMetadataWork() async throws {
    let fixture = FolderScanFixture(), reader = HeldFolderMetadataReader(), host = CancelledRememberHost()
    let coordinator = FolderScanCoordinator(access: fixture.access, scanner: fixture.scanner, metadataReader: reader)
    coordinator.host = host
    let task = coordinator.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    coordinator.setConditions(.init(sort: .captureDate))
    try await fixture.scanner.deliver(["a.jpg"])
    for _ in 0..<100 where reader.requested.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    await fixture.scanner.finish(); try await task.value
    #expect(coordinator.snapshot == nil && coordinator.sourceSnapshot == nil)
    #expect(coordinator.metadataSortState == .idle)
    reader.release()
    for _ in 0..<100 {
        let balance = await fixture.access.balance
        if balance[0] == balance[1] { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(coordinator.snapshot == nil && coordinator.sourceSnapshot == nil)
    let balance = await fixture.access.balance
    #expect(balance[0] == balance[1])
}

@Test @MainActor func issue108RemovedEntriesDoNotStrandRemainingMetadataQueue() async throws {
    let fixture = FolderScanFixture(), reader = HeldFolderMetadataReader()
    let coordinator = FolderScanCoordinator(access: fixture.access, scanner: fixture.scanner, metadataReader: reader)
    let task = coordinator.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    try await fixture.scanner.deliver(["a.jpg", "b.jpg", "c.jpg"])
    await fixture.scanner.finish(); try await task.value
    coordinator.setConditions(.init(sort: .captureDate))
    for _ in 0..<100 where reader.requested.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    let source = try #require(coordinator.sourceSnapshot)
    coordinator.replaceSourceSnapshot(FolderSnapshot(version: source.version,
        entries: source.entries.filter { $0.url.lastPathComponent == "c.jpg" }, isComplete: true))
    reader.release()
    for _ in 0..<100 where reader.requested.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
    #expect(reader.requested == ["a.jpg", "c.jpg"])
    reader.release()
    for _ in 0..<100 where coordinator.metadataSortState == .pending { try await Task.sleep(for: .milliseconds(5)) }
    #expect(coordinator.metadataSortState == .complete)
    #expect(coordinator.snapshot?.entries.map(\.url.lastPathComponent) == ["c.jpg"])
}

@Test @MainActor func issue108RapidSortChangesKeepAtMostOneReadInFlight() async throws {
    let fixture = FolderScanFixture(), reader = HeldFolderMetadataReader()
    let coordinator = FolderScanCoordinator(access: fixture.access, scanner: fixture.scanner, metadataReader: reader)
    let task = coordinator.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    try await fixture.scanner.deliver(["a.jpg"])
    await fixture.scanner.finish(); try await task.value
    coordinator.setConditions(.init(sort: .captureDate))
    for _ in 0..<100 where reader.requested.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    coordinator.setConditions(.init(sort: .pixelDimensions))
    coordinator.setConditions(.init(sort: .captureDate))
    try await Task.sleep(for: .milliseconds(20))
    #expect(reader.requested.count == 1)
    reader.release()
    for _ in 0..<100 where reader.requested.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
    #expect(reader.requested.count == 2)
    reader.release()
    for _ in 0..<100 where coordinator.isMetadataSortPending { try await Task.sleep(for: .milliseconds(5)) }
    #expect(!coordinator.isMetadataSortPending)
}

@Test @MainActor func issue108ManyHeadersPublishBoundedSortBatches() async throws {
    let fixture = FolderScanFixture(), reader = ImmediateFolderMetadataReader()
    let coordinator = FolderScanCoordinator(access: fixture.access, scanner: fixture.scanner, metadataReader: reader)
    let task = coordinator.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    let names = (0..<1024).map { "img\($0).jpg" }
    try await fixture.scanner.deliver(names)
    await fixture.scanner.finish(); try await task.value
    coordinator.setConditions(.init(sort: .captureDate))
    for _ in 0..<2000 where coordinator.isMetadataSortPending { try await Task.sleep(for: .milliseconds(5)) }
    #expect(!coordinator.isMetadataSortPending)
    #expect(reader.requested.count == 1024)
    #expect(coordinator.snapshot?.entries.count == 1024)
    #expect(coordinator.metadataProjectionCount <= 17)
}

@Test(.timeLimit(.minutes(1))) @MainActor
func issue108HeldMetadataHeadersLeaveCooperativeExecutorResponsive() async throws {
    let reader = HeldFolderMetadataReader()
    let workerCount = ProcessInfo.processInfo.activeProcessorCount
    let count = max(4, min(workerCount * 2, 32))
    var coordinators: [FolderScanCoordinator] = []
    for _ in 0..<count {
        let fixture = FolderScanFixture()
        let coordinator = FolderScanCoordinator(access: fixture.access, scanner: fixture.scanner, metadataReader: reader)
        let scan = coordinator.begin(folder: fixture.folder, rootID: fixture.id)
        await fixture.scanner.waitForStart()
        try await fixture.scanner.deliver(["a.jpg"])
        await fixture.scanner.finish()
        try await scan.value
        coordinators.append(coordinator)
    }
    for coordinator in coordinators { coordinator.setConditions(.init(sort: .captureDate)) }
    // The probe itself must not need a cooperative worker to release blocked reads.
    let (started, elapsed) = await withCheckedContinuation { continuation in
        Thread.detachNewThread {
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while reader.requested.count < workerCount && ContinuousClock.now < deadline {
                Thread.sleep(forTimeInterval: 0.005)
            }
            let started = reader.requested.count
            let start = ContinuousClock.now
            Task.detached { continuation.resume(returning: (started, ContinuousClock.now - start)) }
            Thread.sleep(forTimeInterval: 0.8)
            for _ in 0..<count { reader.release() }
        }
    }
    #expect(started >= workerCount)
    #expect(elapsed < .milliseconds(400))
    try await Task.sleep(for: .milliseconds(900))
    for coordinator in coordinators { coordinator.end() }
}
