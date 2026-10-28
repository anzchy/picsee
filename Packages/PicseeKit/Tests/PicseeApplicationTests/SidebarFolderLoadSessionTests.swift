import Foundation
import Testing
import PicseeCore
@testable import PicseeApplication

private actor LoadLease: AccessLeasing {
    let root: URL
    init(root: URL) { self.root = root }
    func acquire(_ request: AccessRequest) -> AccessLease { AccessLease(url: root, rootID: AccessRootID()) }
    func release(_ lease: AccessLease) {}
}

private actor BlockedCounter: SidebarFolderEnumerating {
    let child: URL
    private var permitted = false
    private var waiter: CheckedContinuation<Void, Never>?
    init(child: URL) { self.child = child }
    func children(in folder: URL, root: URL) -> [URL] { [child] }
    func imageCount(in folder: URL, root: URL) async -> Int {
        if !permitted { await withCheckedContinuation { waiter = $0 } }
        return 1234
    }
    func release() { permitted = true; waiter?.resume(); waiter = nil }
}

@Test @MainActor func sidebarSlowCounterDoesNotDelayRows() async throws {
    let root = URL(fileURLWithPath: "/tmp/picsee-sidebar-root")
    let child = root.appendingPathComponent("Trip")
    let counter = BlockedCounter(child: child)
    let browser = SidebarFolderBrowser(access: LoadLease(root: root), enumerator: counter)
    let session = SidebarFolderLoadSession(browser: browser)
    var rowURLs: [URL] = []
    var counts: [URL: Int] = [:]
    var rowsSignal: AsyncStream<Void>.Continuation!
    let rows = AsyncStream<Void> { rowsSignal = $0 }
    var countSignal: AsyncStream<Void>.Continuation!
    let countUpdates = AsyncStream<Void> { countSignal = $0 }
    session.start(folder: root, rootID: AccessRootID(), onRows: { urls, _ in
        rowURLs = urls
        rowsSignal.yield()
    }, onCount: { url, count in
        counts[url] = count
        countSignal.yield()
    })
    var rowIterator = rows.makeAsyncIterator()
    _ = await rowIterator.next()
    try #require(rowURLs == [child])
    #expect(counts.isEmpty)
    await counter.release()
    var countIterator = countUpdates.makeAsyncIterator()
    _ = await countIterator.next()
    #expect(counts[child] == 1234)
    session.cancel()
    #expect(counts[child] == 1234)
}
