import AppKit
import Testing
import PicseeCore
import PicseeApplication
@testable import PicseeInfrastructure
import PicseeMacUI

private final class RecoveryBookmarks: SecurityScope, BookmarkCoding, @unchecked Sendable {
    private let lock = NSLock()
    private var identities: [Data: FileResourceIdentity] = [:]
    private var locations: [Data: URL] = [:]
    private var failures: Set<String> = []
    func start(_ url: URL) -> Bool { true }
    func stop(_ url: URL) {}
    func isReadable(_ url: URL) -> Bool { true }
    func create(for url: URL) throws -> Data {
        let identity = try URLIdentityResourceReader().identity(for: url)
        // A bookmark is an object-specific token. A new directory at the old
        // spelling must not inherit the prior token's moved location/identity.
        let token = Data("\(UUID().uuidString)|\(url.path)".utf8)
        lock.withLock { identities[token] = identity; locations[token] = url }
        return token
    }
    func resolve(_ data: Data) throws -> ResolvedBookmark {
        try lock.withLock {
            guard let url = locations[data], !failures.contains(url.path) else {
                throw NSError(domain: "T229RecoveryResolution", code: 1)
            }
            return ResolvedBookmark(url: url, stale: false)
        }
    }
    func identity(_ data: Data) -> FileResourceIdentity? { lock.withLock { identities[data] } }
    func relocate(_ old: URL, to new: URL) {
        lock.withLock {
            for (token, url) in locations where url.standardizedFileURL == old.standardizedFileURL {
                locations[token] = new
            }
        }
    }
    func fail(_ root: URL, _ failed: Bool) {
        lock.withLock { if failed { _ = failures.insert(root.path) } else { _ = failures.remove(root.path) } }
    }
}

private actor RecoveryMounts: DiskMountPort {
    private var volumes = [AccessProbeVolume(uuid: "111", url: nil, name: "Disk"), AccessProbeVolume(uuid: "222", url: nil, name: "Other")]
    private var continuation: AsyncStream<DiskMountEvent>.Continuation?
    private var pauseNext = false
    private var waiting: [(CheckedContinuation<[AccessProbeVolume], Never>, [AccessProbeVolume])] = []
    private(set) var paused = false
    func mountedVolumes() async -> [AccessProbeVolume] {
        // Capture before suspension: a late success must still lose to a newer eject.
        let captured = volumes
        if pauseNext {
            pauseNext = false; paused = true
            return await withCheckedContinuation { waiting.append(($0, captured)) }
        }
        return captured
    }
    func events() -> AsyncStream<DiskMountEvent> { AsyncStream { continuation = $0 } }
    func emit(_ event: DiskMountEvent) {
        switch event {
        case .mounted(let volume): volumes.removeAll { $0.uuid == volume.uuid }; volumes.append(volume)
        case .unmounted(let volume): volumes.removeAll { $0.uuid == volume.uuid }
        }
        continuation?.yield(event)
    }
    func pauseEnumeration() { pauseNext = true; paused = false }
    func release() {
        pauseNext = false; paused = false
        let held = waiting; waiting = []
        for (continuation, captured) in held { continuation.resume(returning: captured) }
    }
}

/// Gates only the real enumerator's resource-values I/O; neither App state nor scan results are fabricated.
private final class RecoveryReadGate: FileIdentityResourceReading, @unchecked Sendable {
    private let condition = NSCondition()
    private var prefix: String?
    private var blocked = false
    private var mountGeneration = 0
    func nextMount() { condition.lock(); mountGeneration += 1; condition.unlock() }
    func identity(for fileURL: URL) throws -> FileResourceIdentity? {
        let raw = try URLIdentityResourceReader().identity(for: fileURL)
        condition.lock(); let generation = mountGeneration; condition.unlock()
        return raw.map { FileResourceIdentity(volumeUUID: $0.volumeUUID,
            fileIdentifier: generation == 0 ? $0.fileIdentifier : "dev\(generation):\($0.fileIdentifier)") }
    }
    var isBlocked: Bool { condition.lock(); defer { condition.unlock() }; return blocked }
    func arm(_ folder: URL) { condition.lock(); prefix = folder.path + "/"; blocked = false; condition.unlock() }
    func release() { condition.lock(); prefix = nil; blocked = false; condition.broadcast(); condition.unlock() }
    func read(_ url: URL) throws -> URLResourceValues {
        condition.lock()
        if let prefix, url.path.hasPrefix(prefix) {
            blocked = true
            // The test releases this gate explicitly, including in deferred cleanup.
            // CI scheduling delay must not release the held scan early.
            while blocked { condition.wait() }
            blocked = false
        }
        condition.unlock()
        return try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey, .contentTypeKey,
            .contentModificationDateKey, .fileSizeKey, .volumeUUIDStringKey, .fileIdentifierKey])
    }
}

private final class RecoveryWatchSource: FolderEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private var live: [UUID: URL] = [:]
    private var hints: [UUID: @Sendable ([FolderChangeHint]) -> Void] = [:]
    var activeURLs: [URL] { lock.withLock { Array(live.values) } }
    private final class Stream: FolderEventStream, @unchecked Sendable {
        let stopAction: @Sendable () -> Void
        init(_ stop: @escaping @Sendable () -> Void) { stopAction = stop }
        func stop() { stopAction() }
    }
    func start(watching url: URL, onHints: @escaping @Sendable ([FolderChangeHint]) -> Void) throws -> any FolderEventStream {
        let id = UUID()
        lock.withLock { live[id] = url }
        lock.withLock { hints[id] = onHints }
        return Stream { [self] in _ = lock.withLock { live.removeValue(forKey: id) } }
    }
    func emit(_ hint: FolderChangeHint, root: URL) {
        let callbacks = lock.withLock { live.filter { $0.value == root }.keys.compactMap { hints[$0] } }
        for callback in callbacks { callback([hint]) }
    }
}

