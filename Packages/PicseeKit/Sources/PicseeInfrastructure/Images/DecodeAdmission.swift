import Foundation
import PicseeCore

public enum DecodePriority: Int, Sendable { case prefetch, visible, current }
public struct DecodeConfiguration: Sendable {
    public let workers: Int
    public let visible: Int
    public let heavy: Int
    public let budget: Int
    public init(workers: Int = 3, visible: Int = 2, heavy: Int = 1,
                budget: Int = min(512 * 1024 * 1024, Int(Double(ProcessInfo.processInfo.physicalMemory) * 0.08))) {
        precondition(workers > 0 && visible >= 0 && heavy > 0 && budget > 0)
        self.workers = workers; self.visible = visible; self.heavy = heavy; self.budget = budget
    }
}

/// Execution seam: completion means the synchronous decoder has really returned.
public protocol DecodeExecuting: Sendable {
    func submit(_ work: @escaping @Sendable () -> Void)
}
public final class OperationDecodeExecutor: DecodeExecuting, Sendable {
    private let queue: OperationQueue
    public init(workers: Int) {
        queue = OperationQueue()
        queue.name = "io.github.anzchy.picsee.first-image-decode"
        queue.maxConcurrentOperationCount = workers
    }
    public func submit(_ work: @escaping @Sendable () -> Void) { queue.addOperation(work) }
}

public actor DecodeDelivery {
    private var result: Result<DecodedImage, Error>?
    private var waiters: [CheckedContinuation<DecodedImage, Error>] = []
    public init() { }
    public func value() async throws -> DecodedImage {
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { waiters.append($0) }
    }
    func finish(_ result: Result<DecodedImage, Error>) {
        precondition(self.result == nil)
        self.result = result
        let waiting = waiters; waiters.removeAll()
        for waiter in waiting { waiter.resume(with: result) }
    }
}
public struct DecodeSubscription: Sendable {
    public let id: UUID
    public let delivery: DecodeDelivery
    let admission: DecodeAdmission
    public func value() async throws -> DecodedImage { try await delivery.value() }
    public func cancel() async { await admission.cancel(id) }
    public func raisePriority(to priority: DecodePriority) async { await admission.raise(id, to: priority) }
}
public struct DecodeActivity: Sendable {
    public let running: Int
    public let nonCurrent: Int
    public let visible: Int
    public let heavy: Int
    public let reservedBytes: Int
    public let waiting: Int
}

public actor DecodeAdmission {
    private let configuration: DecodeConfiguration
    private let executor: any DecodeExecuting
    private let decoder: any ImageDecoding
    public init(configuration: DecodeConfiguration, executor: any DecodeExecuting, decoder: any ImageDecoding) {
        self.configuration = configuration; self.executor = executor; self.decoder = decoder
    }
    private struct Job {
        let id: UUID
        let request: ImageDecodeRequest
        let key: RenderKey
        let cost: Int
        let heavy: Bool
        var priority: DecodePriority
        var admitted: DecodePriority?
        var subscribers: [UUID: DecodeDelivery]
    }
    private var jobs: [UUID: Job] = [:]
    private var pending: [UUID] = []

    public func subscribe(_ request: ImageDecodeRequest, key: RenderKey, cost: Int, heavy: Bool,
                          priority: DecodePriority) -> DecodeSubscription {
        precondition(cost > 0 && cost <= configuration.budget)
        let id = UUID(), subscriber = UUID(), delivery = DecodeDelivery()
        jobs[id] = Job(id: id, request: request, key: key, cost: cost, heavy: heavy,
                       priority: priority, subscribers: [subscriber: delivery])
        pending.append(id)
        drain()
        return DecodeSubscription(id: subscriber, delivery: delivery, admission: self)
    }
    public func activity() -> DecodeActivity {
        let running = jobs.values.filter { $0.admitted != nil }
        return DecodeActivity(running: running.count,
            nonCurrent: running.filter { $0.admitted != .current }.count,
            visible: running.filter { $0.admitted == .visible }.count,
            heavy: running.filter { $0.heavy }.count,
            reservedBytes: running.reduce(0) { $0 + $1.cost }, waiting: pending.count)
    }
    private func drain() {
        // Stable priority order: FIFO among equal priorities. With finite foreground
        // demand eligible visible work progresses; prefetch has no starvation promise.
        while let id = pending.sorted(by: { jobs[$0]!.priority.rawValue > jobs[$1]!.priority.rawValue })
            .first(where: { id in
                let job = jobs[id]!, active = activity()
                return active.running < configuration.workers &&
                    (job.priority == .current || active.nonCurrent < configuration.workers - 1) &&
                    (job.priority != .visible || active.visible < configuration.visible) &&
                    (!job.heavy || active.heavy < configuration.heavy) &&
                    job.cost <= configuration.budget - active.reservedBytes
            }) {
            // No await between checking all resources and taking them.
            jobs[id]!.admitted = jobs[id]!.priority
            pending.removeAll { $0 == id }
            let request = jobs[id]!.request, decoder = decoder
            executor.submit {
                let result = Result { try decoder.decode(request) }
                Task { await self.finished(id, result: result) }
            }
        }
    }
    private func finished(_ id: UUID, result: Result<DecodedImage, Error>) async {
        let job = jobs.removeValue(forKey: id)!
        drain()
        for delivery in job.subscribers.values { await delivery.finish(result) }
    }
    func cancel(_ id: UUID) { }
    func raise(_ id: UUID, to priority: DecodePriority) {
        guard let jobID = jobs.first(where: { $0.value.subscribers[id] != nil })?.key else { return }
        jobs[jobID]!.priority = DecodePriority(rawValue: max(jobs[jobID]!.priority.rawValue, priority.rawValue))!
        drain()
    }
}
