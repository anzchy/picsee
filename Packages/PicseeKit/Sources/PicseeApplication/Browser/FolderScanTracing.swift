import Foundation

public enum FolderScanOutcome: String, Equatable, Sendable { case complete, cancelled, replaced, failed }

/// Counts describe admitted snapshot entries, including inward aliases; navigation deduplicates separately.
/// Native adapters keep folder paths private and never log image names.
@MainActor public protocol FolderScanTracing: AnyObject {
    func begin(generation: UInt64, folderURL: URL)
    func firstBatch(count: Int, generation: UInt64)
    func complete(count: Int, generation: UInt64)
    func end(outcome: FolderScanOutcome, generation: UInt64)
}
