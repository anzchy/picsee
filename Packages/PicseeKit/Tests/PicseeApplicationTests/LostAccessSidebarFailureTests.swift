import Foundation
import Testing
import PicseeCore
@testable import PicseeApplication

private actor T229SidebarLeases: AccessLeasing {
    let root: URL
    private var acquired = 0, released = 0
    init(root: URL) { self.root = root }
    func acquire(_ request: AccessRequest) -> AccessLease {
        acquired += 1
        return AccessLease(url: root, rootID: AccessRootID())
    }
    func release(_ lease: AccessLease) { released += 1 }
    var balanced: Bool { acquired == released }
}
private enum T229SidebarError: Error { case denied }
private actor T229SidebarFailures: SidebarFolderEnumerating {
    enum Mode: Sendable { case listing, count, held }
    let mode: Mode
    private var pending: CheckedContinuation<[URL], any Error>?
    private(set) var started = false
    init(_ mode: Mode) { self.mode = mode }
    func children(in folder: URL, root: URL) async throws -> [URL] {
        switch mode {
        case .listing: throw T229SidebarError.denied
        case .count: return []
        case .held:
            guard folder.lastPathComponent == "Old" else { return [] }
            started = true
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
    }
    func imageCount(in folder: URL, root: URL) throws -> Int {
        if case .count = mode { throw T229SidebarError.denied }
        return 0
    }
    func releaseFailure() { pending?.resume(throwing: T229SidebarError.denied); pending = nil }
}

@MainActor @Test func t229SidebarReaderFailuresReportCurrentWorkAndIgnoreCancelledOldWork() async throws {
    let root = URL(fileURLWithPath: "/tmp/T229-sidebar")
    for mode in [T229SidebarFailures.Mode.listing, .count] {
        let access = T229SidebarLeases(root: root)
        let session = SidebarFolderLoadSession(browser: SidebarFolderBrowser(access: access,
            enumerator: T229SidebarFailures(mode)))
        var failures: [URL] = []
        session.start(folder: root, rootID: AccessRootID(), onRows: { _, _ in }, onCount: { _, _ in },
            onFailure: { failures.append($0) })
        for _ in 0..<100 where failures.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(failures == [root])
        #expect(await access.balanced)
        session.cancel()
    }

    let access = T229SidebarLeases(root: root), enumerator = T229SidebarFailures(.held)
    let session = SidebarFolderLoadSession(browser: SidebarFolderBrowser(access: access, enumerator: enumerator))
    var failures: [URL] = [], newCounts: [URL] = []
    let old = root.appendingPathComponent("Old"), new = root.appendingPathComponent("New")
    session.start(folder: old, rootID: AccessRootID(), onRows: { _, _ in }, onCount: { _, _ in },
        onFailure: { failures.append($0) })
    for _ in 0..<100 where !(await enumerator.started) { try await Task.sleep(for: .milliseconds(5)) }
    #expect(await enumerator.started)
    session.start(folder: new, rootID: AccessRootID(), onRows: { _, _ in },
        onCount: { url, _ in newCounts.append(url) }, onFailure: { failures.append($0) })
    for _ in 0..<100 where newCounts.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    #expect(newCounts.contains(new))
    await enumerator.releaseFailure()
    for _ in 0..<100 where !(await access.balanced) { try await Task.sleep(for: .milliseconds(5)) }
    #expect(await access.balanced)
    try await Task.sleep(for: .milliseconds(20))
    #expect(failures.isEmpty)
    session.cancel()
}

private actor T229ParentFailureLeases: AccessLeasing {
    let root: URL
    private var acquisitions = 0, releases = 0
    init(root: URL) { self.root = root }
    func acquire(_ request: AccessRequest) throws -> AccessLease {
        acquisitions += 1
        if acquisitions == 2 { throw T229SidebarError.denied }
        return AccessLease(url: root, rootID: AccessRootID())
    }
    func release(_ lease: AccessLease) { releases += 1 }
    var balanced: Bool { acquisitions - 1 == releases }
}

@MainActor @Test func t229SidebarParentFailureReportsFailureAndKeepsKnownRows() async throws {
    let root = URL(fileURLWithPath: "/tmp/T229-parent")
    let access = T229ParentFailureLeases(root: root)
    let session = SidebarFolderLoadSession(browser: SidebarFolderBrowser(access: access,
        enumerator: T229SidebarFailures(.count)))
    var rows: [[URL]] = [], parents: [URL?] = [], failures: [URL] = [], counts: [Int] = []
    session.start(folder: root, rootID: AccessRootID(), onRows: { children, parent in
        rows.append(children); parents.append(parent)
    }, onCount: { _, count in counts.append(count) }, onFailure: { failures.append($0) })
    // Utility work shares MainActor with the entire native test suite. This bounds
    // missing completion, not a product latency requirement.
    let limit = ContinuousClock.now + .seconds(15)
    while failures.count < 2, ContinuousClock.now < limit { try await Task.sleep(for: .milliseconds(5)) }
    #expect(rows == [[]])
    #expect(parents.count == 1 && parents[0] == nil)
    #expect(failures == [root, root])
    #expect(counts.isEmpty)
    #expect(await access.balanced)
    session.cancel()
}