extension FileAccess {
    /// Runs `body` as one turn of the actor, so no lease can resolve a root between its steps.
    fileprivate func runIsolated(_ body: @Sendable () throws -> Void) throws { try body() }
}

@MainActor private final class RecoveryMotion: ReduceMotionSource {
    var reduceMotion = true
    var onChange: (@MainActor () -> Void)?
}

@MainActor private func recoveryWait(_ predicate: @MainActor () -> Bool) async throws {
    while !predicate() { try await Task.sleep(for: .milliseconds(10)) }
    #expect(predicate())
}
@MainActor private func recoveryWaitAsync(_ predicate: @MainActor () async -> Bool) async throws {
    while !(await predicate()) { try await Task.sleep(for: .milliseconds(10)) }
    #expect(await predicate())
}
@MainActor private func recoveryShell(_ controller: CanvasWindowController) throws -> GridShellView {
    try #require(controller.window?.contentView?.subviews.compactMap { $0 as? GridShellView }.first)
}
@MainActor private func recoveryGrid(_ controller: CanvasWindowController) throws -> GridBrowserView {
    try #require(try recoveryShell(controller).mainContent.subviews.compactMap { $0 as? GridBrowserView }.first)
}
@MainActor private func recoveryPage(_ controller: CanvasWindowController) -> LostAccessStateView? {
    controller.window?.contentView?.subviews.compactMap { $0 as? GridShellView }.first?
        .mainContent.subviews.compactMap { $0 as? LostAccessStateView }.first { !$0.isHiddenOrHasHiddenAncestor }
}

@MainActor private struct RecoveryFixture {
    let base: URL
    let a: URL
    let b: URL
    let childOne: URL
    let childTwo: URL
    let rootA: AccessRootID
    let rootB: AccessRootID
    let bookmarks: RecoveryBookmarks
    let mounts: RecoveryMounts
    let gate: RecoveryReadGate
    let watchSource: RecoveryWatchSource
    let services: AccessServices
    init(diagnostics: AccessDiagnostics = AccessDiagnostics()) async throws {
        _ = NSApplication.shared
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let a = base.appendingPathComponent("RootA", isDirectory: true), b = base.appendingPathComponent("RootB", isDirectory: true)
        let one = a.appendingPathComponent("One", isDirectory: true), two = a.appendingPathComponent("Two", isDirectory: true)
        for folder in [one, two, b] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TestAssets/synthetic/landscape-3x2.png")
        for folder in [one, two] {
            try fm.copyItem(at: fixture, to: folder.appendingPathComponent("one.png"))
            try fm.copyItem(at: fixture, to: folder.appendingPathComponent("two.jpg"))
        }
        try fm.copyItem(at: fixture, to: a.appendingPathComponent("root.png"))
        try fm.copyItem(at: fixture, to: b.appendingPathComponent("other.png"))
        let bookmarks = RecoveryBookmarks()
        let files = try FileAccess(scope: bookmarks, bookmarks: bookmarks,
            store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "T229-recovery",
            diagnostics: diagnostics,
            bookmarkVolume: { data in AccessProbeVolume(uuid: String(decoding: data, as: UTF8.self).hasSuffix("RootB") ? "222" : "111", url: nil, name: "Disk") },
            resolvedVolumeUUID: { url in url.path.contains("RootB") ? "222" : "111" },
            bookmarkIdentity: { bookmarks.identity($0) })
        let rootA = try await files.grant(folder: a), rootB = try await files.grant(folder: b)
        let mounts = RecoveryMounts(), gate = RecoveryReadGate(), source = RecoveryWatchSource()
        self.base = base; self.a = a; self.b = b; childOne = one; childTwo = two
        self.rootA = rootA; self.rootB = rootB; self.bookmarks = bookmarks; self.mounts = mounts; self.gate = gate; watchSource = source
        services = AccessServices(files: files, recent: RecentFolderStore(url: base.appendingPathComponent("recent.json")),
            browser: FolderBrowser(readValues: { try gate.read($0) }, resourceReader: gate),
            watch: WatchHub(access: files, source: source, scheduler: DispatchWatchScheduler()), mounts: mounts, selectionScope: bookmarks)
    }
    func controller() -> CanvasWindowController {
        CanvasWindowController(pipeline: ImageIOPipeline(), preferencesStore: InMemoryDisplayPreferencesStore(),
            accessServices: Task { services }, motionPolicy: MotionPolicy(source: RecoveryMotion()))
    }
    func eject() async { await mounts.emit(.unmounted(AccessProbeVolume(uuid: "111", url: nil, name: "Disk"))) }
    func mount() async { await mounts.emit(.mounted(AccessProbeVolume(uuid: "111", url: nil, name: "Disk"))) }
    func ready(_ controller: CanvasWindowController, folder: URL, count: Int? = nil) async throws {
        let grid = try recoveryGrid(controller)
        try await recoveryWait {
            controller.session.folderScan?.snapshot?.isComplete == true &&
            controller.session.folderScan?.snapshot?.version.folder == folder && !grid.isHiddenOrHasHiddenAncestor &&
            (count.map { grid.displayedItemIDs.count == $0 } ?? !grid.displayedItemIDs.isEmpty)
        }
    }
    /// A real bookmark resolves to the moved folder at once. Moving the folder and relocating the fake bookmark
    /// in one FileAccess turn keeps a lease (a thumbnail or metadata read still in flight) from resolving the
    /// old path after it is gone, which drops the root as needing reconnection (#290).
    func moveRoot(to destination: URL) async throws {
        let source = a, bookmarks = bookmarks
        try await services.files.runIsolated {
            try FileManager.default.moveItem(at: source, to: destination)
            bookmarks.relocate(source, to: destination)
        }
    }
    func remove() { gate.release(); try? FileManager.default.removeItem(at: base) }
}

