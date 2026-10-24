import Foundation
import Testing
import PicseeCore
import PicseeInfrastructure

private actor RecursiveResults {
    var entries: [FolderEntry] = []
    func append(_ batch: [FolderEntry]) { entries += batch }
}

private struct RecursiveTree {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("picsee-recursive-\(UUID())")
    let rootID = AccessRootID()
    var root: URL { base.appendingPathComponent("root") }
    var identity: ItemIdentityRoot { .init(id: rootID, url: root) }
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    func directory(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func image(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try Data().write(to: url)
        return url
    }
    func cleanup() { try? FileManager.default.removeItem(at: base) }
}

@Test func recursiveScanIncludesNestedImagesOnlyWhenEnabled() async throws {
    let tree = try RecursiveTree(); defer { tree.cleanup() }
    _ = try tree.image("top.png")
    _ = try tree.directory("sub")
    _ = try tree.image("sub/nested.png")
    let off = RecursiveResults(), on = RecursiveResults()
    let root = tree.identity
    try await FolderBrowser().scan(in: tree.root, root: root) { await off.append($0) }
    try await FolderBrowser().scan(in: tree.root, root: root, options: .init(recursive: true)) { await on.append($0) }
    #expect(Set(await off.entries.map(\.relativePath)) == ["top.png"])
    #expect(Set(await on.entries.map(\.relativePath)) == ["top.png", "sub/nested.png"])
}

@Test func recursiveScanRejectsOutsideLinksAndCyclesWithoutDuplicateIdentity() async throws {
    let tree = try RecursiveTree(); defer { tree.cleanup() }
    let sub = try tree.directory("sub")
    let image = try tree.image("sub/a.png")
    try FileManager.default.createSymbolicLink(at: sub.appendingPathComponent("back"), withDestinationURL: tree.root)
    try FileManager.default.createSymbolicLink(at: tree.root.appendingPathComponent("alias.png"), withDestinationURL: image)
    let outside = tree.base.appendingPathComponent("outside.png")
    try Data().write(to: outside)
    try FileManager.default.createSymbolicLink(at: tree.root.appendingPathComponent("outside.png"), withDestinationURL: outside)
    let outsideDirectory = tree.base.appendingPathComponent("outside-directory")
    try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
    try Data().write(to: outsideDirectory.appendingPathComponent("escaped.png"))
    try FileManager.default.createSymbolicLink(at: tree.root.appendingPathComponent("outside-directory"),
        withDestinationURL: outsideDirectory)
    let result = RecursiveResults()
    try await FolderBrowser().scan(in: tree.root, root: tree.identity, options: .init(recursive: true)) { await result.append($0) }
    let entries = await result.entries
    #expect(entries.count == 1)
    #expect(entries[0].itemID == .rootRelative(rootID: tree.rootID, relativePath: "sub/a.png"))
}

@Test func recursiveScanEntryGuardReportsHonestPartialCount() async throws {
    let tree = try RecursiveTree(); defer { tree.cleanup() }
    _ = try tree.image("a.png")
    _ = try tree.image("b.png")
    let result = RecursiveResults()
    var limitError: FolderScanLimitError?
    do {
        try await FolderBrowser().scan(in: tree.root, root: tree.identity,
            options: .init(recursive: true, maxVisitedEntries: 1)) { await result.append($0) }
    } catch { limitError = error as? FolderScanLimitError }
    #expect(limitError == .entryLimit(limit: 1, admittedImages: 1))
    #expect(await result.entries.count == 1)
}

@Test func recursiveScanGuardBoundaryAndDepthAreExplicit() async throws {
    let tree = try RecursiveTree(); defer { tree.cleanup() }
    _ = try tree.directory("sub")
    _ = try tree.image("sub/a.png")
    let exact = RecursiveResults()
    try await FolderBrowser().scan(in: tree.root, root: tree.identity,
        options: .init(recursive: true, maxVisitedEntries: 2, maxDepth: 1)) { await exact.append($0) }
    #expect(await exact.entries.map(\.relativePath) == ["sub/a.png"])
    let limited = RecursiveResults()
    var limitError: FolderScanLimitError?
    do {
        try await FolderBrowser().scan(in: tree.root, root: tree.identity,
            options: .init(recursive: true, maxDepth: 0)) { await limited.append($0) }
    } catch { limitError = error as? FolderScanLimitError }
    #expect(limitError == .depthLimit(limit: 0, admittedImages: 0))
    #expect(await limited.entries.isEmpty)
}

@Test func recursiveScanEmptyAndHiddenPackageFoldersStayExcluded() async throws {
    let tree = try RecursiveTree(); defer { tree.cleanup() }
    _ = try tree.directory("empty")
    _ = try tree.directory(".hidden")
    _ = try tree.image(".hidden/a.png")
    _ = try tree.directory("bundle.app")
    _ = try tree.image("bundle.app/a.png")
    let result = RecursiveResults()
    try await FolderBrowser().scan(in: tree.root, root: tree.identity, options: .init(recursive: true)) {
        await result.append($0)
    }
    #expect(await result.entries.isEmpty)
}

@Test func recursiveScanDeepTreeStopsAtConfiguredDepth() async throws {
    let tree = try RecursiveTree(); defer { tree.cleanup() }
    var path = ""
    for level in 0..<8 {
        path += "d\(level)/"
        _ = try tree.directory(path)
    }
    _ = try tree.image(path + "deep.png")
    let result = RecursiveResults()
    var limitError: FolderScanLimitError?
    do {
        try await FolderBrowser().scan(in: tree.root, root: tree.identity,
            options: .init(recursive: true, maxDepth: 5)) { await result.append($0) }
    } catch { limitError = error as? FolderScanLimitError }
    #expect(limitError == .depthLimit(limit: 5, admittedImages: 0))
    #expect(await result.entries.isEmpty)
}

@Test func recursiveScanDeepAliasToSeenDirectoryDoesNotTripDepthGuard() async throws {
    let tree = try RecursiveTree(); defer { tree.cleanup() }
    let seen = try tree.directory("seen")
    _ = try tree.image("seen/a.png")
    let nested = try tree.directory("nested")
    try FileManager.default.createSymbolicLink(at: nested.appendingPathComponent("alias-to-seen"),
        withDestinationURL: seen)
    let result = RecursiveResults()
    try await FolderBrowser().scan(in: tree.root, root: tree.identity,
        options: .init(recursive: true, maxDepth: 1)) { await result.append($0) }
    #expect(await result.entries.count == 1)
}

@Test func recursiveScanCancellationStopsBeforeNextNestedBatch() async throws {
    let tree = try RecursiveTree(); defer { tree.cleanup() }
    _ = try tree.directory("sub")
    for index in 0..<321 { _ = try tree.image(String(format: "sub/%04d.png", index)) }
    let result = RecursiveResults()
    let task = Task {
        try await FolderBrowser().scan(in: tree.root, root: tree.identity, options: .init(recursive: true)) { batch in
            await result.append(batch)
            withUnsafeCurrentTask { $0?.cancel() }
        }
    }
    var cancelled = false
    do { try await task.value } catch is CancellationError { cancelled = true }
    #expect(cancelled)
    #expect(await result.entries.count == FolderBrowser.firstBatchSize)
}
