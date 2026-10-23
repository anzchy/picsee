import Foundation

/// Folder identity and scan generation. Construct under the scan's root lease.
/// Future sort/filter conditions belong in this value when those features exist.
public struct SnapshotVersion: Equatable, Sendable {
    public let rootID: AccessRootID
    public let folder: URL
    public let generation: UInt64
    public init(rootID: AccessRootID, folder: URL, generation: UInt64) {
        self.rootID = rootID
        self.folder = folder.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        self.generation = generation
    }
}

/// Original URL for display/opening; canonical target identity matches the image resolver.
/// Caller has checked the root boundary and holds its lease; construct off MainActor.
public struct FolderEntry: Equatable, Sendable {
    public let url: URL
    public let itemID: ItemID
    public let relativePath: String
    public init(url: URL, root: ItemIdentityRoot) {
        self.url = url
        let boundary = root.url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        let target = url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        let displayPath = url.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent).standardizedFileURL
        relativePath = displayPath.pathComponents.dropFirst(boundary.pathComponents.count).joined(separator: "/")
        itemID = .rootRelative(rootID: root.id,
            relativePath: target.pathComponents.dropFirst(boundary.pathComponents.count).joined(separator: "/"))
    }
}

public struct FolderSnapshot: Equatable, Sendable {
    public let version: SnapshotVersion
    public let entries: [FolderEntry]
    public let isComplete: Bool
    public init(version: SnapshotVersion, entries: [FolderEntry], isComplete: Bool) {
        self.version = version
        self.entries = entries.sorted {
            let names = $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent)
            return names == .orderedSame ? $0.relativePath < $1.relativePath : names == .orderedAscending
        }
        self.isComplete = isComplete
    }
    public func appending(_ batch: [FolderEntry], isComplete: Bool) -> Self {
        Self(version: version, entries: entries + batch, isComplete: isComplete)
    }
}