@MainActor @Test(.timeLimit(.minutes(3))) func t229RecoveryRestoresTwoIndependentPositionsAfterRootMoves() async throws {
    let f = try await RecoveryFixture(); defer { f.remove() }
    let viewer = f.controller(), gridWindow = f.controller()
    defer { viewer.window?.close(); gridWindow.window?.close() }
    viewer.browseRecoveredFolder(f.childOne, rootID: f.rootA)
    gridWindow.browseRecoveredFolder(f.childTwo, rootID: f.rootA)
    try await f.ready(viewer, folder: f.childOne, count: 2)
    try await f.ready(gridWindow, folder: f.childTwo, count: 2)
    let viewerConditions = FolderViewConditions(sort: .name, direction: .descending, selectedExtensions: ["png"])
    let gridConditions = FolderViewConditions(sort: .size, direction: .ascending, selectedExtensions: ["jpg"])
    viewer.session.setFolderConditions(viewerConditions)
    gridWindow.session.setFolderConditions(gridConditions)
    try await f.ready(viewer, folder: f.childOne, count: 1)
    try await f.ready(gridWindow, folder: f.childTwo, count: 1)
    let image = try #require(viewer.session.folderScan?.snapshot?.navigationEntries.first)
    let selected = try #require(gridWindow.session.folderScan?.snapshot?.navigationEntries.first)
    gridWindow.session.focus(selected.itemID)
    viewer.session.focus(image.itemID)
    #expect(viewer.route(.enter, from: .key))
    try await recoveryWait { viewer.session.mode == .viewing && viewer.hasImage && viewer.session.imageLoader.presented != nil }
    var announcements: [String] = []
    viewer.accessAnnouncementObserver = { announcements.append($0) }
    gridWindow.accessAnnouncementObserver = { announcements.append($0) }
    await f.eject()
    try await recoveryWait { recoveryPage(viewer) != nil && recoveryPage(gridWindow) != nil }
    try await recoveryWait { announcements.count == 1 }
    let moved = f.base.appendingPathComponent("RemountedRoot", isDirectory: true)
    try await f.moveRoot(to: moved)
    await f.mount()
    let movedImage = moved.appendingPathComponent("One/one.png")
    do {
    // FolderBrowser keeps the enumerator's physical /private/var spelling (pinned by ExternalCurrentFileTests).
    let movedImage = URL(fileURLWithPath: movedImage.path.hasPrefix("/var/") ? "/private" + movedImage.path : movedImage.path)
    try await recoveryWait { viewer.waitingAccessPosition == nil && viewer.hasImage && viewer.session.imageLoader.fileURL == movedImage }
    try await f.ready(gridWindow, folder: moved.appendingPathComponent("Two"), count: 1)
    #expect(viewer.session.mode == .viewing && gridWindow.session.mode == .browsing)
    #expect(viewer.session.folderConditions == viewerConditions)
    #expect(gridWindow.session.folderConditions == gridConditions)
    #expect(gridWindow.session.selection.currentItemID == selected.itemID)
    #expect(viewer.window?.representedURL == movedImage)
    #expect(gridWindow.window?.representedURL == moved.appendingPathComponent("Two"))
    #expect(f.watchSource.activeURLs.contains(moved))
    try await recoveryWait { announcements.count == 2 }
    #expect(announcements.count == 2)
    let later = moved.appendingPathComponent("Two/later.jpg")
    try FileManager.default.copyItem(at: movedImage, to: later)
    f.watchSource.emit(.changed(later), root: moved)
    try await f.ready(gridWindow, folder: moved.appendingPathComponent("Two"), count: 2)
    #expect(gridWindow.session.selection.currentItemID == selected.itemID)
    }
}

private enum RecoveryMissing: String, CaseIterable, Sendable { case childGone, itemGone, childReplaced, itemReplaced }
@MainActor @Test(.timeLimit(.minutes(3)), arguments: RecoveryMissing.allCases)
private func t229RecoveryFallsBackToRootGridWhenOriginalPositionIsGone(_ missing: RecoveryMissing) async throws {
    let f = try await RecoveryFixture(); defer { f.remove() }
    let controller = f.controller(); defer { controller.window?.close() }
    controller.browseRecoveredFolder(f.childOne, rootID: f.rootA)
    try await f.ready(controller, folder: f.childOne, count: 2)
    let image = try #require(controller.session.folderScan?.snapshot?.entries.first { $0.url.lastPathComponent == "one.png" })
    controller.session.focus(image.itemID)
    #expect(controller.route(.enter, from: .key))
    try await recoveryWait { controller.session.mode == .viewing && controller.hasImage }
    await f.eject()
    try await recoveryWait { recoveryPage(controller) != nil }
    let fm = FileManager.default
    switch missing {
    case .childGone: try fm.removeItem(at: f.childOne)
    case .itemGone: try fm.removeItem(at: image.url)
    case .childReplaced:
        try fm.moveItem(at: f.childOne, to: f.base.appendingPathComponent("original-child"))
        try fm.createDirectory(at: f.childOne, withIntermediateDirectories: true)
        try fm.copyItem(at: f.childTwo.appendingPathComponent("one.png"), to: image.url)
    case .itemReplaced:
        try fm.moveItem(at: image.url, to: f.base.appendingPathComponent("original-image.png"))
        try fm.copyItem(at: f.childTwo.appendingPathComponent("one.png"), to: image.url)
    }
    await f.mount()
    try await f.ready(controller, folder: f.a, count: 1)
    #expect(controller.waitingAccessPosition == nil && recoveryPage(controller) == nil)
    #expect(controller.session.mode == .browsing && !controller.hasImage)
    #expect(controller.session.imageLoader.presented == nil)
    #expect(controller.window?.representedURL == f.a)
    #expect(controller.session.folderScan?.snapshot?.entries.first?.url.lastPathComponent == "root.png")
}

