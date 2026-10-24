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
    public private(set) var isComplete: Bool
    /// Keep all admitted URLs above; browse each canonical identity through its first sorted URL.
    public let navigationEntries: [FolderEntry]
    private let navigationIndices: [ItemID: Int]
    public func navigationIndex(for itemID: ItemID) -> Int? { navigationIndices[itemID] }
    public init(version: SnapshotVersion, entries: [FolderEntry], isComplete: Bool) {
        self.init(version: version, orderedEntries: entries.sorted(by: Self.orderedBefore), isComplete: isComplete)
    }
    private init(version: SnapshotVersion, orderedEntries: [FolderEntry], isComplete: Bool) {
        self.version = version; entries = orderedEntries; self.isComplete = isComplete
        var unique: [FolderEntry] = [], indices: [ItemID: Int] = [:]
        for entry in orderedEntries where indices[entry.itemID] == nil {
            indices[entry.itemID] = unique.count
            unique.append(entry)
        }
        navigationEntries = unique; navigationIndices = indices
    }
    private static func orderedBefore(_ lhs: FolderEntry, _ rhs: FolderEntry) -> Bool {
        let names = lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent)
        return names == .orderedSame ? lhs.relativePath < rhs.relativePath : names == .orderedAscending
    }
    public func appending(_ batch: [FolderEntry], isComplete: Bool) -> Self {
        if batch.isEmpty {
            var result = self
            result.isComplete = isComplete
            return result
        }
        let incoming = batch.sorted(by: Self.orderedBefore)
        var ordered: [FolderEntry] = [], left = 0, right = 0
        ordered.reserveCapacity(entries.count + incoming.count)
        while left < entries.count && right < incoming.count {
            if Self.orderedBefore(incoming[right], entries[left]) {
                ordered.append(incoming[right]); right += 1
            } else {
                ordered.append(entries[left]); left += 1
            }
        }
        ordered.append(contentsOf: entries[left...])
        ordered.append(contentsOf: incoming[right...])
        return Self(version: version, orderedEntries: ordered, isComplete: isComplete)
    }
}
