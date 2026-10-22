import Foundation
import Testing
import PicseeCore
@testable import PicseeInfrastructure

final class FakeBookmarks: BookmarkCoding, @unchecked Sendable {
    private let lock = NSLock()
    var stale = false
    var fails = false
    var creationFails = false
    private var creations = 0
    var count: Int { lock.withLock { creations } }
    func create(for url: URL) throws -> Data {
        try lock.withLock {
            if creationFails { throw FileAccessError.invalidFolder }
            creations += 1
            return Data(url.path.utf8)
        }
    }
    func resolve(_ data: Data) throws -> ResolvedBookmark {
        try lock.withLock {
            if fails { throw FileAccessError.corruptStore }
            return ResolvedBookmark(url: URL(fileURLWithPath: String(decoding: data, as: UTF8.self)), stale: stale)
        }
    }
}

@Test func accessBookmarksSurviveRelaunchRefreshStaleAndReportFailures() async throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: base) }
    let folder = base.appendingPathComponent("photos")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("a.jpg")
    let store = BookmarkStore(url: base.appendingPathComponent("support/roots.json"))
    let codec = FakeBookmarks(); let scope = CountingScope()
    let first = try FileAccess(scope: scope, bookmarks: codec, store: store, buildSHA: "A")
    let id = try await first.grant(folder: folder)
    #expect(try store.load().count == 1)
    let saved = try #require(store.load().first)
    #expect(saved.id == id && saved.displayName == "photos" && saved.creatingBuildSHA == "A")
    #expect(saved.createdAt.timeIntervalSinceNow <= 0)
    #expect(await first.rootCovering(file) == id)
    #expect(await first.rootCovering(base) == nil)
    let second = try FileAccess(scope: scope, bookmarks: codec, store: store, buildSHA: "B")
    #expect(await second.launchOutcomes()[id] == "resolved")
    let lease = try await second.acquire(.root(id, file: file))
    await second.release(lease)
    codec.stale = true
    let stale = try FileAccess(scope: scope, bookmarks: codec, store: store, buildSHA: "C")
    #expect(await stale.launchOutcomes()[id] == "stale")
    #expect(codec.count == 2)
    #expect(try store.load().first?.creatingBuildSHA == "A")
    #expect(await stale.records().count == 1)
    codec.fails = true
    let failed = try FileAccess(scope: scope, bookmarks: codec, store: store, buildSHA: "D")
    #expect(await failed.launchOutcomes()[id] == "failed")
    await #expect(throws: FileAccessError.needsReconnection(id)) { try await failed.acquire(.root(id, file: file)) }
    #expect(await failed.rootCovering(file) == nil)
    #expect(try store.load().count == 1)
    codec.fails = false; codec.creationFails = true
    let cannotRefresh = try FileAccess(scope: scope, bookmarks: codec, store: store, buildSHA: "E")
    #expect(await cannotRefresh.launchOutcomes()[id] == "failed")
    #expect(scope.counts[0] == scope.counts[1])
}

@Test func accessFileGrantNeverPersistsAndCorruptStoreIsReported() async throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: base) }
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    let store = BookmarkStore(url: base.appendingPathComponent("roots.json"))
    let scope = CountingScope(); let codec = FakeBookmarks()
    let first = try FileAccess(scope: scope, bookmarks: codec, store: store, buildSHA: "A")
    let file = base.appendingPathComponent("one.jpg")
    let lease = try await first.acquire(.fileGrant(file)); await first.release(lease)
    let second = try FileAccess(scope: scope, bookmarks: codec, store: store, buildSHA: "B")
    #expect(await second.rootCovering(file) == nil)
    #expect(try store.load().isEmpty)
    #expect(codec.count == 0)
    try Data("broken JSON".utf8).write(to: store.url)
    #expect(throws: FileAccessError.corruptStore) {
        try FileAccess(scope: scope, bookmarks: codec, store: store, buildSHA: "C")
    }
    #expect(try Data(contentsOf: store.url) == Data("broken JSON".utf8))
}

@Test func accessAcquireRefreshesNewlyStaleBookmarkAndRejectsLostRoot() async throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: base) }
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    let store = BookmarkStore(url: base.appendingPathComponent("roots.json"))
    let scope = CountingScope(); let codec = FakeBookmarks()
    let access = try FileAccess(scope: scope, bookmarks: codec, store: store, buildSHA: "A")
    let id = try await access.grant(folder: base)
    codec.stale = true
    let lease = try await access.acquire(.root(id, file: base.appendingPathComponent("a.jpg")))
    #expect(codec.count == 2)
    let second = try await access.acquire(.root(id, file: base.appendingPathComponent("b.jpg")))
    #expect(codec.count == 2)
    await access.release(lease); await access.release(second)
    codec.creationFails = true
    await #expect(throws: FileAccessError.needsReconnection(id)) {
        try await access.acquire(.root(id, file: base))
    }
    #expect(await access.rootCovering(base) == nil)
    #expect(scope.counts[0] == scope.counts[1])
    let restored = try FileAccess(scope: scope, bookmarks: FakeBookmarks(), store: store, buildSHA: "B")
    codec.fails = true
    let otherID = try await restored.grant(folder: base)
    #expect(otherID != id)
}