@MainActor @Test(.timeLimit(.minutes(3))) func t229RecoveryFailedRootVerificationStaysUnknownThenRetriesSavedBookmark() async throws {
    let f = try await RecoveryFixture(); defer { f.remove() }
    let controller = f.controller(); defer { controller.window?.close() }
    controller.browseRecoveredFolder(f.childOne, rootID: f.rootA)
    try await f.ready(controller, folder: f.childOne)
    let saved = try #require(await f.services.files.records().first { $0.id == f.rootA }).bookmark
    await f.eject()
    try await recoveryWait { recoveryPage(controller) != nil }
    f.bookmarks.fail(f.a, true)
    await f.mount()
    try await recoveryWait { controller.accessLossCause == .unknown }
    #expect(f.services.monitor.state.permit(for: f.rootA) == nil)
    #expect(!controller.hasImage && controller.session.imageLoader.presented == nil)
    #expect(recoveryPage(controller)?.buttons.count == 2)
    #expect(try recoveryGrid(controller).displayedItemIDs.isEmpty)
    f.bookmarks.fail(f.a, false)
    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApplication.shared)
    try await f.ready(controller, folder: f.childOne, count: 2)
    #expect(controller.waitingAccessPosition == nil)
    #expect(await f.services.files.records().first { $0.id == f.rootA }?.bookmark == saved)
}

