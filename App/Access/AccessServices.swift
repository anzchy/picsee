import Foundation
import PicseeCore
import PicseeApplication
import PicseeInfrastructure

struct AccessServices: Sendable {
    let files: FileAccess
    let recent: RecentFolderStore
    let lister = SiblingLister()
    let browser = FolderBrowser()
    /// One watch per Access Root, shared by every window's folder scan.
    let watch: WatchHub
    init(buildSHA: String) throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true).appendingPathComponent("Picsee")
        let system = SystemSecurityScope()
        files = try FileAccess(scope: system, bookmarks: system,
                               store: BookmarkStore(url: support.appendingPathComponent("access-roots.json")), buildSHA: buildSHA)
        recent = RecentFolderStore(url: support.appendingPathComponent("recent-folders.json"))
        watch = WatchHub(access: files, source: FSEventSource(), scheduler: DispatchWatchScheduler())
    }
    func grant(_ folder: URL) async throws -> AccessRootID {
        let id = try await files.grant(folder: folder)
        try await recent.add(RecentFolder(rootID: id, url: folder, displayName: folder.lastPathComponent))
        return id
    }
    func images(in folder: URL, rootID: AccessRootID) async throws -> [URL] {
        try await files.withLease(.root(rootID, file: folder)) { lease in
            try await lister.images(in: folder, root: lease.url)
        }
    }
    // Untested native composition; FileAccess and Recent persistence are package-tested.
    func rootURL(_ id: AccessRootID) async -> URL? { await files.rootURL(id) }
    func probeRootURL(_ id: AccessRootID) async throws -> URL { try await files.probeRootURL(id) }
    func reconnect(_ id: AccessRootID, folder: URL) async throws -> (rootID: AccessRootID, url: URL) {
        let targetID: AccessRootID
        let url: URL
        do { url = try await files.reconnect(id, folder: folder); targetID = id }
        catch FileAccessError.alreadyGranted(let other) {
            guard let held = await files.rootURL(other) else { throw FileAccessError.needsReconnection(other) }
            targetID = other; url = held
        }
        try await recent.add(RecentFolder(rootID: targetID, url: url, displayName: url.lastPathComponent))
        return (targetID, url)
    }
}
