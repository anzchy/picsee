import AppKit
import Testing
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
import PicseeMacUI

private struct T229AppBookmarks: SecurityScope, BookmarkCoding {
    func start(_ url: URL) -> Bool { true }
    func stop(_ url: URL) {}
    func isReadable(_ url: URL) -> Bool { true }
    func create(for url: URL) throws -> Data { Data(url.path.utf8) }
    func resolve(_ data: Data) throws -> ResolvedBookmark {
        ResolvedBookmark(url: URL(fileURLWithPath: String(decoding: data, as: UTF8.self)), stale: false)
    }
}
private actor T229AppMounts: DiskMountPort {
    private var continuation: AsyncStream<DiskMountEvent>.Continuation?
    func mountedVolumes() -> [AccessProbeVolume] {
        [AccessProbeVolume(uuid: "111", url: URL(fileURLWithPath: "/"), name: "Disk"),
         AccessProbeVolume(uuid: "222", url: URL(fileURLWithPath: "/other"), name: "Other")]
    }
    func events() -> AsyncStream<DiskMountEvent> { AsyncStream { continuation = $0 } }
    func emit(_ event: DiskMountEvent) { continuation?.yield(event) }
}
@MainActor private final class T229AppMotion: ReduceMotionSource {
    var reduceMotion = false
    var onChange: (@MainActor () -> Void)?
}
private struct T229AppInspector: InspectorMetadataReading {
    func read(_ url: URL, access: AccessRequest) async throws -> InspectorMetadata {
        InspectorMetadata(pixelWidth: 100, pixelHeight: 80, thumbnailData: Data([1, 2]))
    }
}

@MainActor private func t229Wait(_ predicate: @MainActor () -> Bool) async throws {
    let limit = ContinuousClock.now + .seconds(8)
    while !predicate(), ContinuousClock.now < limit { try await Task.sleep(for: .milliseconds(10)) }
    #expect(predicate())
}

@MainActor private func t229WaitForNativeGrid(_ controller: CanvasWindowController) async throws {
    let shell = try #require(controller.window?.contentView?.subviews.compactMap { $0 as? GridShellView }.first)
    let grid = try #require(shell.mainContent.subviews.compactMap { $0 as? GridBrowserView }.first)
    try await t229Wait { !grid.isHidden && grid.displayedItemIDs.count == 1 }
}

@MainActor @Test func t229LossClearsBothWindowsAndKeepsUnrelatedRootReadable() async throws {
    _ = NSApplication.shared
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let folder = base.appendingPathComponent("PrivatePhotos", isDirectory: true)
    let other = base.appendingPathComponent("OtherPhotos", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("TestAssets/synthetic/landscape-3x2.png")
    let image = folder.appendingPathComponent("private.png")
    try FileManager.default.copyItem(at: fixture, to: image)
    try FileManager.default.copyItem(at: fixture, to: other.appendingPathComponent("other.png"))
    let adapter = T229AppBookmarks()
    let files = try FileAccess(scope: adapter, bookmarks: adapter,
        store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "T229",
        bookmarkVolume: { data in
            let path = String(decoding: data, as: UTF8.self)
            return AccessProbeVolume(uuid: path.contains("OtherPhotos") ? "222" : "111", url: nil, name: "Disk")
        })
    let root = try await files.grant(folder: folder), unrelated = try await files.grant(folder: other)
    let mounts = T229AppMounts()
    let services = AccessServices(files: files, recent: RecentFolderStore(url: base.appendingPathComponent("recent.json")),
        browser: FolderBrowser(), watch: WatchHub(access: files, source: FSEventSource(), scheduler: DispatchWatchScheduler()),
        mounts: mounts)
    let controllers = (0..<3).map { _ in
        CanvasWindowController(pipeline: ImageIOPipeline(), preferencesStore: InMemoryDisplayPreferencesStore(),
            accessServices: Task { services }, motionPolicy: MotionPolicy(source: T229AppMotion()),
            inspectorReader: T229AppInspector())
    }
    defer { for controller in controllers { controller.window?.close() } }
    for controller in controllers.prefix(2) { controller.browseRecoveredFolder(folder, rootID: root) }
    controllers[2].browseRecoveredFolder(other, rootID: unrelated)
    try await t229Wait { controllers.allSatisfy { $0.session.folderScan?.snapshot?.isComplete == true } }
    for controller in controllers { try await t229WaitForNativeGrid(controller) }
    for controller in controllers.prefix(2) {
        controller.inspector.select(itemID: nil, url: image, access: .root(root, file: image))
    }
    try await t229Wait { controllers.prefix(2).allSatisfy { $0.inspector.name == "private.png" } }
    services.monitor.state.register(root, volumeUUID: "111")
    services.monitor.state.register(unrelated, volumeUUID: "222")
    await mounts.emit(.unmounted(AccessProbeVolume(uuid: "111", url: nil, name: "Disk")))
    try await t229Wait { services.monitor.state.snapshot(for: root)?.availability == .lost(.diskNotConnected) }
    for controller in controllers.prefix(2) {
        #expect(controller.session.mode == .browsing)
        #expect(controller.session.imageLoader.fileURL == nil)
        #expect(controller.session.previewSet == nil && controller.session.filePreviewSet == nil)
        #expect(controller.session.folderScan?.snapshot == nil)
        #expect(controller.inspector.name == nil && controller.inspector.value == .unknown)
        #expect(controller.window?.representedURL == nil)
        #expect(controller.window?.title == "Picsee")
        #expect(controller.gridShellVisible)
        #expect(controller.window?.attachedSheet == nil)
        let grid = try #require(controller.window?.contentView?.subviews.compactMap { $0 as? GridShellView }.first?
            .mainContent.subviews.compactMap { $0 as? GridBrowserView }.first)
        #expect(grid.currentItemID == nil)
        #expect(grid.collectionView.numberOfItems(inSection: 0) == 0)
        let shell = try #require(controller.window?.contentView?.subviews.compactMap { $0 as? GridShellView }.first)
        #expect(shell.folderTree.rows.isEmpty)
    }
    #expect(controllers[2].session.folderScan?.snapshot?.entries.count == 1)
    #expect(controllers[2].window?.representedURL == other)
}


