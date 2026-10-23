import Foundation

/// Caller holds the root lease until this operation exits, including cancellation.
/// Async delivery applies backpressure: the scanner waits before enumerating more.
public protocol FolderScanning: Sendable {
    func scan(in folder: URL, root: ItemIdentityRoot,
        emit: @Sendable ([FolderEntry]) async throws -> Void) async throws
}
