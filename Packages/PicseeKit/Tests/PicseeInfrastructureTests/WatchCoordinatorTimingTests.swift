import Foundation
import Testing
import PicseeCore
import PicseeApplication
@testable import PicseeInfrastructure

@Test(.timeLimit(.minutes(2))) @MainActor func watchedCoordinatorUpdatesWithinTwoSecondsOfQuiescenceOnOneFakeClock() async throws {
    // Filesystem event → hub debounce → coordinator hop → silent rescan → snapshot, timed on the hub's fake clock.
    // A rescan takes no fake time here, so this bounds the pipeline's waiting, not a large folder's scan (未测).
    let w = try await WatchedCoordinator(files: ["F/a.png"]); defer { w.f.remove() }
    let c = w.coordinator
    try await c.begin(folder: w.url("F"), rootID: w.rootID).value
    let step = 10, writes = Array(stride(from: 0, to: 3000, by: 100)), lastWrite = writes[writes.count - 1]
    var updates: [(at: Int, names: [String])] = [], shown = w.names()
    for t in stride(from: 0, through: lastWrite + 3000, by: step) {
        w.f.clock.advance(to: t)
        if writes.contains(t) {
            let name = "F/n\(t / 100).png"
            w.write(name)
            w.f.source.emit([.changed(w.url(name))], on: w.f.url("root"))
        }
        // Let a flush hop to the MainActor, then let any refresh it began finish before fake time moves on.
        await w.turns(5)
        #expect(await mainPoll { w.trace.begins.count == w.trace.ends.count }, "t=\(t) refresh did not settle")
        if w.names() != shown { shown = w.names(); updates.append((t, shown)) }
    }
    let during = updates.filter { $0.at <= lastWrite }
    // A continuous burst still updates at least once per max wait (here at 1000 and 2000, then 3000 after it).
    #expect(during.count >= lastWrite / WatchHub.maxWaitMilliseconds, "updates during the burst: \(updates.map(\.at))")
    #expect((updates.first?.at ?? .max) <= WatchHub.maxWaitMilliseconds + step, "first update \(updates.map(\.at))")
    for (earlier, later) in zip(updates, updates.dropFirst()) {
        #expect(later.at - earlier.at <= WatchHub.maxWaitMilliseconds + step, "gap \(earlier.at)→\(later.at)")
    }
    let final = try #require(updates.last)
    #expect(final.names.contains("n\(lastWrite / 100).png"))
    #expect(final.at <= lastWrite + 2000, "final update at \(final.at), last write \(lastWrite)")
    #expect(final.at <= lastWrite + WatchHub.debounceMilliseconds + step, "final update at \(final.at)")
    #expect(Set(c.sourceSnapshot?.entries.map(\.itemID) ?? []) == (try await w.freshScan(recursive: false)))
}
