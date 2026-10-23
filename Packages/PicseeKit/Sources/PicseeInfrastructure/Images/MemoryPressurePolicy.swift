import Foundation
import PicseeCore

public enum MemoryPressureLevel: String, Sendable { case normal, warning, critical }

/// State advances only at pressure delivery or a request; recovery needs no timer.
struct MemoryPressurePolicy: Sendable {
    private(set) var level: MemoryPressureLevel = .normal
    let recoveryDelay: TimeInterval
    let clock: @Sendable () -> TimeInterval
    private var suspended = false
    private var normalSince: TimeInterval?
    init(recoveryDelay: TimeInterval, clock: @escaping @Sendable () -> TimeInterval) {
        precondition(recoveryDelay.isFinite && recoveryDelay >= 0)
        self.recoveryDelay = recoveryDelay; self.clock = clock
    }
    mutating func update(_ level: MemoryPressureLevel) {
        guard self.level != level else { return }
        self.level = level
        if level == .normal { normalSince = clock() }
        else { suspended = true; normalSince = nil }
    }
    mutating func permits(_ priority: DecodePriority) -> Bool {
        if suspended, level == .normal, let normalSince, clock() - normalSince >= recoveryDelay {
            suspended = false; self.normalSince = nil
        }
        return priority != .prefetch || !suspended
    }
}
