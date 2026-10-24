import Foundation
import Testing
import PicseeCore
@testable import PicseeApplication

@Test @MainActor func recursiveToggleReplacesGenerationAndDiscardsOldBatch() async throws {
    let fixture = FolderScanFixture()
    let old = fixture.coordinator.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    #expect(await fixture.scanner.options(at: 0).recursive == false)
    let replacement = try #require(fixture.coordinator.setRecursiveEnabled(true))
    await fixture.scanner.waitForStart(1)
    #expect(fixture.coordinator.recursiveEnabled)
    #expect(await fixture.scanner.options(at: 1).recursive)
    try await fixture.scanner.deliver(["old.png"], at: 0)
    #expect(fixture.coordinator.snapshot?.entries.isEmpty == true)
    try await fixture.scanner.deliver(["sub/new.png"], at: 1)
    #expect(fixture.coordinator.snapshot?.entries.map(\.relativePath) == ["A/sub/new.png"])
    await fixture.scanner.finish(0)
    await fixture.scanner.finish(1)
    try await old.value
    try await replacement.value
    #expect(await fixture.access.balance == [2, 2])
}

private struct PartialFailureScanner: FolderScanning {
    func scan(in folder: URL, root: ItemIdentityRoot, options: FolderScanOptions,
        emit: @Sendable ([FolderEntry]) async throws -> Void) async throws {
        try await emit([FolderEntry(url: folder.appendingPathComponent("one.png"), root: root)])
        throw FolderScanLimitError.entryLimit(limit: 1, admittedImages: 1)
    }
}

@Test @MainActor func folderScanFailureKeepsPartialCountAndRecoverableState() async {
    let fixture = FolderScanFixture()
    let coordinator = FolderScanCoordinator(access: fixture.access, scanner: PartialFailureScanner())
    let session = ViewerSession(host: nil)
    session.folderScan = coordinator
    let task = coordinator.begin(folder: fixture.folder, rootID: fixture.id)
    _ = try? await task.value
    #expect(coordinator.sourceSnapshot?.entries.count == 1)
    #expect(coordinator.sourceSnapshot?.isComplete == false)
    #expect(session.imageStatus == .folderScanFailed("Scan limit reached", 1))
    #expect(await fixture.access.balance == [1, 1])
}

@MainActor private final class RecursiveSelectionHost: FolderScanHost {
    var opened: [URL] = []
    var cleared = 0
    weak var session: ViewerSession?
    func openFolderImage(_ url: URL, rootID: AccessRootID) { opened.append(url) }
    func rememberFolder(_ folder: URL, rootID: AccessRootID) async throws { }
    func showEmptyFolder() { }
    func clearFolderImageForNoMatches() { cleared += 1; session?.closeImage() }
}

@Test @MainActor func p204FixEmptyFlatToggleClearsExcludedNestedImage() async throws {
    let fixture = FolderScanFixture(), host = RecursiveSelectionHost()
    let session = ViewerSession(host: nil)
    host.session = session
    session.folderScan = fixture.coordinator
    fixture.coordinator.host = host
    _ = fixture.coordinator.setRecursiveEnabled(true)
    let nested = fixture.folder.appendingPathComponent("sub/nested.png")
    let first = fixture.coordinator.begin(folder: fixture.folder, rootID: fixture.id, input: nested)
    await fixture.scanner.waitForStart()
    try await fixture.scanner.deliver(["sub/nested.png"])
    await fixture.scanner.finish(); try await first.value
    session.openImage(nested, maximumPixelSize: 1) { throw CancellationError() }
    #expect(session.imageLoader.fileURL == nested)
    let second = try #require(fixture.coordinator.setRecursiveEnabled(false))
    await fixture.scanner.waitForStart(1)
    await fixture.scanner.finish(1); try await second.value
    #expect(fixture.coordinator.snapshot?.entries.isEmpty == true)
    #expect(fixture.coordinator.currentURL == nil)
    #expect(host.cleared == 1)
    #expect(session.imageLoader.fileURL == nil)
    #expect(session.imageStatus == .empty)
    #expect(fixture.coordinator.canMove(.next, currentURL: nested) == false)
    #expect(fixture.coordinator.canMove(.previous, currentURL: nested) == false)
}

