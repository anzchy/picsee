import Foundation
import PicseeCore

public enum AccessLossCause: Equatable, Sendable {
    case diskNotConnected, unknown
}

public enum AccessAvailability: Equatable, Sendable {
    case readable
    case lost(AccessLossCause)
}

public struct AccessRootSnapshot: Equatable, Sendable {
    public let volumeUUID: String?
    public let counter: UInt64
    public let availability: AccessAvailability
    public init(volumeUUID: String?, counter: UInt64, availability: AccessAvailability) {
        self.volumeUUID = volumeUUID
        self.counter = counter
        self.availability = availability
    }
}

public struct AccessWorkStamp: Hashable, Sendable {
    public let rootID: AccessRootID
    public let counter: UInt64
    public init(rootID: AccessRootID, counter: UInt64) {
        self.rootID = rootID
        self.counter = counter
    }
}

public struct AccessRecoveryAttempt: Equatable, Sendable {
    public let rootID: AccessRootID
    public let counter: UInt64
    public let volumeUUID: String?
    public init(rootID: AccessRootID, counter: UInt64, volumeUUID: String?) {
        self.rootID = rootID
        self.counter = counter
        self.volumeUUID = volumeUUID
    }
}

public enum AccessStateChange: Equatable, Sendable {
    case lost(AccessRootID, counter: UInt64)
    case recovered(AccessRootID, counter: UInt64)
}

/// Shared across windows; OS events and access readers feed this owner.
@MainActor public final class AccessState {
    private struct Entry {
        var volumeUUID: String?
        var counter: UInt64 = 0
        var availability: AccessAvailability = .readable
        var mounted = true
    }

    private var entries: [AccessRootID: Entry] = [:]
    private var retiredCounters: [AccessRootID: UInt64] = [:]
    private var observers: [UUID: @MainActor (AccessStateChange) -> Void] = [:]

    public init() {}
    public func register(_ rootID: AccessRootID, volumeUUID: String?) {
        if var existing = entries[rootID] {
            // Explicitly replacing a grant revokes every old work stamp too.
            if existing.volumeUUID != volumeUUID {
                existing.counter += 1
                existing.volumeUUID = volumeUUID
                existing.availability = .readable
                existing.mounted = true
                entries[rootID] = existing
            }
        } else {
            var entry = Entry(volumeUUID: volumeUUID)
            if let retired = retiredCounters[rootID] { entry.counter = retired + 1 }
            entries[rootID] = entry
        }
    }
    public func forget(_ rootID: AccessRootID) {
        if let entry = entries.removeValue(forKey: rootID) { retiredCounters[rootID] = entry.counter }
    }
    public func snapshot(for rootID: AccessRootID) -> AccessRootSnapshot? {
        guard let entry = entries[rootID] else { return nil }
        return AccessRootSnapshot(volumeUUID: entry.volumeUUID, counter: entry.counter,
                                  availability: entry.availability)
    }
    public func stamp(for rootID: AccessRootID) -> AccessWorkStamp {
        AccessWorkStamp(rootID: rootID, counter: entries[rootID]?.counter ?? UInt64.max)
    }
    public func mayDeliver(_ stamp: AccessWorkStamp) -> Bool {
        guard stamp.counter != UInt64.max, let entry = entries[stamp.rootID] else { return false }
        return entry.counter == stamp.counter && entry.availability == .readable
    }
    @discardableResult public func observe(_ observer: @escaping @MainActor (AccessStateChange) -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }
    public func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
    private func publish(_ change: AccessStateChange) {
        for observer in Array(observers.values) { observer(change) }
    }
    public func diskUnmounted(volumeUUID: String) {
        for (id, var entry) in entries where entry.volumeUUID == volumeUUID && entry.mounted {
            entry.mounted = false
            entry.counter += 1
            entry.availability = .lost(.diskNotConnected)
            entries[id] = entry
            publish(.lost(id, counter: entry.counter))
        }
    }
    public func diskMounted(volumeUUID: String) -> [AccessRecoveryAttempt] {
        var attempts: [AccessRecoveryAttempt] = []
        for (id, var entry) in entries where entry.volumeUUID == volumeUUID && !entry.mounted {
            entry.mounted = true
            entries[id] = entry
            if case .lost = entry.availability {
                attempts.append(AccessRecoveryAttempt(rootID: id, counter: entry.counter, volumeUUID: volumeUUID))
            }
        }
        return attempts
    }
    /// Foreground/wake and access failures may request another real verification.
    public func recoveryAttempt(for rootID: AccessRootID) -> AccessRecoveryAttempt? {
        guard let entry = entries[rootID], entry.mounted,
              case .lost = entry.availability else { return nil }
        return AccessRecoveryAttempt(rootID: rootID, counter: entry.counter, volumeUUID: entry.volumeUUID)
    }
    @discardableResult public func reportRootFailure(_ rootID: AccessRootID, cause: AccessLossCause,
                                                       from stamp: AccessWorkStamp) -> Bool {
        guard mayDeliver(stamp), var entry = entries[rootID] else { return false }
        entry.counter += 1
        entry.availability = .lost(cause)
        if cause == .diskNotConnected { entry.mounted = false }
        entries[rootID] = entry
        publish(.lost(rootID, counter: entry.counter))
        return true
    }
    @discardableResult public func completeRecovery(_ attempt: AccessRecoveryAttempt, verified: Bool) -> Bool {
        guard verified, var entry = entries[attempt.rootID], entry.mounted,
              entry.counter == attempt.counter, entry.volumeUUID == attempt.volumeUUID,
              case .lost = entry.availability else { return false }
        entry.availability = .readable
        entries[attempt.rootID] = entry
        publish(.recovered(attempt.rootID, counter: entry.counter))
        return true
    }
}
