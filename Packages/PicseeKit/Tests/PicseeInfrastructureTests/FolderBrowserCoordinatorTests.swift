import Foundation
import Testing
import PicseeCore
import PicseeApplication
@testable import PicseeInfrastructure

@Test @MainActor func folderBrowserCoordinatorRealLeaseIntegration() async throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let root = base.appendingPathComponent("images")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    for name in ["img10.png", "img2.png"] { try Data().write(to: root.appendingPathComponent(name)) }
    let scope = CountingScope()
    let access = try FileAccess(scope: scope, bookmarks: FakeBookmarks(),
        store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "P2-02-WI-3")
    let id = try await access.grant(folder: root)
    #expect(scope.counts == [1, 1])
    let coordinator = FolderScanCoordinator(access: access, scanner: FolderBrowser())
    try await coordinator.begin(folder: root, rootID: id).value
    #expect(coordinator.snapshot?.entries.map(\.url.lastPathComponent) == ["img2.png", "img10.png"])
    #expect(coordinator.snapshot?.entries.map(\.itemID) == [
        .rootRelative(rootID: id, relativePath: "img2.png"), .rootRelative(rootID: id, relativePath: "img10.png")])
    #expect(coordinator.snapshot?.isComplete == true)
    #expect(scope.counts == [2, 2])
    coordinator.end()
    #expect(coordinator.snapshot == nil)
    let missing = coordinator.begin(folder: root.appendingPathComponent("missing"), rootID: id)
    await #expect(throws: (any Error).self) { try await missing.value }
    #expect(coordinator.failure != nil)
    #expect(!coordinator.isReadingFolder)
    #expect(scope.counts == [3, 3])
    let empty = root.appendingPathComponent("empty")
    try fm.createDirectory(at: empty, withIntermediateDirectories: true)
    try await coordinator.begin(folder: empty, rootID: id).value
    #expect(coordinator.snapshot?.entries == [])
    #expect(coordinator.snapshot?.isComplete == true)
    #expect(scope.counts == [4, 4])
}
