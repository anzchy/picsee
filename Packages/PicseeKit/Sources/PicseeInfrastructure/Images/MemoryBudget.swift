import Foundation

/// The one process-wide image memory ledger (ADR-005): cache-resident pixels, pinned or evictable, plus admitted
/// decode staging, against one limit that every window shares. The peak is the largest total after any recorded change.
final class MemoryBudget: @unchecked Sendable {
    struct Usage: Equatable, Sendable {
        var pinned = 0
        var evictable = 0
        var reserved = 0
        var total: Int { pinned + evictable + reserved }
    }
    let limit: Int
    private let lock = NSLock()
    private var current = Usage()
    private var highest = 0
    init(limit: Int) {
        precondition(limit > 0)
        self.limit = limit
    }
    var usage: Usage { lock.withLock { current } }
    var peak: Int { lock.withLock { highest } }
    func resident(pinned: Int, evictable: Int) {
        lock.withLock { current.pinned = pinned; current.evictable = evictable; highest = max(highest, current.total) }
    }
    func reserved(_ bytes: Int) {
        lock.withLock { current.reserved = bytes; highest = max(highest, current.total) }
    }
}
