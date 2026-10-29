import AppKit
import Testing
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
import PicseeMacUI

@MainActor private final class Round2MotionSource: ReduceMotionSource {
    var reduceMotion = false
    var onChange: (@MainActor () -> Void)?
}

@MainActor private func round2Controller(in base: URL) throws -> CanvasWindowController {
    _ = NSApplication.shared
    let scope = SystemSecurityScope()
    let access = try FileAccess(scope: scope, bookmarks: scope,
        store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "issue140-r2-native")
    let services = AccessServices(files: access,
        recent: RecentFolderStore(url: base.appendingPathComponent("recent.json")),
        browser: FolderBrowser(),
        watch: WatchHub(access: access, source: FSEventSource(), scheduler: DispatchWatchScheduler()))
    return CanvasWindowController(pipeline: ImageIOPipeline(),
        preferencesStore: InMemoryDisplayPreferencesStore(), accessServices: Task { services },
        motionPolicy: MotionPolicy(source: Round2MotionSource()))
}

private func round2Fixture(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("TestAssets/synthetic/\(name)")
}

@Test @MainActor func issue140NativeOrdinaryDotTrashMoveKeepsViewerLive() async throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let ordinaryTrash = base.appendingPathComponent(".Trash")
    try fm.createDirectory(at: ordinaryTrash, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    let original = base.appendingPathComponent("image.png")
    let moved = ordinaryTrash.appendingPathComponent("image.png")
    try fm.copyItem(at: round2Fixture("landscape-3x2.png"), to: original)
    let controller = try round2Controller(in: base)
    let window = try #require(controller.window)
    defer { window.close() }
    controller.open(original, accessRequest: .fileGrant(original))
    let openedDeadline = ContinuousClock.now + .seconds(8)
    while controller.session.imageLoader.presented == nil && ContinuousClock.now < openedDeadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.session.imageLoader.presented != nil)
    try fm.moveItem(at: original, to: moved)
    let reconcileDeadline = ContinuousClock.now + .seconds(8)
    while controller.session.imageLoader.presented?.fileURL.standardizedFileURL != moved.standardizedFileURL &&
          ContinuousClock.now < reconcileDeadline {
        controller.reconcileStandaloneImage()
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.session.imageLoader.presented?.fileURL.standardizedFileURL == moved.standardizedFileURL)
    #expect(window.representedURL?.standardizedFileURL == moved.standardizedFileURL)
    #expect(window.attachedSheet == nil, "sheet: \(sheetText(window))")
}

@Test @MainActor func issue140NativeTrashThenSamePathReplacementShowsNewRevision() async throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    let file = base.appendingPathComponent("image.png")
    try fm.copyItem(at: round2Fixture("landscape-3x2.png"), to: file)
    let controller = try round2Controller(in: base)
    let window = try #require(controller.window)
    defer { window.close() }
    controller.open(file, accessRequest: .fileGrant(file))
    let openedDeadline = ContinuousClock.now + .seconds(8)
    while controller.session.imageLoader.presented == nil && ContinuousClock.now < openedDeadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    let original = try #require(controller.session.imageLoader.presented)
    var trashed: NSURL?
    try fm.trashItem(at: file, resultingItemURL: &trashed)
    defer { if let trashed { try? fm.removeItem(at: trashed as URL) } }
    try fm.copyItem(at: round2Fixture("portrait-2x3.png"), to: file)
    let reconcileDeadline = ContinuousClock.now + .seconds(8)
    while ContinuousClock.now < reconcileDeadline {
        if let presented = controller.session.imageLoader.presented,
           presented.key.revision != original.key.revision,
           presented.fileURL.standardizedFileURL == file.standardizedFileURL { break }
        controller.reconcileStandaloneImage()
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.session.imageLoader.presented?.key.revision != original.key.revision)
    #expect(controller.session.imageLoader.presented?.fileURL.standardizedFileURL == file.standardizedFileURL)
    #expect(window.representedURL?.standardizedFileURL == file.standardizedFileURL)
    #expect(window.attachedSheet == nil)
}
