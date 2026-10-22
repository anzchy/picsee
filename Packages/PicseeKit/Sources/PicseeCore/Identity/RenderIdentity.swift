import Foundation

public struct FileRevision: Hashable, Sendable {
    public let byteCount: Int
    public let modificationDate: Date?
    public init(byteCount: Int, modificationDate: Date?) {
        self.byteCount = byteCount
        self.modificationDate = modificationDate
    }
}

/// P0 has one static frame, oriented colour-managed SDR, decoder version 1.
public struct RenderKey: Hashable, Sendable {
    public let itemID: ItemID
    public let revision: FileRevision
    public let isPreview: Bool
    public let maximumPixelSize: Int
    public init(itemID: ItemID, revision: FileRevision, maximumPixelSize: Int, isPreview: Bool = false) {
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
