import Foundation
import PicseeCore

public struct FileResourceIdentity: Hashable, Sendable {
    public let volumeUUID: String
    public let fileIdentifier: String
    public init(volumeUUID: String, fileIdentifier: String) {
        self.volumeUUID = volumeUUID; self.fileIdentifier = fileIdentifier
    }
}
public protocol FileIdentityResourceReading: Sendable {
    func identity(for fileURL: URL) throws -> FileResourceIdentity?
}
public struct URLIdentityResourceReader: FileIdentityResourceReading {
    public init() { }
    public func identity(for fileURL: URL) throws -> FileResourceIdentity? {
        // Both keys are available on macOS 14. Encode bytes, never the runtime resource object's description.
        var fresh = fileURL
        fresh.removeAllCachedResourceValues()
        let values = try fresh.resourceValues(forKeys: [.volumeUUIDStringKey, .fileResourceIdentifierKey])
        guard let volume = values.volumeUUIDString, let identifier = values.fileResourceIdentifier as? Data else { return nil }
        return FileResourceIdentity(volumeUUID: volume, fileIdentifier: identifier.base64EncodedString())
    }
}
/// Resolves on its own actor, never MainActor. The caller must already hold its File Grant or root lease.
/// Root paths own identity; resource bytes only let an observed rename retain its established ItemID.
/// Rename associations are session-local; durable rename tracking belongs to the later library/watcher.
public actor FileItemIdentityResolver: ItemIdentityResolving {
    private let root: ItemIdentityRoot?
    private let reader: any FileIdentityResourceReading
    private struct Entry {
        let item: ItemID
        let resource: FileResourceIdentity?
    }
    private var entries: [URL: Entry] = [:]
    public init(root: ItemIdentityRoot? = nil, reader: any FileIdentityResourceReading = URLIdentityResourceReader()) {
        self.root = root; self.reader = reader
    }
    public func identity(for fileURL: URL) throws -> ItemID {
        guard fileURL.isFileURL else { throw FileAccessError.outsideRoot }
        if let root, !AccessBoundary.contains(fileURL, in: root.url) { throw FileAccessError.outsideRoot }
        let path = fileURL.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        let resource = try reader.identity(for: path)
        let item: ItemID
        if let existing = entries[path] {
            item = existing.item // Includes replace-at-path, even when resource bytes changed.
        } else if let resource, let renamed = entries.first(where: {
            $0.value.resource == resource && !FileManager.default.fileExists(atPath: $0.key.path)
        }) {
            item = renamed.value.item
            entries.removeValue(forKey: renamed.key)
        } else if let root {
            let boundary = root.url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
            let relative = path.pathComponents.dropFirst(boundary.pathComponents.count).joined(separator: "/")
            let candidate = ItemID.rootRelative(rootID: root.id, relativePath: relative)
            if entries.values.contains(where: { $0.item == candidate }) {
                // A renamed live item still owns this token. Reusing its vacated name creates another item.
                item = resource.map { .resource(volumeUUID: $0.volumeUUID, fileIdentifier: $0.fileIdentifier) }
                    ?? .ephemeral(UUID())
            } else { item = candidate }
        } else if let resource {
            // File Grants have no AccessRootID. Available resource bytes identify them for this grant session.
            item = .resource(volumeUUID: resource.volumeUUID, fileIdentifier: resource.fileIdentifier)
        } else {
            // No file resource identity: one ephemeral token per canonical File Grant path, for this session only.
            item = .ephemeral(UUID())
        }
        entries[path] = Entry(item: item, resource: resource)
        return item
    }
}
