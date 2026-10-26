import Foundation
import PicseeCore

/// One event stream and one root lease per AccessRootID while any subscriber of that root is live.
/// Start/stop transitions of a root run strictly one after another, so a stream never outlives its lease.
public final class WatchHub: FolderWatching, @unchecked Sendable {
    public static let debounceMilliseconds = 200
    public static let maxWaitMilliseconds = 1000
    private let access: any AccessLeasing
    private let source: any FolderEventSource
    private let scheduler: any WatchScheduling
    private let lock = NSLock()
    private var roots: [AccessRootID: Root] = [:]

    /// Mutable state below is guarded by the hub's lock.
    private final class Subscriber: @unchecked Sendable {
        let id = UUID(), folder: URL, path: [String], recursive: Bool, onChange: @Sendable ([FolderChangeHint]) -> Void
        var pending: [FolderChangeHint] = [], timer: (any WatchCancellable)?, windowStart: Int?, epoch = 0
        init(folder: URL, recursive: Bool, onChange: @escaping @Sendable ([FolderChangeHint]) -> Void) {
            self.folder = folder; path = WatchHub.canonical(folder); self.recursive = recursive; self.onChange = onChange
        }
        /// `path` nil means mustRescan. Ancestors, the folder itself and its (direct, unless recursive) contents are relevant.
        func isRelevant(_ changed: [String]?) -> Bool {
            guard let changed else { return true }
            let shared = min(changed.count, path.count)
            return changed.prefix(shared) == path.prefix(shared) && (recursive || changed.count <= path.count + 1)
        }
    }
    private final class Root: @unchecked Sendable {
        var subscribers: [UUID: Subscriber] = [:]
        var stream: (any FolderEventStream)?
        var lease: AccessLease?
        var tail: Task<(any Error)?, Never>?, queued = 0
    }
    private struct Subscription: FolderWatchSubscription {
        let hub: WatchHub, root: Root, rootID: AccessRootID, id: UUID
        func cancel() async { await hub.remove(id, from: root, rootID) }
    }

    public init(access: any AccessLeasing, source: any FolderEventSource, scheduler: any WatchScheduling) {
        self.access = access; self.source = source; self.scheduler = scheduler
    }

    public func subscribe(rootID: AccessRootID, folder: URL, recursive: Bool,
        onChange: @escaping @Sendable ([FolderChangeHint]) -> Void) async throws -> any FolderWatchSubscription {
        let subscriber = Subscriber(folder: folder, recursive: recursive, onChange: onChange)
        let (root, transition) = lock.withLock { () -> (Root, Task<(any Error)?, Never>) in
            let root = roots[rootID] ?? Root()
            roots[rootID] = root
            root.subscribers[subscriber.id] = subscriber
            return (root, enqueue(root, rootID))
        }
        if let error = await transition.value {
            await remove(subscriber.id, from: root, rootID)
            throw error
        }
        return Subscription(hub: self, root: root, rootID: rootID, id: subscriber.id)
    }

    /// Delivers immediately, outside the lock; a pending debounce window is cancelled and folded into this one delivery.
    public func reconcileAll() {
        let due = lock.withLock { roots.values.flatMap(\.subscribers.values).map { s -> (Subscriber, [FolderChangeHint]) in
            s.timer?.cancel(); s.timer = nil; s.windowStart = nil; s.epoch += 1
            defer { s.pending = [] }
            return (s, s.pending + [.mustRescan])
        } }
        for (subscriber, hints) in due { subscriber.onChange(hints) }
    }

    private func remove(_ id: UUID, from root: Root, _ rootID: AccessRootID) async {
        let transition = lock.withLock { () -> Task<(any Error)?, Never>? in
            guard let subscriber = root.subscribers.removeValue(forKey: id) else { return nil }
            subscriber.timer?.cancel()
            return enqueue(root, rootID)
        }
        _ = await transition?.value
    }

    /// Caller holds the lock. Chains a transition after the root's previous one.
    private func enqueue(_ root: Root, _ rootID: AccessRootID) -> Task<(any Error)?, Never> {
        let previous = root.tail
        root.queued += 1
        let task = Task {
            _ = await previous?.value
            let error = await self.transition(root, rootID)
            self.lock.withLock { // An idle root with nothing queued leaves the map; its Subscriptions still hold it.
                root.queued -= 1
                if root.queued == 0, root.subscribers.isEmpty, root.stream == nil, self.roots[rootID] === root { self.roots[rootID] = nil }
            }
            return error
        }
        root.tail = task
        return task
    }

    private enum Step { case none, start(URL), stop(any FolderEventStream, AccessLease) }
    private func transition(_ root: Root, _ rootID: AccessRootID) async -> (any Error)? {
        let step = lock.withLock { () -> Step in
            if root.subscribers.isEmpty, let stream = root.stream, let lease = root.lease {
                root.stream = nil; root.lease = nil
                return .stop(stream, lease)
            }
            guard root.stream == nil, let folder = root.subscribers.values.first?.folder else { return .none }
            return .start(folder)
        }
        switch step {
        case .none: return nil
        case .stop(let stream, let lease):
            stream.stop()
            await access.release(lease)
            return nil
        case .start(let folder):
            let lease: AccessLease
            do { lease = try await access.acquire(.root(rootID, file: folder)) } catch { return error }
            guard lock.withLock({ !root.subscribers.isEmpty }) else { await access.release(lease); return nil }
            let stream = source.start(watching: lease.url) { [weak self] hints in self?.deliver(hints, to: root) }
            lock.withLock { root.stream = stream; root.lease = lease }
            return nil
        }
    }

    /// Path components after resolving symlinks on the deepest existing ancestor, so deleted paths
    /// spelled `/private/var/...` and `/var/...` compare equal.
    static func canonical(_ url: URL) -> [String] {
        var head = url.standardizedFileURL, tail: [String] = []
        while head.pathComponents.count > 1, !FileManager.default.fileExists(atPath: head.path) {
            tail.insert(head.lastPathComponent, at: 0); head.deleteLastPathComponent()
        }
        return head.resolvingSymlinksInPath().pathComponents + tail
    }

    private func deliver(_ hints: [FolderChangeHint], to root: Root) {
        let paths = hints.map { hint -> [String]? in if case .changed(let url) = hint { Self.canonical(url) } else { nil } }
        lock.withLock {
            let now = scheduler.nowMilliseconds
            for subscriber in root.subscribers.values {
                let relevant = zip(hints, paths).filter { subscriber.isRelevant($1) }.map(\.0)
                guard !relevant.isEmpty else { continue }
                subscriber.pending += relevant
                let start = subscriber.windowStart ?? now
                subscriber.windowStart = start; subscriber.epoch += 1
                subscriber.timer?.cancel()
                subscriber.timer = scheduler.schedule(afterMilliseconds: min(now + Self.debounceMilliseconds,
                    start + Self.maxWaitMilliseconds) - now) { [weak self, epoch = subscriber.epoch] in
                    self?.flush(subscriber, of: root, epoch: epoch)
                }
            }
        }
    }

    private func flush(_ subscriber: Subscriber, of root: Root, epoch: Int) {
        let hints = lock.withLock { () -> [FolderChangeHint] in
            guard subscriber.epoch == epoch, root.subscribers[subscriber.id] === subscriber else { return [] }
            subscriber.timer = nil; subscriber.windowStart = nil
            defer { subscriber.pending = [] }
            return subscriber.pending
        }
        if !hints.isEmpty { subscriber.onChange(hints) }
    }
}
