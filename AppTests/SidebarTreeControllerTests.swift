import AppKit
import Testing
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
import PicseeMacUI

@MainActor private final class SidebarMotionSource: ReduceMotionSource {
    var reduceMotion = false
    var onChange: (@MainActor () -> Void)?
}

@MainActor private func sidebarTree(_ controller: CanvasWindowController) throws -> GridSidebarTreeView {
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let content = try #require(controller.window?.contentView)
    return try #require(descendants(content)
        .compactMap { $0 as? GridSidebarTreeView }.first)
}

@MainActor private func sidebarCancelButton(_ controller: CanvasWindowController) throws -> NSButton {
    func buttons(_ view: NSView) -> [NSButton] {
        let current: [NSButton] = (view as? NSButton).map { [$0] } ?? []
        return current + view.subviews.flatMap(buttons)
    }
    let content = try #require(controller.window?.contentView)
    return try #require(buttons(content).first { $0.title == String(localized: "Cancel Reading") })
}
private func sameSidebarURL(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.standardizedFileURL.pathComponents == rhs.standardizedFileURL.pathComponents
}

@MainActor private func waitForSidebar(_ stage: String, _ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(8)
    while !(await condition()) && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require(await condition(), "Sidebar stage: \(stage)")
}

private actor SidebarLeaseTracker: AccessLeasing {
    let root: URL
    private(set) var active = 0
    private(set) var childAcquires = 0
    init(root: URL) { self.root = root }
    func acquire(_ request: AccessRequest) -> AccessLease {
        active += 1
        if case .root(_, let file) = request, file.lastPathComponent == "Child" { childAcquires += 1 }
        return AccessLease(url: root, rootID: AccessRootID())
    }
    func release(_ lease: AccessLease) { active -= 1 }
}

private actor SidebarBlockedCount: SidebarFolderEnumerating {
    let child: URL
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private(set) var started = 0
    init(child: URL) { self.child = child }
    func children(in folder: URL, root: URL) -> [URL] { [child] }
    func imageCount(in folder: URL, root: URL) async -> Int {
        started += 1
        if !released { await withCheckedContinuation { waiters.append($0) } }
        return 1
    }
    func release() { released = true; for waiter in waiters { waiter.resume() }; waiters.removeAll() }
}

private actor SwitchingSidebarCounter: SidebarFolderEnumerating {
    let a: URL, b: URL
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private(set) var bStarts = 0
    init(a: URL, b: URL) { self.a = a; self.b = b }
    func children(in folder: URL, root: URL) -> [URL] {
        folder.pathComponents == a.pathComponents ? [b] : []
    }
    func imageCount(in folder: URL, root: URL) async -> Int {
        if folder.pathComponents == a.pathComponents { return 1 }
        bStarts += 1
        let count = bStarts == 1 ? 999 : 2
        if !released { await withCheckedContinuation { waiters.append($0) } }
        return count
    }
    func release() { released = true; for waiter in waiters { waiter.resume() }; waiters.removeAll() }
}