private struct RecoveryInterleaving: Sendable {
    let duringScan: Bool
    let secondEject: Bool
    static let all = [false, true].flatMap { duringScan in [false, true].map { Self(duringScan: duringScan, secondEject: $0) } }
}
@MainActor @Test(.timeLimit(.minutes(3)), arguments: RecoveryInterleaving.all)
private func t229RecoveryGeneratedNavigationAndSecondEjectInterleavings(_ trace: RecoveryInterleaving) async throws {
    let f = try await RecoveryFixture(); defer { f.remove() }
    let first = f.controller(), second = f.controller()
    defer { first.window?.close(); second.window?.close(); f.gate.release(); Task { await f.mounts.release() } }
    first.browseRecoveredFolder(f.childOne, rootID: f.rootA)
    second.browseRecoveredFolder(f.childTwo, rootID: f.rootA)
    try await f.ready(first, folder: f.childOne)
    try await f.ready(second, folder: f.childTwo)
    await f.eject()
    try await recoveryWait { recoveryPage(first) != nil && recoveryPage(second) != nil }
    let lostCounter = try #require(f.services.monitor.state.snapshot(for: f.rootA)?.counter)
    if trace.duringScan { f.gate.arm(f.a) } else { await f.mounts.pauseEnumeration() }
    await f.mount()
    if trace.duringScan { try await recoveryWait { f.gate.isBlocked } }
    else { try await recoveryWaitAsync { await f.mounts.paused } }
    #expect(recoveryPage(first) != nil && recoveryPage(second) != nil)
    #expect(!first.hasImage && !second.hasImage)
    #expect(try recoveryGrid(first).displayedItemIDs.isEmpty)
    #expect(try recoveryGrid(second).displayedItemIDs.isEmpty)
    if trace.duringScan { #expect(f.watchSource.activeURLs.contains(f.a)) }
    first.browseRecoveredFolder(f.b, rootID: f.rootB)
    if trace.secondEject {
        await f.eject()
        try await recoveryWait { f.services.monitor.state.snapshot(for: f.rootA)?.counter == lostCounter + 1 }
    }
    f.gate.release()
    await f.mounts.release()
    try await f.ready(first, folder: f.b, count: 1)
    #expect(first.waitingAccessPosition == nil && first.window?.representedURL == f.b)
    if trace.secondEject {
        #expect(recoveryPage(second) != nil)
        #expect(!second.hasImage && second.window?.representedURL == nil)
        await f.mount()
    }
    try await f.ready(second, folder: f.childTwo, count: 2)
    #expect(second.waitingAccessPosition == nil)
    #expect(second.session.folderScan?.snapshot?.version.rootID == f.rootA)
    #expect(first.session.folderScan?.snapshot?.version.rootID == f.rootB)
    #expect(first.window?.representedURL == f.b)
}

@MainActor @Test(.timeLimit(.minutes(3))) func t229RecoveryCancelReadingAnotherRootRestoresWaitingPosition() async throws {
    let f = try await RecoveryFixture(); defer { f.remove() }
    let controller = f.controller(); defer { controller.window?.close(); f.gate.release() }
    var announcements: [String] = []
    controller.accessAnnouncementObserver = { announcements.append($0) }
    controller.browseRecoveredFolder(f.childOne, rootID: f.rootA)
    try await f.ready(controller, folder: f.childOne)
    await f.eject()
    try await recoveryWait { recoveryPage(controller) != nil }
    let loss = try #require(announcements.first)
    let position = try #require(controller.waitingAccessPosition)
    f.gate.arm(f.b)
    controller.browseRecoveredFolder(f.b, rootID: f.rootB)
    let state = try #require(controller.window?.contentView?.subviews.compactMap { $0 as? ViewerStateHost }.first)
    let cancel = try #require(state.buttons.first)
    cancel.performClick(nil)
    #expect(controller.waitingAccessPosition?.rootID == position.rootID)
    #expect(controller.waitingAccessPosition?.folderURL == position.folderURL)
    #expect(controller.waitingAccessPosition?.counter == position.counter)
    #expect(recoveryPage(controller) != nil && controller.window?.representedURL == nil)
    #expect(!controller.hasImage)
    f.gate.release()
    await f.mount()
    try await f.ready(controller, folder: f.childOne, count: 2)
    #expect(announcements == [loss, "Folder Access Restored"])
}

@MainActor @Test(.timeLimit(.minutes(3))) func t229RecoveryAnnouncementBudgetRestartsAfterNavigationAway() async throws {
    let f = try await RecoveryFixture(); defer { f.remove() }
    let controller = f.controller(); defer { controller.window?.close() }
    var announcements: [String] = []
    controller.accessAnnouncementObserver = { announcements.append($0) }
    controller.browseRecoveredFolder(f.childOne, rootID: f.rootA)
    try await f.ready(controller, folder: f.childOne)
    await f.eject()
    try await recoveryWait { recoveryPage(controller) != nil && announcements.count == 1 }
    controller.browseRecoveredFolder(f.b, rootID: f.rootB)
    try await f.ready(controller, folder: f.b, count: 1)
    await f.mount()
    try await recoveryWait { f.services.monitor.state.snapshot(for: f.rootA)?.availability == .readable }
    #expect(announcements.count == 1)
    controller.browseRecoveredFolder(f.childOne, rootID: f.rootA)
    try await f.ready(controller, folder: f.childOne)
    await f.eject()
    try await recoveryWait { recoveryPage(controller) != nil && announcements.count == 2 }
    await f.eject()
    #expect(announcements.count == 2)
    await f.mount()
    try await f.ready(controller, folder: f.childOne)
    try await recoveryWait { announcements.count == 3 }
    #expect(announcements.count == 3)
}

// Audit M6: the root is readable again, but one window's own folder cannot be
// listed. That window falls back to the root grid instead of staying on page 26,
// and loss is not announced again after "Folder Access Restored".
@MainActor @Test(.timeLimit(.minutes(3))) func t229FixPerWindowRestoreFailureFallsBackToRootGridWithoutReannouncingLoss() async throws {
    let f = try await RecoveryFixture()
    let viewer = f.controller(), gridWindow = f.controller()
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: f.childTwo.path)
        viewer.window?.close(); gridWindow.window?.close(); f.remove()
    }
    viewer.browseRecoveredFolder(f.childOne, rootID: f.rootA)
    gridWindow.browseRecoveredFolder(f.childTwo, rootID: f.rootA)
    try await f.ready(viewer, folder: f.childOne, count: 2)
    try await f.ready(gridWindow, folder: f.childTwo, count: 2)
    var announcements: [String] = []
    viewer.accessAnnouncementObserver = { announcements.append($0) }
    gridWindow.accessAnnouncementObserver = { announcements.append($0) }
    await f.eject()
    try await recoveryWait { recoveryPage(viewer) != nil && recoveryPage(gridWindow) != nil && announcements.count == 1 }
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: f.childTwo.path)
    await f.mount()
    try await f.ready(viewer, folder: f.childOne, count: 2)
    try await recoveryWait { gridWindow.waitingAccessPosition == nil && recoveryPage(gridWindow) == nil }
    try await f.ready(gridWindow, folder: f.a)
    #expect(gridWindow.window?.representedURL == f.a)
    #expect(gridWindow.session.folderScan?.snapshot?.version.rootID == f.rootA)
    #expect(f.services.monitor.state.snapshot(for: f.rootA)?.availability == .readable)
    try await recoveryWait { announcements.count == 2 }
    // Recovery has announced; observe only unwanted repeat announcements.
    try await Task.sleep(for: .milliseconds(300))
    #expect(announcements.count == 2)
    #expect(announcements.filter { $0 == announcements.first }.count == 1)
}

// Audit gpt F1 (round 2): the recovery identity follows the grid the window
// shows. (a) The root moves while readable; a later eject and remount restore
// the moved child and its Current Item, not the root grid.
@MainActor @Test(.timeLimit(.minutes(3))) func t229Fix2RecoveryFollowsRootMovedWhileReadable() async throws {
    let f = try await RecoveryFixture(); defer { f.remove() }
    let controller = f.controller(); defer { controller.window?.close() }
    controller.browseRecoveredFolder(f.childOne, rootID: f.rootA)
    try await f.ready(controller, folder: f.childOne, count: 2)
    let selected = try #require(controller.session.folderScan?.snapshot?.navigationEntries.last)
    controller.session.focus(selected.itemID)
    let moved = f.base.appendingPathComponent("MovedRoot", isDirectory: true)
    let movedChild = moved.appendingPathComponent("One", isDirectory: true)
    try await f.moveRoot(to: moved)
    for watched in [f.a, f.childOne] { f.watchSource.emit(.mustRescan, root: watched) }
    try await f.ready(controller, folder: movedChild, count: 2)
    try await recoveryWait { controller.window?.representedURL == movedChild }
    await f.eject()
    try await recoveryWait { recoveryPage(controller) != nil }
    await f.mount()
    try await f.ready(controller, folder: movedChild, count: 2)
    #expect(controller.waitingAccessPosition == nil)
    #expect(controller.session.selection.currentItemID == selected.itemID)
    #expect(controller.window?.representedURL == movedChild)
}

