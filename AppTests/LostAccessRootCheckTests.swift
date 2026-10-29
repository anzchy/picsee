import AppKit
import Testing
import PicseeCore
import PicseeApplication
@testable import PicseeInfrastructure

// Audit M1: reader failures and app activation must not each start a full
// root listing. Every root check enumerates mounts once, so the mount port
// counts root checks.
private final class RootCheckBookmarks: SecurityScope, BookmarkCoding, @unchecked Sendable {
    private let lock = NSLock()
    private var scopes = 0
    var activeScopes: Int { lock.withLock { scopes } }
    func start(_ url: URL) -> Bool { lock.withLock { scopes += 1 }; return true }
    func stop(_ url: URL) { lock.withLock { scopes -= 1 } }
    func isReadable(_ url: URL) -> Bool { true }
    func create(for url: URL) throws -> Data { Data(url.path.utf8) }
    func resolve(_ data: Data) throws -> ResolvedBookmark {
        ResolvedBookmark(url: URL(fileURLWithPath: String(decoding: data, as: UTF8.self)), stale: false)
    }
}
private actor RootCheckMounts: DiskMountPort {
    private let volumes = [AccessProbeVolume(uuid: "111", url: nil, name: "Disk")]
    private var connected = true
    func disconnect() { connected = false }
    private var pauseNext = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var enumerations = 0
    private(set) var paused = false
    func mountedVolumes() async -> [AccessProbeVolume] {
        enumerations += 1
        if pauseNext {
            pauseNext = false; paused = true
            await withCheckedContinuation { waiting.append($0) }
        }
        return connected ? volumes : []
    }
    func events() -> AsyncStream<DiskMountEvent> { AsyncStream { _ in } }
    func pauseEnumeration() { pauseNext = true; paused = false }
    func release() {
        paused = false
        let held = waiting; waiting = []
        for continuation in held { continuation.resume() }
    }
}
@MainActor private struct RootCheckFixture {
    let base: URL
    let root: AccessRootID
    let mounts: RootCheckMounts
    let monitor: AccessMonitor
    let codec: RootCheckBookmarks
    init(sourceExists: (@Sendable (URL, RootCheckBookmarks) throws -> Bool)? = nil) async throws {
        _ = NSApplication.shared
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let folder = base.appendingPathComponent("Root", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not an image".utf8).write(to: folder.appendingPathComponent("broken.jpg"))
        let codec = RootCheckBookmarks()
        self.codec = codec
        let files = try FileAccess(scope: codec, bookmarks: codec,
            store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "T229-root-check",
            bookmarkVolume: { _ in AccessProbeVolume(uuid: "111", url: nil, name: "Disk") },
            resolvedVolumeUUID: { _ in "111" })
        root = try await files.grant(folder: folder)
        mounts = RootCheckMounts()
        let services = AccessServices(files: files, recent: RecentFolderStore(url: base.appendingPathComponent("recent.json")),
            browser: FolderBrowser(), watch: WatchHub(access: files, source: FSEventSource(),
                scheduler: DispatchWatchScheduler()), mounts: mounts)
        if let sourceExists {
            monitor = AccessMonitor(files: files, mounts: mounts, sourceExists: { try sourceExists($0, codec) })
        } else {
            monitor = services.monitor
        }
        self.base = base
        await monitor.register(root)
        #expect(monitor.state.snapshot(for: root)?.availability == .readable)
    }
    func remove() { try? FileManager.default.removeItem(at: base) }
}
@MainActor private func rootCheckWait(_ predicate: @MainActor () async -> Bool) async throws {
    while !(await predicate()) { try await Task.sleep(for: .milliseconds(10)) }
    #expect(await predicate())
}

@MainActor @Test(.timeLimit(.minutes(3))) func t229FixDecodeFailuresNeverStartRootChecks() async throws {
    let f = try await RootCheckFixture(); defer { f.remove() }
    let before = await f.mounts.enumerations
    let stamp = f.monitor.state.stamp(for: f.root)
    let failures: [any Error] = [ImageLoadError(.corruptImage), ImageLoadError(.unsupportedFormat),
                                 ImageDecodeError.unreadableImage, ImageDecodeError.budgetExceeded]
    for _ in 0..<5 {
        for failure in failures { await f.monitor.reportReadFailure(f.root, from: stamp, error: failure) }
    }
    #expect(await f.mounts.enumerations == before)
    #expect(f.monitor.state.snapshot(for: f.root)?.availability == .readable)
}

@MainActor @Test(.timeLimit(.minutes(3))) func t229FixConcurrentAccessFailuresShareOneRootCheck() async throws {
    let f = try await RootCheckFixture(); defer { f.remove() }
    let before = await f.mounts.enumerations
    let stamp = f.monitor.state.stamp(for: f.root)
    await f.mounts.pauseEnumeration()
    let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
    let reports = (0..<20).map { _ in
        Task { @MainActor in await f.monitor.reportReadFailure(f.root, from: stamp, error: denied) }
    }
    try await rootCheckWait { await f.mounts.paused }
    // Negative observation only after the first root check is known to be held.
    try await Task.sleep(for: .milliseconds(200))
    await f.mounts.release()
    for report in reports { await report.value }
    #expect(await f.mounts.enumerations - before == 1)
    #expect(f.monitor.state.snapshot(for: f.root)?.availability == .readable)
}

@MainActor @Test(.timeLimit(.minutes(3))) func t229FixRepeatedActivationChecksEachRootOnce() async throws {
    let f = try await RootCheckFixture(); defer { f.remove() }
    let before = await f.mounts.enumerations
    var completed = false
    let readiness = f.monitor.observeReadiness { if $0 == f.root { completed = true } }
    defer { f.monitor.removeReadinessObserver(readiness) }
    await f.mounts.pauseEnumeration()
    for _ in 0..<5 {
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApplication.shared)
    }
    try await rootCheckWait { await f.mounts.paused }
    // Observe duplicate activation while the positive check remains held.
    try await Task.sleep(for: .milliseconds(200))
    await f.mounts.release()
    try await rootCheckWait { completed }
    #expect(await f.mounts.enumerations - before == 1)
    #expect(f.monitor.state.snapshot(for: f.root)?.availability == .readable)
}

