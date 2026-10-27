import Foundation
import Testing
import PicseeCore
import PicseeApplication
@testable import PicseeInfrastructure

@Test func issue140FileGrantBookmarkFollowsRenameAndRefreshesStaleData() async throws {
    let f = try WatchFixture(folders: ["root"]); defer { f.remove() }
    let original = f.url("root/old.png"), renamed = f.url("root/new.png")
    try Data(repeating: 1, count: 4).write(to: original)
    let lease = try await f.access.acquire(.fileGrant(original))
    await f.access.release(lease)
    let created = f.bookmarks.count
    try FileManager.default.moveItem(at: original, to: renamed)
    f.bookmarks.relocated = renamed
    f.bookmarks.stale = true
    #expect(try await f.access.resolveFileGrant(original) == renamed)
    #expect(f.bookmarks.count > created)
    let movedLease = try await f.access.acquire(.fileGrant(original))
    #expect(movedLease.url == renamed)
    await f.access.release(movedLease)
    #expect(await f.access.records().isEmpty)
    f.bookmarks.fails = true
    await #expect(throws: FileAccessError.needsFileReconnection(original)) {
        _ = try await f.access.resolveFileGrant(original)
    }
}

@Test func issue140FileGrantSourceUsesRenamedFileAndReplacementPixels() async throws {
    let f = try WatchFixture(folders: ["root"]); defer { f.remove() }
    let original = f.url("root/old.png"), renamed = f.url("root/new.png")
    try FileManager.default.copyItem(at: fixture("landscape-3x2.png"), to: original)
    let source = try await AccessImageSource.open(.fileGrant(original), access: f.access,
        pipeline: ImageIOPipeline())
    let (oldRequest, oldImage) = try await source.image(maximumPixelSize: 64)
    try FileManager.default.moveItem(at: original, to: renamed)
    f.bookmarks.relocated = renamed
    let (renamedRequest, renamedImage) = try await source.image(maximumPixelSize: 64)
    #expect(renamedRequest.fileURL == renamed)
    #expect(renamedImage.itemID == oldImage.itemID)
    #expect(try rgba(renamedImage.image) == rgba(oldImage.image))
    try Data(contentsOf: fixture("portrait-2x3.png")).write(to: renamed, options: .atomic)
    let (replacementRequest, replacementImage) = try await source.image(maximumPixelSize: 64)
    #expect(replacementRequest.renderKey?.revision != oldRequest.renderKey?.revision)
    #expect(try rgba(replacementImage.image) != rgba(oldImage.image))
    await source.close()
}

@Test func issue140FileGrantRenameWinsWhenVacatedNameIsReused() async throws {
    let f = try WatchFixture(folders: ["root"]); defer { f.remove() }
    let original = f.url("root/old.png"), renamed = f.url("root/new.png")
    try Data(repeating: 1, count: 3).write(to: original)
    let lease = try await f.access.acquire(.fileGrant(original))
    await f.access.release(lease)
    try FileManager.default.moveItem(at: original, to: renamed)
    try Data(repeating: 2, count: 3).write(to: original)
    f.bookmarks.relocated = renamed
    #expect(try await f.access.resolveFileGrant(original) == renamed)
}

@Test func issue140SingleFileSamePathAtomicReplacementShowsNewPixels() async throws {
    let f = try WatchFixture(folders: ["root"]); defer { f.remove() }
    let file = f.url("root/image.png")
    try FileManager.default.copyItem(at: fixture("landscape-3x2.png"), to: file)
    let source = try await AccessImageSource.open(.fileGrant(file), access: f.access,
        pipeline: ImageIOPipeline())
    let (oldRequest, oldImage) = try await source.image(maximumPixelSize: 64)
    try Data(contentsOf: fixture("portrait-2x3.png")).write(to: file, options: .atomic)
    let (newRequest, newImage) = try await source.image(maximumPixelSize: 64)
    #expect(newRequest.renderKey?.itemID == oldRequest.renderKey?.itemID)
    #expect(newRequest.renderKey?.revision != oldRequest.renderKey?.revision)
    #expect(try rgba(newImage.image) != rgba(oldImage.image))
    await source.close()
}

@Test func issue140ExistingFileGrantBookmarkReportsScopeLossForReconnection() async throws {
    let f = try WatchFixture(folders: ["root"]); defer { f.remove() }
    let file = f.url("root/image.png")
    try Data(repeating: 1, count: 4).write(to: file)
    let lease = try await f.access.acquire(.fileGrant(file))
    await f.access.release(lease)
    f.scope.succeeds = false
    await #expect(throws: FileAccessError.needsFileReconnection(file)) {
        _ = try await f.access.acquire(.fileGrant(file))
    }
}

private actor NoRelocationLease: AccessLeasing {
    func acquire(_ request: AccessRequest) async throws -> AccessLease { throw FileAccessError.startFailed }
    func release(_ lease: AccessLease) async {}
}

@Test func issue140OtherAccessLeasesHaveNoImplicitFolderRelocation() async throws {
    #expect(try await NoRelocationLease().relocatedFolder(URL(fileURLWithPath: "/tmp"),
        rootID: AccessRootID()) == nil)
}
