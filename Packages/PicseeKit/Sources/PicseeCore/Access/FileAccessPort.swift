import Foundation

public enum FileAccessError: Error, Equatable, Sendable {
    case needsReconnection(AccessRootID), outsideRoot, startFailed, corruptStore, invalidFolder
    case alreadyGranted(AccessRootID)
}

public enum AccessRequest: Hashable, Sendable {
    case root(AccessRootID, file: URL)
    case fileGrant(URL)
}

public struct AccessLease: Hashable, Sendable {
    public let token: UUID
    public let url: URL
    public let rootID: AccessRootID?
    public init(token: UUID = UUID(), url: URL, rootID: AccessRootID?) {
        self.token = token; self.url = url; self.rootID = rootID
    }
}

public protocol SecurityScope: Sendable {
    func start(_ url: URL) -> Bool
    func stop(_ url: URL)
    /// A point-in-time check of access already permitted by the sandbox.
    func isReadable(_ url: URL) -> Bool
}

public protocol AccessLeasing: Sendable {
    func acquire(_ request: AccessRequest) async throws -> AccessLease
    func release(_ lease: AccessLease) async
}

extension AccessLeasing {
    public func withLease<T: Sendable>(_ request: AccessRequest,
        operation: @Sendable (AccessLease) async throws -> T) async throws -> T {
        let lease = try await acquire(request)
        do {
            try Task.checkCancellation()
            let result = try await operation(lease)
            await release(lease)
            return result
        } catch {
            await release(lease)
            throw error
        }
    }
}

public struct ResolvedBookmark: Sendable {
    public let url: URL
    public let stale: Bool
    public init(url: URL, stale: Bool) { self.url = url; self.stale = stale }
}
public protocol BookmarkCoding: Sendable {
    func create(for url: URL) throws -> Data
    func resolve(_ data: Data) throws -> ResolvedBookmark
}

public struct AccessRootRecord: Codable, Equatable, Sendable {
    public let id: AccessRootID
    public var bookmark: Data
    public let displayName: String
    public let creatingBuildSHA: String
    public let createdAt: Date
    public init(id: AccessRootID, bookmark: Data, displayName: String, creatingBuildSHA: String, createdAt: Date) {
        self.id = id; self.bookmark = bookmark; self.displayName = displayName
        self.creatingBuildSHA = creatingBuildSHA; self.createdAt = createdAt
    }
}