// Audit M4: the wake path shares the foreground recheck.
@MainActor @Test(.timeLimit(.minutes(3))) func t229FixWakeRechecksSavedRootsOnce() async throws {
    let f = try await RootCheckFixture(); defer { f.remove() }
    let before = await f.mounts.enumerations
    var completed = false
    let readiness = f.monitor.observeReadiness { if $0 == f.root { completed = true } }
    defer { f.monitor.removeReadinessObserver(readiness) }
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
    try await rootCheckWait { completed }
    // After completion, watch for an unwanted duplicate root check.
    try await Task.sleep(for: .milliseconds(200))
    #expect(await f.mounts.enumerations - before == 1)
    #expect(f.monitor.state.snapshot(for: f.root)?.availability == .readable)
}

// Audit opus M7 (round 2): a missing source is access evidence, not content.
// ENOENT maps to sourceChanged; a decoder failure on a file that no longer
// exists can't be told from damage. Each starts exactly one root check; a
// damaged file that is still there starts none.
@MainActor @Test(.timeLimit(.minutes(3))) func t229Fix2MissingSourceFailuresStartOneRootCheck() async throws {
    let f = try await RootCheckFixture(); defer { f.remove() }
    let stamp = f.monitor.state.stamp(for: f.root)
    let gone = f.base.appendingPathComponent("Root/gone.jpg")
    let enoent = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
    let missing: [(any Error, URL?)] = [(ImageLoadError(.sourceChanged), nil), (ImageLoadError(.sourceChanged), gone),
        (ImageLoadError(.corruptImage), gone), (ImageLoadError(.unsupportedFormat), gone),
        (ImageDecodeError.unreadableImage, gone), (enoent, gone)]
    for (failure, file) in missing {
        let before = await f.mounts.enumerations
        await f.monitor.reportReadFailure(f.root, from: stamp, error: failure, file: file)
        #expect(await f.mounts.enumerations - before == 1, "\(failure)")
    }
    let broken = f.base.appendingPathComponent("Root/broken.jpg")
    let before = await f.mounts.enumerations
    for failure: any Error in [ImageLoadError(.corruptImage), ImageLoadError(.unsupportedFormat), ImageDecodeError.unreadableImage,
                               ImageLoadError(.resourceLimit), ImageLoadError(.cancelled)] {
        await f.monitor.reportReadFailure(f.root, from: stamp, error: failure, file: broken)
    }
    #expect(await f.mounts.enumerations == before)
    #expect(f.monitor.state.snapshot(for: f.root)?.availability == .readable)
}

