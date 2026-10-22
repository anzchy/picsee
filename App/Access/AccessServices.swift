import Foundation
import PicseeCore
import PicseeApplication
import PicseeInfrastructure

struct AccessServices: Sendable {
    let files: FileAccess
    let recent: RecentFolderStore
    let lister = SiblingLister()
    init(buildSHA: String) throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true).appendingPathComponent("Picsee")
        let system = SystemSecurityScope()
        files = try FileAccess(scope: system, bookmarks: system,
                               store: BookmarkStore(url: support.appendingPathComponent("access-roots.json")), buildSHA: buildSHA)
        recent = RecentFolderStore(url: support.appendingPathComponent("recent-folders.json"))
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
}
