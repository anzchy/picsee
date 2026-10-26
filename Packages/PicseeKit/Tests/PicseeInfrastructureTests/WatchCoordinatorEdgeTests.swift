import Foundation
import Testing
import PicseeCore
import PicseeApplication
@testable import PicseeInfrastructure

@Test @MainActor func watchedCoordinatorKeepsSnapshotWhenRefreshFailsAndFollowsAliasDeletion() async throws {
    // A failed silent refresh keeps the last complete snapshot, the image and the watch; the next hint recovers.
    let w = try await WatchedCoordinator(files: ["F/a.png", "F/b.png"]); defer { w.f.remove() }
    let c = w.coordinator
    try await c.begin(folder: w.url("F"), rootID: w.rootID, input: w.url("F/a.png")).value
    w.host.reset()
    let prior = try #require(c.sourceSnapshot)
    let failures = w.trace.ends.filter { $0.outcome == .failed }.count
    w.delete("F"); w.changed(["F"])
    #expect(await mainPoll { w.trace.ends.filter { $0.outcome == .failed }.count == failures + 1 })
    #expect(c.sourceSnapshot == prior)
    #expect(c.failure == nil)
    #expect(c.currentURL?.lastPathComponent == "a.png")
    #expect(w.host.opened.isEmpty && w.host.cleared == 0 && w.host.didStart == 0)
    #expect(w.f.source.active == 1)
    w.write("F/a.png"); w.write("F/c.png"); w.changed(["F/c.png"])
    #expect(await mainPoll { w.names() == ["a.png", "c.png"] })
    #expect(c.currentURL?.lastPathComponent == "a.png")
    #expect(w.host.opened.isEmpty)

    // Deleting the alias being viewed keeps the same image under the URL that still exists.
    let alias = try await WatchedCoordinator(files: ["F/b.png", "F/c.png"]); defer { alias.f.remove() }
    try FileManager.default.createSymbolicLink(at: alias.url("F/a.png"), withDestinationURL: alias.url("F/c.png"))
    let viewer = alias.coordinator
    try await viewer.begin(folder: alias.url("F"), rootID: alias.rootID, input: alias.url("F/a.png")).value
    #expect(viewer.currentItemID == alias.id("F/c.png"))
    alias.host.reset()
    let g0 = alias.generation
    alias.delete("F/a.png"); alias.changed(["F/a.png"])
    #expect(await mainPoll { alias.generation > g0 })
    #expect(viewer.currentItemID == alias.id("F/c.png"))
    #expect(viewer.currentURL?.lastPathComponent == "c.png")
    #expect(alias.host.opened.map(\.lastPathComponent) == ["c.png"])
}
