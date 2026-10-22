import Foundation

public enum FileAccessError: Error, Equatable, Sendable {
    case needsReconnection(AccessRootID), outsideRoot, startFailed, corruptStore, invalidFolder
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
