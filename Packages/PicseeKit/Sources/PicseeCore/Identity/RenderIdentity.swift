import Foundation

public struct FileRevision: Hashable, Sendable {
    public let byteCount: Int
    public let modificationDate: Date?
    public init(byteCount: Int, modificationDate: Date?) {
        self.byteCount = byteCount
        self.modificationDate = modificationDate
    }
}

public enum RenderPolicy: String, Sendable { case orientedSDR, unorientedSDR }
public enum RenderPurpose: String, Sendable { case viewer, thumbnail }
public struct RenderKey: Hashable, Sendable {
    public let frameIndex: Int
    public let policy: RenderPolicy
    public let decoderVersion: Int
    public let purpose: RenderPurpose
    /// Versioned UTF-8 cache-key text. P3-03 hashes this with SHA-256 for disk filenames.
    /// Field order: item, bytes, date bits (reference epoch), frame, edge, preview, policy, decoder, purpose.
    public var stableEncoding: String {
        let date = revision.modificationDate.map { String($0.timeIntervalSinceReferenceDate.bitPattern, radix: 16) } ?? "none"
        return ["rk1", itemID.stableEncoding, String(revision.byteCount), date, String(frameIndex),
                String(maximumPixelSize), isPreview ? "1" : "0", policy.rawValue,
                String(decoderVersion), purpose.rawValue].joined(separator: "|")
    }
    public let itemID: ItemID
    public let revision: FileRevision
    public let isPreview: Bool
    public let maximumPixelSize: Int
    public init(itemID: ItemID, revision: FileRevision, maximumPixelSize: Int, isPreview: Bool = false,
                frameIndex: Int = 0, policy: RenderPolicy = .orientedSDR,
                decoderVersion: Int = 1, purpose: RenderPurpose = .viewer) {
        self.frameIndex = frameIndex; self.policy = policy
        self.decoderVersion = decoderVersion; self.purpose = purpose
        self.isPreview = isPreview
        self.itemID = itemID
        self.revision = revision
        self.maximumPixelSize = maximumPixelSize
    }
}

public struct PresentationToken: Equatable, Sendable {
    public let binding: UUID
    public let generation: UUID
    public init(binding: UUID, generation: UUID) {
        self.binding = binding
        self.generation = generation
    }
    public func accepts(key: RenderKey, expected: RenderKey, token: PresentationToken) -> Bool {
        key.itemID == expected.itemID && key.revision == expected.revision && self == token
    }
}
