import Foundation
import Testing
import PicseeCore
@testable import PicseeInfrastructure

final class CountingScope: SecurityScope, @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0
    var succeeds = true
    func start(_ url: URL) -> Bool { lock.withLock { starts += 1; return succeeds } }
    func stop(_ url: URL) { lock.withLock { stops += 1 } }
    var counts: [Int] { lock.withLock { [starts, stops] } }
}

@Test func accessLeasesBalanceAcrossWindowsFailuresAndCancellation() async throws {
    let scope = CountingScope()
    let access = FileAccess(scope: scope)
    let folder = URL(fileURLWithPath: "/tmp")
    let root = try await access.grant(folder: folder)
    let request = AccessRequest.root(root, file: folder.appendingPathComponent("a.jpg"))
    let first = try await access.acquire(request)
    let second = try await access.acquire(request)
    #expect(scope.counts == [1, 0])
    await access.release(first); await access.release(first)
    #expect(scope.counts == [1, 0])
    await access.release(second)
    #expect(scope.counts == [1, 1])
    await #expect(throws: FileAccessError.outsideRoot) {
        try await access.acquire(.root(root, file: URL(fileURLWithPath: "/elsewhere/a.jpg")))
    }
    let unknown = AccessRootID()
    await #expect(throws: FileAccessError.needsReconnection(unknown)) {
        try await access.acquire(.root(unknown, file: folder))
    }
}

@Test func accessFileGrantFailedStartNeverStopsAndScopesOnlyOneFile() async throws {
    let scope = CountingScope(); scope.succeeds = false
    let access = FileAccess(scope: scope)
    let file = URL(fileURLWithPath: "/tmp/a.jpg")
    await #expect(throws: FileAccessError.startFailed) { try await access.acquire(.fileGrant(file)) }
    #expect(scope.counts == [1, 0])
    let root = try await access.grant(folder: file.deletingLastPathComponent())
    await #expect(throws: FileAccessError.startFailed) { try await access.acquire(.root(root, file: file)) }
    #expect(scope.counts == [2, 0])
    scope.succeeds = true
    let lease = try await access.acquire(.fileGrant(file))
    #expect(lease.rootID == nil)
    #expect(lease.url == file)
    await access.release(lease)
    enum Failure: Error { case expected }
    await #expect(throws: Failure.expected) {
        try await access.withLease(.fileGrant(file)) { _ in throw Failure.expected }
    }
    let cancelled = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await access.withLease(.fileGrant(file)) { _ in 1 }
    }
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    let value = try await access.withLease(.fileGrant(file)) { _ in 42 }
    #expect(value == 42)
    #expect(scope.counts == [6, 4])
}