@Test @MainActor func sidebarABARevisitRejectsStaleBlockedCount() async throws {
    _ = NSApplication.shared
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = base.appendingPathComponent("A"), b = a.appendingPathComponent("B")
    try fm.createDirectory(at: b, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    let image = try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("TestAssets/synthetic/portrait-2x3.png"))
    try image.write(to: a.appendingPathComponent("a.png"))
    try image.write(to: b.appendingPathComponent("b.png"))
    let scope = SystemSecurityScope()
    let access = try FileAccess(scope: scope, bookmarks: scope,
        store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "sidebar-aba")
    let root = try await access.grant(folder: base)
    let services = AccessServices(files: access,
        recent: RecentFolderStore(url: base.appendingPathComponent("recent.json")),
        browser: FolderBrowser(), watch: WatchHub(access: access, source: FSEventSource(), scheduler: DispatchWatchScheduler()))
    let controller = CanvasWindowController(pipeline: ImageIOPipeline(),
        preferencesStore: InMemoryDisplayPreferencesStore(), accessServices: Task { services },
        motionPolicy: MotionPolicy(source: SidebarMotionSource()))
    defer { controller.window?.close() }
    let counter = SwitchingSidebarCounter(a: a, b: b)
    controller.sidebarBrowserOverride = SidebarFolderBrowser(access: SidebarLeaseTracker(root: base), enumerator: counter)
    controller.browseRecoveredFolder(a, rootID: root)
    let tree = try sidebarTree(controller)
    try await waitForSidebar("A count blocked at child") {
        let started = await counter.bStarts
        return tree.rows.contains { sameSidebarURL($0.folderURL, b) } && started > 0
    }
    tree.rows.first(where: { sameSidebarURL($0.folderURL, b) })?.performClick(nil)
    #expect(tree.rows.first(where: { $0.current }).map { sameSidebarURL($0.folderURL, b) } == true)
    controller.browseRecoveredFolder(a, rootID: root)
    try await waitForSidebar("A revisit") {
        let started = await counter.bStarts
        return tree.rows.first(where: { $0.current }).map { sameSidebarURL($0.folderURL, a) } == true &&
            started >= 2
    }
    await counter.release()
    try await waitForSidebar("current A direct count") {
        tree.rows.first(where: { $0.current })?.countLabel.stringValue == "1" &&
        tree.rows.first(where: { sameSidebarURL($0.folderURL, b) })?.countLabel.stringValue == "2"
    }
}

@Test @MainActor func sidebarCloseCancelsBlockedCountAndTakesNoChildLease() async throws {
    _ = NSApplication.shared
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    let scope = SystemSecurityScope()
    let access = try FileAccess(scope: scope, bookmarks: scope,
        store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "sidebar-close")
    let root = try await access.grant(folder: base)
    let services = AccessServices(files: access,
        recent: RecentFolderStore(url: base.appendingPathComponent("recent.json")),
        browser: FolderBrowser(), watch: WatchHub(access: access, source: FSEventSource(), scheduler: DispatchWatchScheduler()))
    let controller = CanvasWindowController(pipeline: ImageIOPipeline(),
        preferencesStore: InMemoryDisplayPreferencesStore(), accessServices: Task { services },
        motionPolicy: MotionPolicy(source: SidebarMotionSource()))
    let tracker = SidebarLeaseTracker(root: base)
    let counter = SidebarBlockedCount(child: base.appendingPathComponent("Child"))
    controller.sidebarBrowserOverride = SidebarFolderBrowser(access: tracker, enumerator: counter)
    controller.browseRecoveredFolder(base, rootID: root)
    let tree = try sidebarTree(controller)
    try await waitForSidebar("close rows and scan") { tree.rows.map(\.folderURL).contains(counter.child) &&
        controller.session.folderScan?.sourceSnapshot?.isComplete == true }
    try await waitForSidebar("blocked count") { await counter.started > 0 }
    #expect(controller.gridSearchAvailable)
    let childAcquiresAtClose = await tracker.childAcquires
    #expect(childAcquiresAtClose == 0)
    controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: controller.window))
    controller.window?.close()
    await counter.release()
    try await waitForSidebar("released lease") { await tracker.active == 0 }
    #expect(await tracker.childAcquires == childAcquiresAtClose)
}

