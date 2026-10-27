import AppKit
import Testing
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
import PicseeMacUI
import Darwin

@MainActor private final class SmokeMotionSource: ReduceMotionSource {
    var reduceMotion = false
    var onChange: (@MainActor () -> Void)?
}

@MainActor private func smokeFixture(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("TestAssets/synthetic/\(name)")
}

@MainActor private func smokeChrome(in view: NSView) -> ViewerChromeOverlay? {
    if let chrome = view as? ViewerChromeOverlay { return chrome }
    for child in view.subviews {
        if let chrome = smokeChrome(in: child) { return chrome }
    }
    return nil
}

@MainActor private func smokeViewer(in base: URL, image: URL) async throws
    -> (CanvasWindowController, AccessServices, NSWindow, ViewerChromeOverlay) {
    _ = NSApplication.shared
    let scope = SystemSecurityScope()
    let access = try FileAccess(scope: scope, bookmarks: scope,
        store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "issue140-smoke")
    let root = try await access.grant(folder: base)
    let services = AccessServices(files: access,
        recent: RecentFolderStore(url: base.appendingPathComponent("recent.json")),
        browser: FolderBrowser(),
        watch: WatchHub(access: access, source: FSEventSource(), scheduler: DispatchWatchScheduler()))
    let controller = CanvasWindowController(pipeline: ImageIOPipeline(),
        preferencesStore: InMemoryDisplayPreferencesStore(), accessServices: Task { services },
        motionPolicy: MotionPolicy(source: SmokeMotionSource()))
    let window = try #require(controller.window)
    let chrome = try #require(window.contentView.flatMap(smokeChrome(in:)))
    controller.open(image, accessRequest: .root(root, file: image))
    let deadline = ContinuousClock.now + .seconds(8)
    while (controller.session.folderScan?.sourceSnapshot?.isComplete != true ||
           controller.session.imageLoader.presented == nil || chrome.position == nil) &&
          ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.session.folderScan?.sourceSnapshot?.isComplete == true)
    #expect(controller.session.imageLoader.presented != nil)
    return (controller, services, window, chrome)
}

@Test @MainActor func issue140SmokeWatchedRenameUpdatesViewedTitleLabelAndCurrentItem() async throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    let original = base.appendingPathComponent("03-landscape.png")
    let renamed = base.appendingPathComponent("03-renamed-landscape.png")
    try fm.copyItem(at: smokeFixture("landscape-3x2.png"), to: original)
    let (controller, services, window, chrome) = try await smokeViewer(in: base, image: original)
    defer { window.close() }
    let id = try #require(controller.session.folderScan?.currentItemID)
    controller.session.beginBrowsing(items: [id], sourceVersion: .init(1), scrollAnchor: id)
    controller.session.focus(id)
    #expect(CommandRouter().route(.preview, from: .key, to: controller.session))
    #expect(controller.session.previewSet?.currentItemID == id)
    try fm.moveItem(at: original, to: renamed)
    services.watch.reconcileAll()
    let deadline = ContinuousClock.now + .seconds(8)
    while controller.session.folderScan?.sourceSnapshot?.entries.first?.url.standardizedFileURL.resolvingSymlinksInPath() !=
          renamed.standardizedFileURL.resolvingSymlinksInPath() &&
          ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    while (controller.session.imageLoader.presented?.fileURL.lastPathComponent != renamed.lastPathComponent ||
           chrome.filename != renamed.lastPathComponent) && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.session.folderScan?.sourceSnapshot?.entries.first?.url.standardizedFileURL.resolvingSymlinksInPath() ==
        renamed.standardizedFileURL.resolvingSymlinksInPath())
    #expect(controller.session.folderScan?.currentItemID == id)
    #expect(controller.session.currentItemID == id)
    #expect(controller.session.folderScan?.currentURL?.standardizedFileURL.resolvingSymlinksInPath() ==
        renamed.standardizedFileURL.resolvingSymlinksInPath())
    #expect(controller.session.imageLoader.presented?.fileURL.lastPathComponent == renamed.lastPathComponent)
    #expect(window.title == renamed.lastPathComponent)
    #expect(chrome.filename == renamed.lastPathComponent)
    #expect(chrome.position == "Images: 1")
}

@Test @MainActor func issue140SmokeWatchedAtomicReplacementReloadsPresentedRevision() async throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    let image = base.appendingPathComponent("03-landscape.png")
    let replacement = base.appendingPathComponent(".replacement.png")
    try fm.copyItem(at: smokeFixture("landscape-3x2.png"), to: image)
    try fm.copyItem(at: smokeFixture("portrait-2x3.png"), to: replacement)
    let (controller, services, window, _) = try await smokeViewer(in: base, image: image)
    defer { window.close() }
    let first = try #require(controller.session.imageLoader.presented)
    let id = try #require(controller.session.folderScan?.currentItemID)
    controller.session.beginBrowsing(items: [id], sourceVersion: .init(1), scrollAnchor: id)
    controller.session.focus(id)
    #expect(CommandRouter().route(.preview, from: .key, to: controller.session))
    let generation = try #require(controller.session.folderScan?.generation)
    let result = replacement.path.withCString { from in
        image.path.withCString { to in Darwin.rename(from, to) }
    }
    #expect(result == 0)
    services.watch.reconcileAll()
    let deadline = ContinuousClock.now + .seconds(8)
    while (controller.session.folderScan?.generation == generation ||
           controller.session.folderScan?.isScanning == true) && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    while (controller.session.imageLoader.presented == nil ||
           controller.session.imageLoader.presented?.key.revision == first.key.revision) &&
          ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.session.folderScan?.generation != generation)
    #expect(controller.session.imageLoader.presented?.key.revision != first.key.revision)
    #expect(controller.session.imageLoader.presented?.fileURL.lastPathComponent == image.lastPathComponent)
}

@Test @MainActor func issue140SmokeWatchedDeleteUpdatesBottomImageCount() async throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    let shown = base.appendingPathComponent("03-landscape.png")
    let neighbour = base.appendingPathComponent("04-portrait.png")
    try fm.copyItem(at: smokeFixture("landscape-3x2.png"), to: shown)
    try fm.copyItem(at: smokeFixture("portrait-2x3.png"), to: neighbour)
    let (controller, services, window, chrome) = try await smokeViewer(in: base, image: shown)
    defer { window.close() }
    #expect(chrome.position == "Images: 2")
    try fm.removeItem(at: shown)
    services.watch.reconcileAll()
    let deadline = ContinuousClock.now + .seconds(8)
    while controller.session.folderScan?.sourceSnapshot?.navigationEntries.count != 1 &&
          ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    while chrome.position != "Images: 1" && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.session.folderScan?.sourceSnapshot?.navigationEntries.count == 1)
    #expect(controller.session.folderScan?.currentURL?.lastPathComponent == neighbour.lastPathComponent)
    #expect(chrome.position == "Images: 1")
}