// A stalled filesystem boundary must not occupy the UI actor. A wrong MainActor
// call returns immediately so ranOnMain fails without deadlocking that actor.
private final class RootCheckProbeGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var released = false
    private var total = 0
    private var blocked = 0
    private var onMain = false
    private var unscoped = false
    var calls: Int { condition.lock(); defer { condition.unlock() }; return total }
    var waiting: Bool { condition.lock(); defer { condition.unlock() }; return blocked > 0 && !released }
    var ranOnMain: Bool { condition.lock(); defer { condition.unlock() }; return onMain }
    var ranUnscoped: Bool { condition.lock(); defer { condition.unlock() }; return unscoped }
    func probe(_ url: URL, codec: RootCheckBookmarks) -> Bool {
        condition.lock(); defer { condition.unlock() }
        total += 1; blocked += 1
        onMain = onMain || Thread.isMainThread
        unscoped = unscoped || codec.activeScopes == 0
        // Keep a correct background probe held until explicit release.
        // The test already asserts !ranOnMain; never block the UI on a regression.
        while !released && !Thread.isMainThread { condition.wait() }
        blocked -= 1
        return false
    }
    func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
}

@MainActor @Test(.timeLimit(.minutes(3)), arguments: [Int(EPERM), Int(EACCES), Int(EIO)])
func t229Fix3DeniedOrIndeterminateSourceIsNotMissing(_ code: Int) async throws {
    let f = try await RootCheckFixture(sourceExists: { _, _ in throw NSError(domain: NSPOSIXErrorDomain, code: code) })
    defer { f.remove() }
    let broken = f.base.appendingPathComponent("Root/broken.jpg")
    #expect(FileManager.default.fileExists(atPath: broken.path))
    let before = await f.mounts.enumerations
    let snapshot = f.monitor.state.snapshot(for: f.root)
    for failure: any Error in [ImageLoadError(.corruptImage), ImageLoadError(.unsupportedFormat), ImageDecodeError.unreadableImage] {
        await f.monitor.reportReadFailure(f.root, from: f.monitor.state.stamp(for: f.root), error: failure, file: broken)
    }
    #expect(await f.mounts.enumerations == before)
    #expect(f.monitor.state.snapshot(for: f.root) == snapshot)
    #expect(f.codec.activeScopes == 0)
}

@MainActor @Test(.timeLimit(.minutes(3)), arguments: [false, true])
func t229Fix3BlockedSourceProbeIsScopedResponsiveAndRejectsLateResult(_ stale: Bool) async throws {
    let gate = RootCheckProbeGate()
    let f = try await RootCheckFixture(sourceExists: { gate.probe($0, codec: $1) })
    defer { gate.release(); f.remove() }
    let stamp = f.monitor.state.stamp(for: f.root)
    let before = await f.mounts.enumerations
    let report = Task { @MainActor in
        await f.monitor.reportReadFailure(f.root, from: stamp, error: ImageLoadError(.corruptImage),
                                         file: f.base.appendingPathComponent("Root/broken.jpg"))
    }
    try await rootCheckWait { gate.calls > 0 }
    // Reaching here on MainActor while the probe waits is the heartbeat.
    #expect(gate.waiting)
    #expect(!gate.ranOnMain)
    #expect(!gate.ranUnscoped)
    #expect(f.codec.activeScopes > 0)
    if stale { f.monitor.state.reauthorize(f.root, volumeUUID: "111") }
    else { report.cancel() }
    let expected = f.monitor.state.snapshot(for: f.root)
    await f.mounts.disconnect()
    gate.release()
    await report.value
    #expect(f.monitor.state.snapshot(for: f.root) == expected)
    #expect(await f.mounts.enumerations == before)
    #expect(f.codec.activeScopes == 0)
}

