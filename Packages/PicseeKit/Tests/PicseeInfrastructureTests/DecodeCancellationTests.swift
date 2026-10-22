import Foundation
import Testing
import PicseeCore
import PicseeInfrastructure

func expectCancelled(_ subscription: DecodeSubscription) async {
    do { _ = try await subscription.value(); Issue.record("cancelled subscription succeeded") }
    catch { #expect(error is CancellationError) }
}

@Test func cancellationKeepsRunningReservationsUntilActualReturn() async throws {
    let executor = ControlledExecutor()
    let admission = DecodeAdmission(configuration: DecodeConfiguration(workers: 1, budget: 4), executor: executor, decoder: TinyDecoder())
    let running = await admission.subscribe(tinyRequest, key: decodeKey(10), cost: 4, heavy: true, priority: .current)
    let waiting = await admission.subscribe(tinyRequest, key: decodeKey(11), cost: 4, heavy: true, priority: .current)
    await waiting.cancel(); await waiting.cancel()
    #expect(await admission.activity().waiting == 0)
    await running.cancel(); await running.cancel()
    #expect(await admission.activity().reservedBytes == 4)
    #expect(await admission.activity().running == 1)
    executor.runFirst()
    // Do not await the stub's never-completing cancelled queued delivery on RED.
    if await admission.activity().waiting == 0 { await expectCancelled(waiting) }
    do { _ = try await running.value(); Issue.record("cancelled decode delivered success") }
    catch { #expect(error is CancellationError) }
    #expect(await admission.activity().reservedBytes == 0)
}

final class BlockingDecoder: ImageDecoding, @unchecked Sendable {
    let started: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation
    let gate = DispatchSemaphore(value: 0)
    init() { (started, signal) = AsyncStream.makeStream() }
    func decode(_ request: ImageDecodeRequest) throws -> DecodedImage {
        signal.yield(())
        gate.wait()
        return try TinyDecoder().decode(request)
    }
}

@Test func realQueueCancellationBalancesThreePointsWithoutSleep() async throws {
    let decoder = BlockingDecoder()
    let admission = DecodeAdmission(configuration: DecodeConfiguration(workers: 1, budget: 4),
        executor: OperationDecodeExecutor(workers: 1), decoder: decoder)
    let running = await admission.subscribe(tinyRequest, key: decodeKey(20), cost: 4, heavy: true, priority: .current)
    var starts = decoder.started.makeAsyncIterator()
    _ = await starts.next()
    let queued = await admission.subscribe(tinyRequest, key: decodeKey(21), cost: 4, heavy: true, priority: .current)
    await queued.cancel()
    await running.cancel()
    #expect(await admission.activity().reservedBytes == 4)
    #expect(await admission.activity().waiting == 0)
    decoder.gate.signal()
    if await admission.activity().waiting == 0 { await expectCancelled(queued) }
    await expectCancelled(running)
    #expect(await admission.activity().running == 0)
}