@Test @MainActor func sidebarCancelRestoresPriorTreeAndWatchRefreshRemovesDeletedChild() async throws {
    _ = NSApplication.shared
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = base.appendingPathComponent("A")
    let b = a.appendingPathComponent("B")
    let c = a.appendingPathComponent("C")
    try fm.createDirectory(at: b, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    let image = try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("TestAssets/synthetic/portrait-2x3.png"))
    try image.write(to: a.appendingPathComponent("a.png"))
    try image.write(to: b.appendingPathComponent("b.png"))
    let scope = SystemSecurityScope()
    let access = try FileAccess(scope: scope, bookmarks: scope,
        store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "sidebar-fix")
    let root = try await access.grant(folder: base)
    let directChildren = try await SidebarFolderBrowser(access: access,
        enumerator: SystemSidebarFolderEnumerator()).children(in: a, rootID: root)
    #expect(directChildren.map(\.lastPathComponent) == ["B"])
    let services = AccessServices(files: access,
        recent: RecentFolderStore(url: base.appendingPathComponent("recent.json")),
        browser: FolderBrowser(), watch: WatchHub(access: access, source: FSEventSource(), scheduler: DispatchWatchScheduler()))
    let controller = CanvasWindowController(pipeline: ImageIOPipeline(),
        preferencesStore: InMemoryDisplayPreferencesStore(), accessServices: Task { services },
        motionPolicy: MotionPolicy(source: SidebarMotionSource()))
    defer { controller.window?.close() }
    controller.browseRecoveredFolder(a, rootID: root)
    let tree = try sidebarTree(controller)
    try await waitForSidebar("A scan") { controller.session.folderScan?.sourceSnapshot?.isComplete == true }
    try await waitForSidebar("A tree") {
        tree.rows.contains { sameSidebarURL($0.folderURL, b) }
    }
    try await waitForSidebar("direct counts") {
        tree.rows.first(where: { sameSidebarURL($0.folderURL, a) })?.countLabel.stringValue == "1" &&
        tree.rows.first(where: { sameSidebarURL($0.folderURL, b) })?.countLabel.stringValue == "1"
    }
    #expect(tree.rows.first(where: { sameSidebarURL($0.folderURL, a) })?.countLabel.stringValue == "1")
    _ = controller.session.setFolderRecursiveEnabled(true)
    try await waitForSidebar("recursive grid keeps direct tree count") {
        controller.session.folderScan?.sourceSnapshot?.navigationEntries.count == 2 &&
        tree.rows.first(where: { sameSidebarURL($0.folderURL, a) })?.countLabel.stringValue == "1"
    }
    tree.rows.first(where: { sameSidebarURL($0.folderURL, b) })?.performClick(nil)
    #expect(tree.rows.first(where: { $0.current }).map { sameSidebarURL($0.folderURL, b) } == true)
    let cancel = try sidebarCancelButton(controller)
    cancel.performClick(nil)
    try await waitForSidebar("restore A tree") {
        tree.rows.first(where: { $0.current }).map { sameSidebarURL($0.folderURL, a) } == true &&
        tree.rows.contains { sameSidebarURL($0.folderURL, b) }
    }
    try fm.createDirectory(at: c, withIntermediateDirectories: true)
    try image.write(to: c.appendingPathComponent("c.png"))
    services.watch.reconcileAll()
    try await waitForSidebar("added C") {
        tree.rows.contains { sameSidebarURL($0.folderURL, c) } &&
        tree.rows.first(where: { sameSidebarURL($0.folderURL, c) })?.countLabel.stringValue == "1"
    }
    try image.write(to: c.appendingPathComponent("c2.png"))
    services.watch.reconcileAll()
    try await waitForSidebar("changed C image count") {
        tree.rows.first(where: { sameSidebarURL($0.folderURL, c) })?.countLabel.stringValue == "2"
    }
    let d = a.appendingPathComponent("D")
    try fm.moveItem(at: c, to: d)
    services.watch.reconcileAll()
    try await waitForSidebar("renamed C to D") {
        !tree.rows.contains { sameSidebarURL($0.folderURL, c) } &&
        tree.rows.first(where: { sameSidebarURL($0.folderURL, d) })?.countLabel.stringValue == "2"
    }
    try fm.removeItem(at: b)
    services.watch.reconcileAll()
    try await waitForSidebar("removed B") { !tree.rows.contains { sameSidebarURL($0.folderURL, b) } }
    #expect(!tree.rows.contains(where: { sameSidebarURL($0.folderURL, b) }))
}