@MainActor @Test func t229ReaderFailureChecksRootInsteadOfLosingReadableRootForMissingChild() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let rootURL = base.appendingPathComponent("Root", isDirectory: true)
    let child = rootURL.appendingPathComponent("MissingChild", isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let adapter = T229AppBookmarks()
    let files = try FileAccess(scope: adapter, bookmarks: adapter,
        store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "T229-reader")
    let id = try await files.grant(folder: rootURL)
    let monitor = AccessMonitor(files: files, mounts: T229AppMounts())
    await monitor.start()
    monitor.state.register(id, volumeUUID: nil)
    let stamp = monitor.state.stamp(for: id)
    #expect((try? FileManager.default.contentsOfDirectory(at: child, includingPropertiesForKeys: nil)) == nil)
    await monitor.reportReadFailure(id, from: stamp)
    #expect(monitor.state.snapshot(for: id)?.availability == .readable)
    #expect(monitor.state.snapshot(for: id)?.counter == 0)
    try FileManager.default.removeItem(at: rootURL)
    await monitor.reportReadFailure(id, from: stamp)
    #expect(monitor.state.snapshot(for: id)?.availability == .lost(.unknown))
    #expect(monitor.state.snapshot(for: id)?.counter == 1)
}

@MainActor @Test func t229RootCoveredStandaloneViewerClearsPixelsAndPrivateIdentityOnUnmount() async throws {
    _ = NSApplication.shared
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let folder = base.appendingPathComponent("PrivatePhotos", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("TestAssets/synthetic/landscape-3x2.png")
    let image = folder.appendingPathComponent("private.png")
    try FileManager.default.copyItem(at: fixture, to: image)
    let adapter = T229AppBookmarks()
    let files = try FileAccess(scope: adapter, bookmarks: adapter,
        store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "T229-viewer",
        bookmarkVolume: { _ in AccessProbeVolume(uuid: "111", url: nil, name: "Disk") })
    let root = try await files.grant(folder: folder)
    let mounts = T229AppMounts()
    let services = AccessServices(files: files, recent: RecentFolderStore(url: base.appendingPathComponent("recent.json")),
        browser: FolderBrowser(), watch: WatchHub(access: files, source: FSEventSource(), scheduler: DispatchWatchScheduler()),
        mounts: mounts)
    let controller = CanvasWindowController(pipeline: ImageIOPipeline(), preferencesStore: InMemoryDisplayPreferencesStore(),
        accessServices: Task { services }, motionPolicy: MotionPolicy(source: T229AppMotion()), inspectorReader: T229AppInspector())
    defer { controller.window?.close() }
    controller.open(image, accessRequest: nil)
    try await t229Wait { controller.session.imageLoader.presented != nil && controller.hasImage }
    #expect(controller.session.mode == .viewing)
    #expect(controller.window?.representedURL == image)
    controller.inspector.select(itemID: nil, url: image, access: .root(root, file: image))
    await mounts.emit(.unmounted(AccessProbeVolume(uuid: "111", url: nil, name: "Disk")))
    try await t229Wait { controller.waitingAccessPosition?.rootID == root }
    #expect(controller.session.mode == .browsing)
    #expect(!controller.hasImage)
    #expect(controller.session.imageLoader.fileURL == nil && controller.session.imageLoader.presented == nil)
    #expect(controller.inspector.name == nil && controller.inspector.value == .unknown)
    #expect(controller.window?.representedURL == nil && controller.window?.title == "Picsee")
    #expect(controller.gridShellVisible && controller.window?.attachedSheet == nil)
}

@MainActor @Test func t229ClosedControllerCannotReopenDetachedPrivateGridWithoutRootAssociation() async throws {
    _ = NSApplication.shared
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let folder = base.appendingPathComponent("PrivatePhotos", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("TestAssets/synthetic/landscape-3x2.png")
    try FileManager.default.copyItem(at: fixture, to: folder.appendingPathComponent("private.png"))
    let adapter = T229AppBookmarks()
    let files = try FileAccess(scope: adapter, bookmarks: adapter,
        store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "T229-reopen",
        bookmarkVolume: { _ in AccessProbeVolume(uuid: "111", url: nil, name: "Disk") })
    let root = try await files.grant(folder: folder)
    let mounts = T229AppMounts()
    let services = AccessServices(files: files, recent: RecentFolderStore(url: base.appendingPathComponent("recent.json")),
        browser: FolderBrowser(), watch: WatchHub(access: files, source: FSEventSource(), scheduler: DispatchWatchScheduler()),
        mounts: mounts)
    let controller = CanvasWindowController(pipeline: ImageIOPipeline(), preferencesStore: InMemoryDisplayPreferencesStore(),
        accessServices: Task { services }, motionPolicy: MotionPolicy(source: T229AppMotion()))
    defer { controller.window?.close() }
    controller.browseRecoveredFolder(folder, rootID: root)
    try await t229Wait { controller.session.folderScan?.snapshot?.isComplete == true }
    try await t229WaitForNativeGrid(controller)
    let shell = try #require(controller.window?.contentView?.subviews.compactMap { $0 as? GridShellView }.first)
    let grid = try #require(shell.mainContent.subviews.compactMap { $0 as? GridBrowserView }.first)
    #expect(grid.displayedItemIDs.count == 1)
    controller.window?.close()
    await mounts.emit(.unmounted(AccessProbeVolume(uuid: "111", url: nil, name: "Disk")))
    try await t229Wait { services.monitor.state.snapshot(for: root)?.availability == .lost(.diskNotConnected) }
    controller.showWindow(nil)
    #expect(grid.displayedItemIDs.isEmpty)
    #expect(grid.currentItemID == nil)
    #expect(shell.folderTree.rows.isEmpty)
    #expect(controller.window?.representedURL == nil && controller.window?.title == "Picsee")
    #expect(!controller.hasImage)
}

@MainActor @Test func t229CancelReadingRestoresRootAssociationBeforeUnrelatedDiskLoss() async throws {
    _ = NSApplication.shared
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = base.appendingPathComponent("A", isDirectory: true), b = base.appendingPathComponent("B", isDirectory: true)
    try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("TestAssets/synthetic/landscape-3x2.png")
    try FileManager.default.copyItem(at: fixture, to: a.appendingPathComponent("private.png"))
    let adapter = T229AppBookmarks()
    let files = try FileAccess(scope: adapter, bookmarks: adapter,
        store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "T229-cancel-context",
        bookmarkVolume: { data in
            let url = URL(fileURLWithPath: String(decoding: data, as: UTF8.self))
            return AccessProbeVolume(uuid: url.lastPathComponent == "B" ? "222" : "111", url: nil, name: "Disk")
        })
    let rootA = try await files.grant(folder: a), rootB = try await files.grant(folder: b)
    let mounts = T229AppMounts()
    let services = AccessServices(files: files, recent: RecentFolderStore(url: base.appendingPathComponent("recent.json")),
        browser: FolderBrowser(), watch: WatchHub(access: files, source: FSEventSource(), scheduler: DispatchWatchScheduler()),
        mounts: mounts)
    let controller = CanvasWindowController(pipeline: ImageIOPipeline(), preferencesStore: InMemoryDisplayPreferencesStore(),
        accessServices: Task { services }, motionPolicy: MotionPolicy(source: T229AppMotion()))
    defer { controller.window?.close() }
    controller.browseRecoveredFolder(a, rootID: rootA)
    try await t229Wait { controller.session.folderScan?.snapshot?.isComplete == true }
    try await t229WaitForNativeGrid(controller)
    controller.browseRecoveredFolder(b, rootID: rootB)
    let state = try #require(controller.window?.contentView?.subviews.compactMap { $0 as? ViewerStateHost }.first)
    let cancel = try #require(state.buttons.first)
    cancel.performClick(nil)
    #expect(controller.window?.representedURL == a)
    await mounts.emit(.unmounted(AccessProbeVolume(uuid: "222", url: nil, name: "Other")))
    try await t229Wait { services.monitor.state.snapshot(for: rootB)?.availability == .lost(.diskNotConnected) }
    #expect(controller.waitingAccessPosition == nil)
    #expect(controller.window?.representedURL == a)
    let shell = try #require(controller.window?.contentView?.subviews.compactMap { $0 as? GridShellView }.first)
    let grid = try #require(shell.mainContent.subviews.compactMap { $0 as? GridBrowserView }.first)
    #expect(grid.displayedItemIDs.count == 1)
}
