import Foundation

/// A favorite or recently viewed image: its Access Root and canonical root-relative path, never bytes,
/// bookmarks or absolute paths. Only a root item can be one, so a File Grant image is never remembered.
/// `fileNumber` is the file number seen when recorded; equality ignores it.
public struct PersonalImageRef: Hashable, Codable, Sendable {
    public let rootID: AccessRootID
    public let relativePath: String
    public let fileNumber: UInt64?
    public var itemID: ItemID { .rootRelative(rootID: rootID, relativePath: relativePath) }

    /// Same canonical path as `FolderEntry.itemID`; nil for the root itself or a target outside it.
    public init?(fileURL: URL, root: ItemIdentityRoot, fileNumber: UInt64?) {
        guard fileURL.isFileURL else { return nil }
        let boundary = Self.canonical(root.url).pathComponents
        let target = Self.canonical(fileURL).pathComponents
        guard target.count > boundary.count, target.starts(with: boundary) else { return nil }
        rootID = root.id
        relativePath = target.dropFirst(boundary.count).joined(separator: "/")
        self.fileNumber = fileNumber
    }
    static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rootID == rhs.rootID && lhs.relativePath == rhs.relativePath
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rootID); hasher.combine(relativePath)
    }
    private enum CodingKeys: String, CodingKey { case rootID, relativePath, fileNumber }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rootID.rawValue, forKey: .rootID)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encodeIfPresent(fileNumber, forKey: .fileNumber)
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rootID = AccessRootID(rawValue: try container.decode(UUID.self, forKey: .rootID))
        relativePath = try container.decode(String.self, forKey: .relativePath)
        fileNumber = try container.decodeIfPresent(UInt64.self, forKey: .fileNumber)
        let normalized = URL(fileURLWithPath: "/" + relativePath).standardizedFileURL.path
        guard !relativePath.isEmpty, normalized == "/" + relativePath,
              !relativePath.split(separator: "/").contains("..") else {
            throw DecodingError.dataCorruptedError(forKey: .relativePath, in: container,
                debugDescription: "Noncanonical relative path")
        }
    }
}

public struct PersonalImageVisit: Equatable, Codable, Sendable {
    public let ref: PersonalImageRef
    public let viewedAt: Date
    public init(ref: PersonalImageRef, viewedAt: Date) { self.ref = ref; self.viewedAt = viewedAt }
}

/// `missing`: the recorded file is not at its path (moved, deleted or replaced); never another file's pixels.
/// `revoked`: its Access Root cannot be reached now.
public enum PersonalImageAvailability: Equatable, Sendable {
    case present(URL), missing, revoked
}
