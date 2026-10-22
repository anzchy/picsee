import Foundation

/// A reference only: no bookmark or authority is stored here.
public struct RecentFolder: Codable, Equatable, Sendable {
    public let rootID: AccessRootID
    public let url: URL
    public let displayName: String
    public let openedAt: Date
    public init(rootID: AccessRootID, url: URL, displayName: String, openedAt: Date = Date()) {
        self.rootID = rootID; self.url = url; self.displayName = displayName; self.openedAt = openedAt
    }
}