// (b) Cancel Reading returns to the previous complete grid; the abandoned scan
// must not keep the recovery identity.
@MainActor @Test(.timeLimit(.minutes(3))) func t229Fix2CancelReadingBackToReadableGridKeepsItsRecoveryIdentity() async throws {
    let f = try await RecoveryFixture(); defer { f.remove() }
    let controller = f.controller(); defer { controller.window?.close(); f.gate.release() }
    controller.browseRecoveredFolder(f.childOne, rootID: f.rootA)
    try await f.ready(controller, folder: f.childOne, count: 2)
    let selected = try #require(controller.session.folderScan?.snapshot?.navigationEntries.last)
    controller.session.focus(selected.itemID)
    // Cancel Reading restores the grid view's Current Item, so select it there too, as a user would.
    try recoveryGrid(controller).activate(currentItemID: selected.itemID)
    f.gate.arm(f.b)
    controller.browseRecoveredFolder(f.b, rootID: f.rootB)
    try await recoveryWait { f.gate.isBlocked }
    let state = try #require(controller.window?.contentView?.subviews.compactMap { $0 as? ViewerStateHost }.first)
    try #require(state.buttons.first).performClick(nil)
    f.gate.release()
    try await f.ready(controller, folder: f.childOne, count: 2)
    #expect(controller.window?.representedURL == f.childOne)
    await f.eject()
    try await recoveryWait { recoveryPage(controller) != nil }
    await f.mount()
    try await f.ready(controller, folder: f.childOne, count: 2)
    #expect(controller.waitingAccessPosition == nil)
    #expect(controller.session.selection.currentItemID == selected.itemID)
    #expect(controller.window?.representedURL == f.childOne)
}

// Audit gpt F2 (round 2): one loss episode announces loss once and recovery
// once. Window B leaves Choose Another Folder open while A recovers; cancelling
// B's panel afterwards must not announce loss again, nor a second recovery.
@MainActor @Test(.timeLimit(.minutes(3))) func t229Fix2PanelLeftOpenDuringRecoveryAnnouncesLossAndRecoveryOnce() async throws {
    let f = try await RecoveryFixture()
    let first = f.controller(), second = f.controller()
    let window = try #require(second.window)
    defer {
        if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .cancel) }
        first.window?.close(); window.close(); f.remove()
    }
    second.showWindow(nil)
    first.browseRecoveredFolder(f.childOne, rootID: f.rootA)
    second.browseRecoveredFolder(f.childTwo, rootID: f.rootA)
    try await f.ready(first, folder: f.childOne, count: 2)
    try await f.ready(second, folder: f.childTwo, count: 2)
    var announcements: [String] = []
    first.accessAnnouncementObserver = { announcements.append($0) }
    second.accessAnnouncementObserver = { announcements.append($0) }
    await f.eject()
    try await recoveryWait { recoveryPage(first) != nil && recoveryPage(second) != nil && announcements.count == 1 }
    let page = try #require(recoveryPage(second))
    page.chooseOtherButton.performClick(nil)
    try await recoveryWait { window.attachedSheet is NSOpenPanel }
    await f.mount()
    try await f.ready(first, folder: f.childOne, count: 2)
    try await recoveryWait { announcements.count == 2 }
    #expect(recoveryPage(second) != nil)
    let panel = try #require(window.attachedSheet as? NSOpenPanel)
    window.endSheet(panel, returnCode: .cancel)
    try await recoveryWait { window.attachedSheet == nil }
    try await f.ready(second, folder: f.childTwo, count: 2)
    try await recoveryWait { announcements.count == 2 }
    // Both windows completed; cancelling the panel must not announce again.
    try await Task.sleep(for: .milliseconds(300))
    let loss = try #require(announcements.first)
    #expect(announcements == [loss, String(localized: "Folder Access Restored")])
}


private final class RecoveryDiagnosticTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var messages: [String] { lock.withLock { stored } }
    var diagnostics: AccessDiagnostics { AccessDiagnostics { [self] message, _ in lock.withLock { stored.append(message) } } }
}

@MainActor @Test(.timeLimit(.minutes(3))) func t229DiagnosticsAppRefusalThenRecoveryPublishesTruthfulState() async throws {
    let trace = RecoveryDiagnosticTrace(), f = try await RecoveryFixture(diagnostics: trace.diagnostics)
    defer { f.remove() }
    await f.services.monitor.start()
    await f.eject()
    try await recoveryWait { f.services.monitor.state.snapshot(for: f.rootA)?.availability == .lost(.diskNotConnected) }
    f.bookmarks.fail(f.a, true)
    await f.mount()
    try await recoveryWait { f.services.monitor.state.snapshot(for: f.rootA)?.availability == .lost(.unknown) }
    #expect(trace.messages.contains { $0.contains("AccessRootLost") && $0.contains("cause=diskNotConnected") })
    #expect(trace.messages.contains { $0.contains("AccessRecovery") && $0.contains("outcome=refused") })
    #expect(!trace.messages.contains { $0.contains("AccessRecovery outcome=published") })
    f.bookmarks.fail(f.a, false)
    await f.eject()
    try await recoveryWait { f.services.monitor.state.snapshot(for: f.rootA)?.availability == .lost(.diskNotConnected) }
    await f.mount()
    try await recoveryWait { f.services.monitor.state.snapshot(for: f.rootA)?.availability == .readable }
    #expect(trace.messages.contains { $0.contains("AccessRecovery outcome=published") })
    #expect(!trace.messages.joined().contains(f.base.path))
}