@MainActor @Test(.timeLimit(.minutes(3))) func t229Fix3StaleAndCancelledReportsNeverProbe() async throws {
    let gate = RootCheckProbeGate(); gate.release()
    let f = try await RootCheckFixture(sourceExists: { gate.probe($0, codec: $1) })
    defer { f.remove() }
    let stamp = f.monitor.state.stamp(for: f.root)
    f.monitor.state.reauthorize(f.root, volumeUUID: "111")
    let file = f.base.appendingPathComponent("Root/broken.jpg")
    await f.monitor.reportReadFailure(f.root, from: stamp, error: ImageLoadError(.corruptImage), file: file)
    let cancelled = Task { @MainActor in
        withUnsafeCurrentTask { $0?.cancel() }
        await f.monitor.reportReadFailure(f.root, from: f.monitor.state.stamp(for: f.root),
                                         error: ImageLoadError(.corruptImage), file: file)
    }
    await cancelled.value
    #expect(gate.calls == 0)
    #expect(f.monitor.state.snapshot(for: f.root)?.availability == .readable)
}

@MainActor @Test(.timeLimit(.minutes(3))) func t229Fix3ConcurrentSourceReportsCoalesceAndCancellationIsPerCaller() async throws {
    let gate = RootCheckProbeGate()
    let f = try await RootCheckFixture(sourceExists: { gate.probe($0, codec: $1) })
    defer { gate.release(); f.remove(); Task { await f.mounts.release() } }
    let stamp = f.monitor.state.stamp(for: f.root)
    let before = await f.mounts.enumerations
    await f.mounts.pauseEnumeration()
    let reports = (0..<12).map { _ in Task { @MainActor in
        await f.monitor.reportReadFailure(f.root, from: stamp, error: ImageLoadError(.corruptImage),
                                         file: f.base.appendingPathComponent("Root/broken.jpg"))
    } }
    try await rootCheckWait { gate.calls > 0 }
    // The probe is held; this window only observes unwanted duplicate probes.
    try await Task.sleep(for: .milliseconds(100))
    #expect(gate.waiting)
    #expect(gate.calls == 1)
    reports[0].cancel()
    gate.release()
    try await rootCheckWait { await f.mounts.paused }
    await f.mounts.disconnect()
    await f.mounts.release()
    for report in reports { await report.value }
    #expect(await f.mounts.enumerations - before == 1)
    #expect(f.monitor.state.snapshot(for: f.root)?.availability == .lost(.diskNotConnected))
    #expect(f.codec.activeScopes == 0)
}

@MainActor @Test(.timeLimit(.minutes(3))) func t229Fix3ContentProbeDoesNotSwallowOtherSourcesOrAccessEvidence() async throws {
    let gate = RootCheckProbeGate()
    let f = try await RootCheckFixture(sourceExists: { url, codec in
        if url.lastPathComponent == "broken.jpg" { _ = gate.probe(url, codec: codec); return true }
        return false
    })
    defer { gate.release(); f.remove() }
    let stamp = f.monitor.state.stamp(for: f.root)
    let before = await f.mounts.enumerations
    let present = Task { @MainActor in
        await f.monitor.reportReadFailure(f.root, from: stamp, error: ImageLoadError(.corruptImage),
                                         file: f.base.appendingPathComponent("Root/broken.jpg"))
    }
    try await rootCheckWait { gate.calls > 0 }
    #expect(gate.waiting)
    // A different missing source and explicit access evidence still reach root checks.
    await f.monitor.reportReadFailure(f.root, from: stamp, error: ImageLoadError(.unsupportedFormat),
                                     file: f.base.appendingPathComponent("Root/gone.jpg"))
    await f.monitor.reportReadFailure(f.root, from: stamp, error: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)))
    #expect(await f.mounts.enumerations - before == 2)
    gate.release()
    await present.value
    #expect(f.monitor.state.snapshot(for: f.root)?.availability == .readable)
    #expect(f.codec.activeScopes == 0)
}
