import Foundation
import Testing
@testable import PicseeInfrastructure

@Test func accessProbeGathererReadsRealBookmarkAndListsDirectory() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }
    let folder = root.appendingPathComponent("Photos", isDirectory: true)
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("image".utf8).write(to: folder.appendingPathComponent("one.jpg"))

    let gatherer = AccessProbeFactGatherer()
    let plain = try gatherer.makeBookmark(for: folder, storingVolumeProperties: false)
    let enriched = try gatherer.makeBookmark(for: folder, storingVolumeProperties: true)
    let report = gatherer.gather(bookmarkData: enriched)
    let expectedUUID = try folder.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString

    #expect(plain != enriched)
    #expect(report.volume.uuid == expectedUUID)
    #expect(report.resolution.url?.resolvingSymlinksInPath() == folder.resolvingSymlinksInPath())
    #expect(report.resolution.stale == false)
    #expect(report.scopeStarted != nil)
    #expect(report.listing?.entryCount == 1)
    #expect(report.listing?.error == nil)
    #expect(!report.isInTrash)
    #expect(report.classification.cause == .readable)
    #expect(report.latencyMilliseconds >= 0)
}

private final class AccessProbeBookmarkRecorder: AccessProbeBookmarkCoding, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedOptions: URL.BookmarkResolutionOptions?
    var options: URL.BookmarkResolutionOptions? { lock.withLock { recordedOptions } }

    func makeBookmark(for url: URL, includingResourceValuesForKeys keys: Set<URLResourceKey>?) throws -> Data {
        Data([1])
    }

    func volumeProperties(in data: Data) -> AccessProbeVolume {
        AccessProbeVolume(uuid: "volume-a", url: nil, name: "Photos")
    }

    func resolve(_ data: Data, options: URL.BookmarkResolutionOptions) throws -> AccessProbeResolution {
        lock.withLock { recordedOptions = options }
        return .resolved(URL(fileURLWithPath: "/Volumes/Photos/2026", isDirectory: true), stale: false)
    }
}

@Test func accessProbeResolutionNeverMountsOrShowsUI() {
    let bookmarks = AccessProbeBookmarkRecorder()
    let gatherer = AccessProbeFactGatherer(
        bookmarks: bookmarks,
        scope: SystemSecurityScope(),
        mountedVolumes: { [AccessProbeVolume(uuid: "volume-a", url: nil, name: "Photos")] },
        lister: { _ in 0 },
        isInTrash: { _ in false }
    )

    _ = gatherer.gather(bookmarkData: Data([1]))

    #expect(bookmarks.options == [.withSecurityScope, .withoutMounting, .withoutUI])
}

@Test func accessProbeGathererFollowsRenamedFolder() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }
    let original = root.appendingPathComponent("Original", isDirectory: true)
    let renamed = root.appendingPathComponent("Renamed", isDirectory: true)
    try fileManager.createDirectory(at: original, withIntermediateDirectories: true)
    let gatherer = AccessProbeFactGatherer()
    let bookmark = try gatherer.makeBookmark(for: original, storingVolumeProperties: true)

    try fileManager.moveItem(at: original, to: renamed)
    let report = gatherer.gather(bookmarkData: bookmark)

    #expect(report.resolution.url?.resolvingSymlinksInPath() == renamed.resolvingSymlinksInPath())
    #expect(report.resolution.stale != nil)
    #expect(report.listing?.entryCount == 0)
    #expect(report.classification.cause == .readable)
}

@Test func accessProbeGathererCapturesDeletedFolderFailure() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }
    let folder = root.appendingPathComponent("Deleted", isDirectory: true)
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    let gatherer = AccessProbeFactGatherer()
    let bookmark = try gatherer.makeBookmark(for: folder, storingVolumeProperties: true)

    try fileManager.removeItem(at: folder)
    let report = gatherer.gather(bookmarkData: bookmark)

    #expect(report.resolution.error != nil || report.listing?.error != nil)
    #expect(report.classification.cause != .readable)
}

@Test func accessProbeGathererMarksFolderInTrash() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    var trashed: NSURL?
    defer {
        if let trashed { try? fileManager.removeItem(at: trashed as URL) }
        try? fileManager.removeItem(at: root)
    }
    let folder = root.appendingPathComponent("Trashed", isDirectory: true)
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    let gatherer = AccessProbeFactGatherer()
    let bookmark = try gatherer.makeBookmark(for: folder, storingVolumeProperties: true)

    try fileManager.trashItem(at: folder, resultingItemURL: &trashed)
    let report = gatherer.gather(bookmarkData: bookmark)

    #expect(report.resolution.url?.resolvingSymlinksInPath() == (trashed as URL?)?.resolvingSymlinksInPath())
    #expect(report.isInTrash)
    #expect(report.classification.isInTrash)
    #expect(report.classification.cause == .unknown)
}

@Test func accessProbeGathererCapturesPermissionDenial() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let folder = root.appendingPathComponent("Denied", isDirectory: true)
    defer {
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        try? fileManager.removeItem(at: root)
    }
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    let gatherer = AccessProbeFactGatherer()
    let bookmark = try gatherer.makeBookmark(for: folder, storingVolumeProperties: true)

    try fileManager.setAttributes([.posixPermissions: 0], ofItemAtPath: folder.path)
    let report = gatherer.gather(bookmarkData: bookmark)

    #expect(report.scopeStarted != nil)
    #expect(report.listing?.error != nil)
    #expect(report.classification.cause == .accessExpired)
}

@Test func accessProbeGathererCapturesCorruptBookmarkError() {
    let report = AccessProbeFactGatherer().gather(bookmarkData: Data("corrupt".utf8))

    #expect(report.volume.uuid == nil)
    #expect(report.resolution.error != nil)
    #expect(report.scopeStarted == nil)
    #expect(report.listing == nil)
    #expect(report.classification.cause == .unknown)
}
