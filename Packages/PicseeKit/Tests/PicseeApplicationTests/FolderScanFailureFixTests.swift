import Foundation
import Testing
import PicseeCore
@testable import PicseeApplication

@MainActor final class FolderFixTrace: FolderScanTracing {
    var events: [String] = []
    func begin(generation: UInt64, folderURL: URL) { events.append("begin-\(generation)") }
    func firstBatch(count: Int, generation: UInt64) { events.append("first-\(count)") }
    func complete(count: Int, generation: UInt64) { events.append("complete-\(count)") }
    func end(outcome: FolderScanOutcome, generation: UInt64) { events.append("\(outcome.rawValue)-\(generation)") }
}

@Test(arguments: [0, 1, 3])
@MainActor func folderFixFailureFinalizesEndpoints(count: Int) async throws {
    let fixture = FolderScanFixture(), host = FolderNavigationHost(), trace = FolderFixTrace()
    let coordinator = FolderScanCoordinator(access: fixture.access, scanner: fixture.scanner, trace: trace)
    let session = ViewerSession(host: host), imageHost = LoadHost(), pipeline = LoadPipeline(), leases = LoadLeases()
    session.imageLoader.host = imageHost; session.folderScan = coordinator; coordinator.host = host
    let file = fixture.folder.appendingPathComponent("img2.png")
    session.openImage(file, maximumPixelSize: 512) {
        try await AccessImageSource.open(.fileGrant(file), access: leases, pipeline: pipeline)
    }
    await session.imageLoader.loadTask?.value
    let presented = session.imageLoader.presented?.key
    #expect(session.imageStatus == .showing)
    let task = coordinator.begin(folder: fixture.folder, rootID: fixture.id, input: file,
        pending: count == 1 ? .next : nil)
    await fixture.scanner.waitForStart()
    if count > 0 { try await fixture.scanner.deliver(count == 1 ? ["img2.png"] : ["img1.png", "img2.png", "img10.png"]) }
    await fixture.scanner.finish(failing: true)
    await #expect(throws: FolderScanTestError.expected) { try await task.value }
    #expect(coordinator.failure is FolderScanTestError)
    #expect(coordinator.snapshot?.isComplete == true)
    #expect(coordinator.pendingDirection == nil && !coordinator.isReadingFolder)
    #expect(coordinator.canMove(.next) == (count == 0 ? nil : count == 3))
    #expect(coordinator.canMove(.previous) == (count == 0 ? nil : count == 3))
    #expect(coordinator.snapshot?.entries.count == count)
    #expect(session.imageStatus == .showing && session.imageLoader.presented?.key == presented)
    #expect(session.imageLoader.fileURL == file && host.opens.isEmpty)
    #expect(trace.events == (count == 0 ? ["begin-1", "failed-1"] : ["begin-1", "first-\(count)", "failed-1"]))
    #expect(await fixture.access.balance == [1, 1])
    session.closeImage()
}