@Test @MainActor func recursiveToggleOffRemovesNestedSelectionAndKeepsConditions() async throws {
    let fixture = FolderScanFixture(), host = RecursiveSelectionHost()
    fixture.coordinator.host = host
    _ = fixture.coordinator.setRecursiveEnabled(true)
    let nested = fixture.folder.appendingPathComponent("sub/nested.png")
    let first = fixture.coordinator.begin(folder: fixture.folder, rootID: fixture.id, input: nested)
    await fixture.scanner.waitForStart()
    try await fixture.scanner.deliver(["top.jpg", "sub/nested.png"])
    await fixture.scanner.finish(); try await first.value
    #expect(fixture.coordinator.currentURL == nested)
    fixture.coordinator.setConditions(.init(sort: .name, direction: .descending))
    let second = try #require(fixture.coordinator.setRecursiveEnabled(false))
    #expect(fixture.coordinator.currentURL == nil)
    await fixture.scanner.waitForStart(1)
    #expect(await fixture.scanner.options(at: 1).recursive == false)
    try await fixture.scanner.deliver(["top.jpg"], at: 1)
    await fixture.scanner.finish(1); try await second.value
    #expect(fixture.coordinator.snapshot?.navigationEntries.map(\.url.lastPathComponent) == ["top.jpg"])
    #expect(fixture.coordinator.currentURL?.lastPathComponent == "top.jpg")
    #expect(host.opened.map(\.lastPathComponent) == ["top.jpg"])
    #expect(fixture.coordinator.conditions.direction == .descending)
    #expect(await fixture.access.balance == [2, 2])
}

@Test @MainActor func recursiveSessionFacadeTogglesAndRetryStartsFreshLease() async throws {
    let fixture = FolderScanFixture(), session = ViewerSession(host: nil)
    session.folderScan = fixture.coordinator
    #expect(!session.folderRecursiveEnabled)
    let first = fixture.coordinator.begin(folder: fixture.folder, rootID: fixture.id)
    await fixture.scanner.waitForStart()
    session.setFolderRecursiveEnabled(true)
    await fixture.scanner.waitForStart(1)
    #expect(session.folderRecursiveEnabled)
    await fixture.scanner.finish(0)
    await fixture.scanner.finish(1, failing: true)
    try await first.value
    for _ in 0..<1_000 where fixture.coordinator.failure == nil { await Task.yield() }
    #expect(fixture.coordinator.failure != nil)
    session.retryFolderScan()
    await fixture.scanner.waitForStart(2)
    #expect(await fixture.scanner.options(at: 2).recursive)
    await fixture.scanner.finish(2)
    for _ in 0..<1_000 where fixture.coordinator.sourceSnapshot?.isComplete != true { await Task.yield() }
    #expect(fixture.coordinator.sourceSnapshot?.isComplete == true)
    #expect(await fixture.access.balance == [3, 3])
}

private struct PermissionFailureScanner: FolderScanning {
    let error: any Error
    func scan(in folder: URL, root: ItemIdentityRoot, options: FolderScanOptions,
        emit: @Sendable ([FolderEntry]) async throws -> Void) async throws { throw error }
}

@Test @MainActor func folderScanPermissionFailureIsRecoverableAndNoCountInvented() async {
    let fixture = FolderScanFixture()
    let coordinator = FolderScanCoordinator(access: fixture.access,
        scanner: PermissionFailureScanner(error: POSIXError(.EPERM)))
    let session = ViewerSession(host: nil); session.folderScan = coordinator
    _ = try? await coordinator.begin(folder: fixture.folder, rootID: fixture.id).value
    #expect(session.imageStatus == .folderScanFailed("Folder access denied", 0))
    #expect(coordinator.completedImageCount == nil)
    #expect(coordinator.sourceSnapshot?.isComplete == false)
    #expect(await fixture.access.balance == [1, 1])
}

private actor RootFailureLease: AccessLeasing {
    var requests = 0
    func acquire(_ request: AccessRequest) throws -> AccessLease {
        requests += 1
        throw FileAccessError.invalidFolder
    }
    func release(_ lease: AccessLease) { }
}

@Test @MainActor func folderAccessFailureBeforeSnapshotShowsZeroAndCanRetry() async {
    let fixture = FolderScanFixture(), access = RootFailureLease(), session = ViewerSession(host: nil)
    #expect(session.folderRecursiveEnabled == false)
    let coordinator = FolderScanCoordinator(access: access, scanner: fixture.scanner)
    session.folderScan = coordinator
    #expect(session.folderRecursiveEnabled == false)
    _ = try? await coordinator.begin(folder: fixture.folder, rootID: fixture.id).value
    #expect(session.imageStatus == .folderScanFailed("Folder access denied", 0))
    #expect(coordinator.sourceSnapshot == nil)
    _ = try? await coordinator.retry()?.value
    #expect(await access.requests == 2)
}
