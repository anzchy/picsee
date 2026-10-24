import Foundation

/// A scan is nonrecursive unless the current window explicitly enables recursion.
/// Bounds apply to visited filesystem entries and directory depth, including nonimages.
public struct FolderScanOptions: Equatable, Sendable {
    public var recursive: Bool
    public var maxVisitedEntries: Int
    public var maxDepth: Int
    public init(recursive: Bool = false, maxVisitedEntries: Int = 100_000, maxDepth: Int = 64) {
        self.recursive = recursive
        self.maxVisitedEntries = maxVisitedEntries
        self.maxDepth = maxDepth
    }
}

public enum FolderScanLimitError: Error, Equatable, Sendable {
    case entryLimit(limit: Int, admittedImages: Int)
    case depthLimit(limit: Int, admittedImages: Int)
}

/// Caller holds the root lease until this operation exits, including cancellation.
/// Async delivery applies backpressure: the scanner waits before enumerating more.
public protocol FolderScanning: Sendable {
    func scan(in folder: URL, root: ItemIdentityRoot, options: FolderScanOptions,
        emit: @Sendable ([FolderEntry]) async throws -> Void) async throws
}

public extension FolderScanning {
    func scan(in folder: URL, root: ItemIdentityRoot,
        emit: @Sendable ([FolderEntry]) async throws -> Void) async throws {
        try await scan(in: folder, root: root, options: .init(), emit: emit)
    }
}
