import Foundation
import Testing
import PicseeCore
import PicseeInfrastructure

@Test func accessRecentFoldersPersistNewestTenWithoutBookmarksOrAuthority() async throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: base) }
    let path = base.appendingPathComponent("recent.json")
    let store = RecentFolderStore(url: path)
    #expect(try await store.load().isEmpty)
    var folders: [RecentFolder] = []
    for n in 0..<12 {
        let folder = RecentFolder(rootID: AccessRootID(), url: base.appendingPathComponent("folder\(n)"), displayName: "folder\(n)")
        folders.append(folder)
        try await store.add(folder)
    }
    let reopened = RecentFolderStore(url: path)
    #expect(try await reopened.load().map(\.displayName) == (2..<12).reversed().map { "folder\($0)" })
    try await reopened.add(folders[3])
    #expect(try await reopened.load().count == 10)
    #expect(try await reopened.load().first == folders[3])
    let regrant = RecentFolder(rootID: AccessRootID(), url: folders[3].url, displayName: "regranted")
    try await reopened.add(regrant)
    #expect(try await reopened.load().count == 10)
    #expect(try await reopened.load().first == regrant)
    try #require(fm.fileExists(atPath: path.path))
    #expect(!String(decoding: try Data(contentsOf: path), as: UTF8.self).contains("bookmark"))
    let access = try FileAccess(scope: CountingScope(), bookmarks: FakeBookmarks(), store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "new")
    #expect(await access.rootCovering(folders[3].url) == nil)
    try Data("invalid".utf8).write(to: path)
    await #expect(throws: FileAccessError.corruptStore) { try await reopened.load() }
    await #expect(throws: FileAccessError.corruptStore) { try await reopened.add(regrant) }
}
