import Foundation
import Testing
import PicseeCore
import PicseeInfrastructure

struct IdentityTree {
    let root: URL
    let file: URL
    let id = AccessRootID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        file = root.appendingPathComponent("b.png")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a"), withIntermediateDirectories: true)
        try Data("first".utf8).write(to: file)
    }
    var scope: ItemIdentityRoot { ItemIdentityRoot(id: id, url: root) }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
private struct MissingIdentityReader: FileIdentityResourceReading {
    func identity(for fileURL: URL) throws -> FileResourceIdentity? {
        #expect(!Thread.isMainThread)
        return nil
    }
}

@Test func itemResolverCanonicalAliasesRenameAndHardLinks() async throws {
    let tree = try IdentityTree(); defer { tree.remove() }
    let resolver = FileItemIdentityResolver(root: tree.scope)
    let original = try await resolver.identity(for: tree.file)
    #expect(original == .rootRelative(rootID: tree.id, relativePath: "b.png"))
    let link = tree.root.appendingPathComponent("link.png")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tree.file)
    for alias in [tree.root.appendingPathComponent("a/../b.png"), link,
                  URL(fileURLWithPath: tree.root.path + "/").appendingPathComponent("b.png")] {
        #expect(try await resolver.identity(for: alias) == original)
    }
    let trailingRoot = FileItemIdentityResolver(root: ItemIdentityRoot(id: tree.id, url: URL(fileURLWithPath: tree.root.path + "/")))
    #expect(try await trailingRoot.identity(for: tree.file) == original)
    let hardLink = tree.root.appendingPathComponent("hard.png")
    try FileManager.default.linkItem(at: tree.file, to: hardLink)
    // User chose path identity: two simultaneously existing hard-link paths are two items.
    #expect(try await resolver.identity(for: hardLink) != original)
    let other = tree.root.appendingPathComponent("other.png")
    try Data("other".utf8).write(to: other)
    #expect(try await resolver.identity(for: other) != original)
    let renamed = tree.root.appendingPathComponent("renamed.png")
    try FileManager.default.moveItem(at: tree.file, to: renamed)
    #expect(try await resolver.identity(for: renamed) == original)
}

@Test @MainActor func itemResolverMissingResourcesHaveExplicitFallbacks() async throws {
    let tree = try IdentityTree(); defer { tree.remove() }
    let resolver = FileItemIdentityResolver(root: tree.scope, reader: MissingIdentityReader())
    #expect(try await resolver.identity(for: tree.file) == .rootRelative(rootID: tree.id, relativePath: "b.png"))
    let grant = FileItemIdentityResolver(reader: MissingIdentityReader())
    let first = try await grant.identity(for: tree.file)
    #expect(try await grant.identity(for: tree.root.appendingPathComponent("a/../b.png")) == first)
    #expect(first.stableEncoding.hasPrefix("id1:ephemeral:"))
    let other = tree.root.appendingPathComponent("other.png")
    try Data("other".utf8).write(to: other)
    #expect(try await grant.identity(for: other) != first)
    let outside = tree.root.deletingLastPathComponent().appendingPathComponent("outside.png")
    await #expect(throws: FileAccessError.outsideRoot) { try await resolver.identity(for: outside) }
    // resolvingSymlinksInPath needs an existing target; never overwrite or remove another owner's file.
    let ownsOutside = !FileManager.default.fileExists(atPath: outside.path)
    if ownsOutside { try Data("outside".utf8).write(to: outside, options: .withoutOverwriting) }
    defer { if ownsOutside { try? FileManager.default.removeItem(at: outside) } }
    let escape = tree.root.appendingPathComponent("escape.png")
    try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: outside)
    await #expect(throws: FileAccessError.outsideRoot) { try await resolver.identity(for: escape) }
    await #expect(throws: FileAccessError.outsideRoot) { try await grant.identity(for: URL(string: "https://example.invalid/a")!) }
}

private final class OptionalIdentityReader: FileIdentityResourceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var missing = false
    func makeUnavailable() { lock.withLock { missing = true } }
    func identity(for fileURL: URL) throws -> FileResourceIdentity? {
        if lock.withLock({ missing }) { return nil }
        return try URLIdentityResourceReader().identity(for: fileURL)
    }
}

@Test func itemResolverVacatedNameDoesNotCollideWithRenamedItem() async throws {
    for missing in [false, true] {
        let tree = try IdentityTree(); defer { tree.remove() }
        let reader = OptionalIdentityReader()
        let resolver = FileItemIdentityResolver(root: tree.scope, reader: reader)
        let original = try await resolver.identity(for: tree.file)
        let renamed = tree.root.appendingPathComponent("renamed.png")
        try FileManager.default.moveItem(at: tree.file, to: renamed)
        #expect(try await resolver.identity(for: renamed) == original)
        if missing { reader.makeUnavailable() }
        try Data("new file".utf8).write(to: tree.file)
        let new = try await resolver.identity(for: tree.file)
        #expect(new != original)
        #expect(try await resolver.identity(for: tree.file) == new)
        #expect(try await resolver.identity(for: renamed) == original)
    }
}

@Test func itemResolverFileGrantsUseResourceBytesWhenAvailable() async throws {
    let tree = try IdentityTree(); defer { tree.remove() }
    let first = FileItemIdentityResolver()
    let item = try await first.identity(for: tree.file)
    #expect(item.stableEncoding.hasPrefix("id1:res:"))
    #expect(try await FileItemIdentityResolver().identity(for: tree.file) == item)
    let renamed = tree.root.appendingPathComponent("renamed.png")
    try FileManager.default.moveItem(at: tree.file, to: renamed)
    #expect(try await first.identity(for: renamed) == item)
    #expect(try await FileItemIdentityResolver().identity(for: renamed) == item)
}