@MainActor @Test(.timeLimit(.minutes(3))) func t229DiagnosticsSupersededRecoveryRefusesPublication() async throws {
    let trace = RecoveryDiagnosticTrace(), f = try await RecoveryFixture(diagnostics: trace.diagnostics)
    defer { f.remove(); Task { await f.mounts.release() } }
    await f.services.monitor.start()
    await f.eject()
    try await recoveryWait { f.services.monitor.state.snapshot(for: f.rootA)?.availability == .lost(.diskNotConnected) }
    let lossCounter = try #require(f.services.monitor.state.snapshot(for: f.rootA)?.counter)
    await f.mounts.pauseEnumeration()
    await f.mount()
    try await recoveryWaitAsync { await f.mounts.paused }
    await f.eject()
    try await recoveryWait { f.services.monitor.state.snapshot(for: f.rootA)?.availability == .lost(.diskNotConnected) }
    try await recoveryWait { f.services.monitor.state.snapshot(for: f.rootA)?.counter == lossCounter + 1 }
    await f.mounts.release()
    try await recoveryWait { trace.messages.contains { $0.contains("AccessRecovery outcome=refused") } }
    #expect(!trace.messages.contains { $0.contains("AccessRecovery outcome=published") })
    #expect(f.services.monitor.state.snapshot(for: f.rootA)?.availability == .lost(.diskNotConnected))
    await f.mount()
    try await recoveryWait { f.services.monitor.state.snapshot(for: f.rootA)?.availability == .readable }
    #expect(trace.messages.contains { $0.contains("AccessRecovery outcome=published") })
}

@MainActor @Test(.timeLimit(.minutes(3))) func t229R2GridRestoresNonFirstCurrentItemAfterMountTokenChanges() async throws {
    let f = try await RecoveryFixture(); defer { f.remove() }
    try FileManager.default.copyItem(at: f.childOne.appendingPathComponent("one.png"),
        to: f.childOne.appendingPathComponent("three.png"))
    let controller = f.controller(); defer { controller.window?.close() }
    controller.browseRecoveredFolder(f.childOne, rootID: f.rootA)
    try await f.ready(controller, folder: f.childOne, count: 3)
    let conditions = FolderViewConditions(sort: .name, direction: .descending, selectedExtensions: ["png"])
    controller.session.setFolderConditions(conditions)
    try await f.ready(controller, folder: f.childOne, count: 2)
    let before = try #require(controller.session.folderScan?.snapshot?.navigationEntries.last)
    controller.session.focus(before.itemID)
    try recoveryGrid(controller).activate(currentItemID: before.itemID)
    await f.eject()
    try await recoveryWait { recoveryPage(controller) != nil }
    f.gate.nextMount()
    await f.mount()
    try await recoveryWait { controller.waitingAccessPosition == nil }
    let snapshot = try #require(controller.session.folderScan?.snapshot)
    let current = snapshot.entries.first { $0.itemID == controller.session.selection.currentItemID }
    #expect(snapshot.version.folder.standardizedFileURL.path == f.childOne.standardizedFileURL.path)
    #expect(current?.url.standardizedFileURL.path == before.url.standardizedFileURL.path)
    #expect(current?.resourceIdentifier != before.resourceIdentifier)
    #expect(controller.session.folderConditions == conditions)
    await f.eject()
    try await recoveryWait { recoveryPage(controller) != nil }
    f.gate.nextMount()
    await f.mount()
    try await recoveryWait { controller.waitingAccessPosition == nil }
    let repeated = controller.session.folderScan?.snapshot?.entries.first { $0.itemID == controller.session.selection.currentItemID }
    #expect(repeated?.url.standardizedFileURL.path == before.url.standardizedFileURL.path)
}


// #230: these tests supply the system panel's result to the production
// continuation. The real chooser configuration/cancel is exercised separately.
@MainActor private func t230OpenPositionBeforeLoss(_ f: RecoveryFixture, _ controller: CanvasWindowController) async throws -> ItemID {
    controller.browseRecoveredFolder(f.childOne, rootID: f.rootA)
    try await f.ready(controller, folder: f.childOne, count: 2)
    controller.session.setFolderConditions(.init(sort: .name, direction: .descending, selectedExtensions: ["png", "jpg"]))
    try await f.ready(controller, folder: f.childOne, count: 2)
    let entries = try #require(controller.session.folderScan?.snapshot?.navigationEntries)
    let chosen = try #require(entries.last)
    controller.session.focus(chosen.itemID)
    #expect(controller.route(.enter, from: .key))
    try await recoveryWait { controller.session.mode == .viewing && controller.hasImage && controller.session.imageLoader.presented != nil }
    return chosen.itemID
}
@MainActor private func t230DenyRoot(_ f: RecoveryFixture, _ controller: CanvasWindowController) async throws {
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: f.a.path)
    await f.services.monitor.reportReadFailure(f.rootA, from: f.services.monitor.state.stamp(for: f.rootA),
        error: NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError))
    try await recoveryWait { recoveryPage(controller) != nil }
    #expect(f.services.monitor.state.snapshot(for: f.rootA)?.availability == .lost(.accessExpired))
    #expect(!controller.hasImage && controller.session.mode == .browsing)
    #expect(controller.window?.representedURL == nil && controller.window?.title == "Picsee")
    #expect(controller.inspector.name == nil && controller.inspector.value == .unknown)
}

