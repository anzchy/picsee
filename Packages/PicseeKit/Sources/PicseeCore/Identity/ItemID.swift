import Foundation

/// Bootstrap identity token. File identity resolution belongs to P1-01.
public struct ItemID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public var stableEncoding: String { "id1:ephemeral:" + rawValue.uuidString }

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}
