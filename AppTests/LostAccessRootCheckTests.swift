import AppKit
import Testing
import PicseeCore
import PicseeApplication
@testable import PicseeInfrastructure

// Audit M1: reader failures and app activation must not each start a full
// root listing. Every root check enumerates mounts once, so the mount port
// counts root checks.
private final class RootCheckBookmarks: SecurityScope, BookmarkCoding, @unchecked Sendable {
    func start(_ url: URL) -> Bool { true }
    func stop(_ url: URL) {}
    func isReadable(_ url: URL) -> Bool { true }
    func create(for url: URL) throws -> Data { Data(url.path.utf8) }
    func resolve(_ data: Data) throws -> ResolvedBookmark {
        ResolvedBookmark(url: URL(fileURLWithPath: String(decoding: data, as: UTF8.self)), stale: false)
    }
}
private actor RootCheckMounts: DiskMountPort {
    private let volumes = [AccessProbeVolume(uuid: "111", url: nil, name: "Disk")]
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
        return volumes
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
    init() async throws {
        _ = NSApplication.shared
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let folder = base.appendingPathComponent("Root", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not an image".utf8).write(to: folder.appendingPathComponent("broken.jpg"))
        let codec = RootCheckBookmarks()
        let files = try FileAccess(scope: codec, bookmarks: codec,
            store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "T229-root-check",
            bookmarkVolume: { _ in AccessProbeVolume(uuid: "111", url: nil, name: "Disk") },
            resolvedVolumeUUID: { _ in "111" })
        root = try await files.grant(folder: folder)
        mounts = RootCheckMounts()
        let services = AccessServices(files: files, recent: RecentFolderStore(url: base.appendingPathComponent("recent.json")),
            browser: FolderBrowser(), watch: WatchHub(access: files, source: FSEventSource(),
                scheduler: DispatchWatchScheduler()), mounts: mounts)
        monitor = services.monitor
        self.base = base
        await monitor.register(root)
        #expect(monitor.state.snapshot(for: root)?.availability == .readable)
    }
    func remove() { try? FileManager.default.removeItem(at: base) }
}
@MainActor private func rootCheckWait(_ predicate: @MainActor () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(8)
    while !(await predicate()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(await predicate())
}

@MainActor @Test func t229FixDecodeFailuresNeverStartRootChecks() async throws {
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

@MainActor @Test func t229FixConcurrentAccessFailuresShareOneRootCheck() async throws {
    let f = try await RootCheckFixture(); defer { f.remove() }
    let before = await f.mounts.enumerations
    let stamp = f.monitor.state.stamp(for: f.root)
    await f.mounts.pauseEnumeration()
    let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
    let reports = (0..<20).map { _ in
        Task { @MainActor in await f.monitor.reportReadFailure(f.root, from: stamp, error: denied) }
    }
    try await rootCheckWait { await f.mounts.paused }
    try await Task.sleep(for: .milliseconds(200))
    await f.mounts.release()
    for report in reports { await report.value }
    #expect(await f.mounts.enumerations - before == 1)
    #expect(f.monitor.state.snapshot(for: f.root)?.availability == .readable)
}

@MainActor @Test func t229FixRepeatedActivationChecksEachRootOnce() async throws {
    let f = try await RootCheckFixture(); defer { f.remove() }
    let before = await f.mounts.enumerations
    await f.mounts.pauseEnumeration()
    for _ in 0..<5 {
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApplication.shared)
    }
    try await rootCheckWait { await f.mounts.paused }
    try await Task.sleep(for: .milliseconds(200))
    await f.mounts.release()
    try await Task.sleep(for: .milliseconds(300))
    #expect(await f.mounts.enumerations - before == 1)
    #expect(f.monitor.state.snapshot(for: f.root)?.availability == .readable)
}