@MainActor @Test(.timeLimit(.minutes(3)), arguments: [false, true])
func t230SameIdentityReselectRestoresOriginalPosition(_ renamed: Bool) async throws {
    let f = try await RecoveryFixture(); defer { f.remove() }
    let controller = f.controller(); defer { controller.window?.close() }
    let item = try await t230OpenPositionBeforeLoss(f, controller)
    let conditions = controller.session.folderConditions
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.a.path) }
    try await t230DenyRoot(f, controller)
    #expect(recoveryPage(controller)?.titleLabel.stringValue == String(localized: "Access Has Expired"))
    #expect(recoveryPage(controller)?.buttons.count == 1)
    #expect(controller.waitingAccessPosition?.folderReference != nil)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.a.path)
    var selected = f.a
    if renamed {
        selected = f.base.appendingPathComponent("ReselectedMovedRoot")
        try await f.moveRoot(to: selected)
    }
    controller.completeAccessFolderSelection(selected, reselect: true)
    try await recoveryWait { controller.waitingAccessPosition == nil && controller.session.folderScan?.snapshot?.isComplete == true }
    #expect(controller.session.folderScan?.snapshot?.version.folder == selected.appendingPathComponent("One"))
    #expect(controller.session.currentItemID == item)
    #expect(controller.session.folderConditions == conditions)
    #expect(controller.session.mode == .browsing && !controller.hasImage)
    #expect(await f.services.files.records().count == 2)
    #expect(f.services.monitor.state.snapshot(for: f.rootA)?.availability == .readable)
}

@MainActor @Test(.timeLimit(.minutes(3)), arguments: ["other", "replacement", "missing-proof"])
func t230DifferentIdentitySelectionOpensNormallyPreservingLostRoot(_ kind: String) async throws {
    let f = try await RecoveryFixture(); defer { f.remove() }
    let controller = f.controller(); defer { controller.window?.close() }
    if kind == "missing-proof" {
        await f.services.monitor.register(f.rootA)
        _ = f.services.monitor.state.reportRootFailure(f.rootA, cause: .accessExpired, from: f.services.monitor.state.stamp(for: f.rootA))
        controller.requestFolderReconnection(rootID: f.rootA, lastKnownFolder: f.a, displayName: "RootA")
        try await recoveryWait { recoveryPage(controller) != nil }
        #expect(controller.waitingAccessPosition?.folderReference == nil)
    } else {
        _ = try await t230OpenPositionBeforeLoss(f, controller)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.a.path) }
        try await t230DenyRoot(f, controller)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.a.path)
    }
    let original = try #require(await f.services.files.records().first { $0.id == f.rootA })
    let lost = f.services.monitor.state.snapshot(for: f.rootA)
    var selected = f.b
    if kind == "replacement" {
        let moved = f.base.appendingPathComponent("OriginalStillLost")
        try await f.moveRoot(to: moved)
        try FileManager.default.createDirectory(at: f.a, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: f.b.appendingPathComponent("other.png"), to: f.a.appendingPathComponent("new.png"))
        selected = f.a
    } else if kind == "missing-proof" { selected = f.a }
    controller.completeAccessFolderSelection(selected, reselect: true)
    try await recoveryWait { controller.waitingAccessPosition == nil && controller.session.folderScan?.snapshot?.isComplete == true }
    #expect(controller.session.folderScan?.snapshot?.version.folder == selected)
    #expect(controller.session.folderScan?.snapshot?.version.rootID != f.rootA)
    #expect(await f.services.files.records().first { $0.id == f.rootA } == original)
    #expect(f.services.monitor.state.snapshot(for: f.rootA) == lost)
    #expect(await f.services.files.records().count == (kind == "other" ? 2 : 3))
    #expect(controller.window?.attachedSheet == nil)
}

@MainActor @Test(.timeLimit(.minutes(3))) func t230ExpiredPanelCancelPreservesStateAndButtons() async throws {
    let f = try await RecoveryFixture(); defer { f.remove() }
    let controller = f.controller(); let window = try #require(controller.window)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.a.path)
        if let panel = window.attachedSheet { window.endSheet(panel, returnCode: .cancel) }
        window.close()
    }
    _ = try await t230OpenPositionBeforeLoss(f, controller)
    try await t230DenyRoot(f, controller)
    let page = try #require(recoveryPage(controller)), lost = f.services.monitor.state.snapshot(for: f.rootA)
    let records = await f.services.files.records(), current = controller.waitingAccessPosition?.currentItemID
    for _ in 0..<2 {
        page.reselectButton.performClick(nil)
        try await recoveryWait { window.attachedSheet is NSOpenPanel }
        let panel = try #require(window.attachedSheet as? NSOpenPanel)
        #expect(panel.canChooseDirectories && !panel.canChooseFiles && !panel.allowsMultipleSelection)
        window.endSheet(panel, returnCode: .cancel)
        try await recoveryWait { window.attachedSheet == nil }
        #expect(recoveryPage(controller) === page && page.buttons == [page.reselectButton])
        #expect(window.firstResponder === page.reselectButton)
        #expect(f.services.monitor.state.snapshot(for: f.rootA) == lost)
        #expect(await f.services.files.records() == records)
        #expect(controller.waitingAccessPosition?.currentItemID == current)
    }
}

@MainActor @Test(.timeLimit(.minutes(3))) func t230AccessExpiredCatalogHasPinnedChineseAndEnglishCopy() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("App/Resources/Localizable.xcstrings"))
    let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let strings = try #require(catalog["strings"] as? [String: Any])
    for (key, chinese) in [
        ("Access Has Expired", "授权失效"),
        ("Access has expired. Choose this folder again to restore access; picsee will return to where you left off.", "访问权限已失效。重新选择这个文件夹即可恢复，picsee 会回到你刚才的位置。")
    ] {
        let entry = try #require(strings[key] as? [String: Any])
        let localizations = try #require(entry["localizations"] as? [String: Any])
        for (language, expected) in [("en", key), ("zh-Hans", chinese)] {
            let translation = try #require(localizations[language] as? [String: Any])
            let unit = try #require(translation["stringUnit"] as? [String: Any])
            #expect(unit["value"] as? String == expected)
        }
    }
}
