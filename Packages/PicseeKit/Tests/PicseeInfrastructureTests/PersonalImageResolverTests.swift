import Foundation
import Testing
import PicseeCore
@testable import PicseeInfrastructure

/// The real system scope and bookmarks, with start denial standing in for a revoked grant.
private final class SwitchableSystemScope: SecurityScope, @unchecked Sendable {
    private let lock = NSLock()
    private let system = SystemSecurityScope()
    private var denied = false
    private var balance = [0, 0]
    var deny: Bool {
        get { lock.withLock { denied } }
        set { lock.withLock { denied = newValue } }
    }
    var counts: [Int] { lock.withLock { balance } }
    func start(_ url: URL) -> Bool {
        if deny { return false }
        let started = system.start(url)
        if started { lock.withLock { balance[0] += 1 } }
        return started
    }
    func stop(_ url: URL) { lock.withLock { balance[1] += 1 }; system.stop(url) }
    func isReadable(_ url: URL) -> Bool { system.isReadable(url) }
}

private struct PersonalResolverFixture {
    let base: URL
    let folder: URL
    let scope = SwitchableSystemScope()
    let access: FileAccess
    let rootID: AccessRootID
    var root: ItemIdentityRoot { ItemIdentityRoot(id: rootID, url: folder) }
    var resolver: PersonalImageResolver { PersonalImageResolver(access: access) }
    init(name: String = "root") async throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        folder = base.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        access = try FileAccess(scope: scope, bookmarks: SystemSecurityScope(),
            store: BookmarkStore(url: base.appendingPathComponent("support/roots.json")), buildSHA: "personal")
        rootID = try await access.grant(folder: folder)
    }
    /// Writes the file and records it as the store would: path plus file number, read under a root lease.
    func remember(_ name: String, bytes: Data = Data([1, 2, 3])) async throws -> PersonalImageRef {
        let file = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: file)
        let number = try await access.withLease(.root(rootID, file: file)) { _ in PersonalImageResolver.fingerprint(of: file) }
        return try #require(PersonalImageRef(fileURL: file, root: root, fileNumber: try #require(number)))
    }
}

private func personalCanonicalPath(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }

@Test func personalImageResolverPresentOnRealGrant() async throws {
    let fixture = try await PersonalResolverFixture()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let bytes = Data("present".utf8)
    let ref = try await fixture.remember("sub/a.jpg", bytes: bytes)
    guard case .present(let url) = await fixture.resolver.resolve(ref) else {
        Issue.record("expected present"); return
    }
    #expect(personalCanonicalPath(url) == personalCanonicalPath(fixture.folder.appendingPathComponent("sub/a.jpg")))
    #expect(try Data(contentsOf: url) == bytes)
    #expect(fixture.scope.counts[0] == fixture.scope.counts[1])
}

@Test func personalImageResolverMissingCases() async throws {
    let fm = FileManager.default
    let fixture = try await PersonalResolverFixture()
    defer { try? fm.removeItem(at: fixture.base) }
    let resolver = fixture.resolver
    let folder = fixture.folder, outside = fixture.base.appendingPathComponent("outside")
    try fm.createDirectory(at: outside, withIntermediateDirectories: true)

    let moved = try await fixture.remember("moved.jpg")
    try fm.moveItem(at: folder.appendingPathComponent("moved.jpg"), to: outside.appendingPathComponent("moved.jpg"))
    #expect(await resolver.resolve(moved) == .missing, "moved out of the root")

    let deleted = try await fixture.remember("deleted.jpg")
    try fm.removeItem(at: folder.appendingPathComponent("deleted.jpg"))
    #expect(await resolver.resolve(deleted) == .missing, "deleted")

    let swapped = try await fixture.remember("a.jpg", bytes: Data("A".utf8))
    _ = try await fixture.remember("b.jpg", bytes: Data("B".utf8))
    try fm.removeItem(at: folder.appendingPathComponent("a.jpg"))
    try fm.moveItem(at: folder.appendingPathComponent("b.jpg"), to: folder.appendingPathComponent("a.jpg"))
    #expect(await resolver.resolve(swapped) == .missing, "another file moved onto the path")

    let directory = try await fixture.remember("dir.jpg")
    try fm.removeItem(at: folder.appendingPathComponent("dir.jpg"))
    try fm.createDirectory(at: folder.appendingPathComponent("dir.jpg"), withIntermediateDirectories: true)
    #expect(await resolver.resolve(directory) == .missing, "replaced by a directory")

    let linked = try await fixture.remember("linked.jpg")
    try fm.moveItem(at: folder.appendingPathComponent("linked.jpg"), to: outside.appendingPathComponent("linked.jpg"))
    try fm.createSymbolicLink(at: folder.appendingPathComponent("linked.jpg"), withDestinationURL: outside.appendingPathComponent("linked.jpg"))
    #expect(await resolver.resolve(linked) == .missing, "now a link to the same file outside the root")

    _ = try await fixture.remember("unknown.jpg")
    let unknown = try #require(PersonalImageRef(fileURL: folder.appendingPathComponent("unknown.jpg"), root: fixture.root, fileNumber: nil))
    #expect(await resolver.resolve(unknown) == .missing, "no recorded file number")
    #expect(fixture.scope.counts[0] == fixture.scope.counts[1])
}

@Test func personalImageResolverNeverServesStaleResult() async throws {
    let fixture = try await PersonalResolverFixture()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let resolver = fixture.resolver
    let ref = try await fixture.remember("a.jpg")
    guard case .present = await resolver.resolve(ref) else { Issue.record("expected present first"); return }
    fixture.scope.deny = true
    #expect(await resolver.resolve(ref) == .revoked)
    #expect(await resolver.resolve(ref) == .revoked)
    fixture.scope.deny = false
    _ = try await fixture.access.reconnect(fixture.rootID, folder: fixture.folder)
    guard case .present = await resolver.resolve(ref) else { Issue.record("expected present after reconnect"); return }
    try FileManager.default.removeItem(at: fixture.folder.appendingPathComponent("a.jpg"))
    #expect(await resolver.resolve(ref) == .missing)
    #expect(fixture.scope.counts[0] == fixture.scope.counts[1])
}

@Test func personalImageResolverRevokedWhenRootFolderGone() async throws {
    let fixture = try await PersonalResolverFixture()
    defer { try? FileManager.default.removeItem(at: fixture.base) }
    let ref = try await fixture.remember("a.jpg")
    try FileManager.default.removeItem(at: fixture.folder)
    let relaunched = try FileAccess(scope: fixture.scope, bookmarks: SystemSecurityScope(),
        store: BookmarkStore(url: fixture.base.appendingPathComponent("support/roots.json")), buildSHA: "personal")
    #expect(await PersonalImageResolver(access: relaunched).resolve(ref) == .revoked)
    #expect(await fixture.resolver.resolve(ref) == .revoked)
}

@Test func personalImageResolverUsesEachRefsOwnRoot() async throws {
    let first = try await PersonalResolverFixture(name: "one")
    defer { try? FileManager.default.removeItem(at: first.base) }
    let secondFolder = first.base.appendingPathComponent("two")
    try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
    let secondID = try await first.access.grant(folder: secondFolder)
    let one = try await first.remember("a.jpg", bytes: Data("one".utf8))
    try Data("two".utf8).write(to: secondFolder.appendingPathComponent("a.jpg"))
    let number = try await first.access.withLease(.root(secondID, file: secondFolder)) { _ in
        PersonalImageResolver.fingerprint(of: secondFolder.appendingPathComponent("a.jpg"))
    }
    let two = try #require(PersonalImageRef(fileURL: secondFolder.appendingPathComponent("a.jpg"),
        root: ItemIdentityRoot(id: secondID, url: secondFolder), fileNumber: number))
    guard case .present(let urlOne) = await first.resolver.resolve(one),
          case .present(let urlTwo) = await first.resolver.resolve(two) else { Issue.record("expected both present"); return }
    #expect(try Data(contentsOf: urlOne) == Data("one".utf8))
    #expect(try Data(contentsOf: urlTwo) == Data("two".utf8))
    try FileManager.default.removeItem(at: secondFolder)
    #expect(await first.resolver.resolve(two) == .revoked)
    guard case .present = await first.resolver.resolve(one) else { Issue.record("root one unaffected"); return }
}

@Test func personalImageResolverRevokedOnBookmarkOrScopeFailure() async throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: base) }
    let folder = base.appendingPathComponent("root")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("a.jpg")
    try Data([1]).write(to: file)
    let scope = CountingScope(), codec = FakeBookmarks()
    let access = try FileAccess(scope: scope, bookmarks: codec, store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "personal")
    let id = try await access.grant(folder: folder)
    let ref = try #require(PersonalImageRef(fileURL: file, root: ItemIdentityRoot(id: id, url: folder),
        fileNumber: PersonalImageResolver.fingerprint(of: file)))
    let resolver = PersonalImageResolver(access: access)
    guard case .present = await resolver.resolve(ref) else { Issue.record("expected present"); return }
    codec.fails = true
    #expect(await resolver.resolve(ref) == .revoked)
    codec.fails = false
    let fresh = try FileAccess(scope: scope, bookmarks: codec, store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "personal")
    scope.succeeds = false
    #expect(await PersonalImageResolver(access: fresh).resolve(ref) == .revoked)
    #expect(scope.counts[0] == scope.counts[1] + 1, "the denied start is counted but never stopped")
}

@Test func personalImageResolverBalancesLeases() async throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: base) }
    let folder = base.appendingPathComponent("root")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let scope = CountingScope(), codec = FakeBookmarks()
    let access = try FileAccess(scope: scope, bookmarks: codec, store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "personal")
    let id = try await access.grant(folder: folder)
    let root = ItemIdentityRoot(id: id, url: folder)
    func ref(_ name: String) throws -> PersonalImageRef {
        let file = folder.appendingPathComponent(name)
        try Data([7]).write(to: file)
        return try #require(PersonalImageRef(fileURL: file, root: root, fileNumber: PersonalImageResolver.fingerprint(of: file)))
    }
    let present = try ref("present.jpg"), deleted = try ref("deleted.jpg")
    try fm.removeItem(at: folder.appendingPathComponent("deleted.jpg"))
    let resolver = PersonalImageResolver(access: access)
    var previous = scope.counts[0]
    for _ in 0..<5 {
        for (value, expected) in [(present, "present"), (deleted, "missing")] {
            let outcome = await resolver.resolve(value)
            switch outcome {
            case .present: #expect(expected == "present")
            case .missing: #expect(expected == "missing")
            case .revoked: Issue.record("unexpected revoked")
            }
            #expect(scope.counts[0] == scope.counts[1])
            #expect(scope.counts[0] > previous, "every resolve takes a fresh lease")
            previous = scope.counts[0]
        }
    }
    #expect(PersonalImageResolver.fingerprint(of: folder.appendingPathComponent("deleted.jpg")) == nil)
}
