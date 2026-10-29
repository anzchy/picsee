import AppKit
import Testing
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
import PicseeMacUI

@MainActor private final class TrashTestMotionSource: ReduceMotionSource {
    var reduceMotion = false
    var onChange: (@MainActor () -> Void)?
}

@MainActor func sheetText(_ window: NSWindow) -> String {
    guard let sheet = window.attachedSheet else { return "" }
    func texts(_ view: NSView) -> [String] {
        ((view as? NSTextField).map { [$0.stringValue] } ?? []) + view.subviews.flatMap(texts)
    }
    return sheet.contentView.map(texts)?.filter { !$0.isEmpty }.joined(separator: " | ") ?? ""
}

@Test @MainActor func issue140DisplayedFileGrantTrashClearsWithoutReconnectSheet() async throws {
    _ = NSApplication.shared
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    let file = base.appendingPathComponent("image.png")
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("TestAssets/synthetic/landscape-3x2.png")
    try fm.copyItem(at: fixture, to: file)
    let scope = SystemSecurityScope()
    let access = try FileAccess(scope: scope, bookmarks: scope,
        store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "issue140-native-trash")
    let services = AccessServices(files: access,
        recent: RecentFolderStore(url: base.appendingPathComponent("recent.json")),
        browser: FolderBrowser(),
        watch: WatchHub(access: access, source: FSEventSource(), scheduler: DispatchWatchScheduler()))
    let controller = CanvasWindowController(pipeline: ImageIOPipeline(),
        preferencesStore: InMemoryDisplayPreferencesStore(), accessServices: Task { services },
        motionPolicy: MotionPolicy(source: TrashTestMotionSource()))
    let window = try #require(controller.window)
    defer { window.close() }
    controller.open(file, accessRequest: .fileGrant(file))
    let deadline = ContinuousClock.now + .seconds(8)
    while controller.session.imageLoader.presented == nil && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.session.imageLoader.presented != nil)
    var trashed: NSURL?
    try fm.trashItem(at: file, resultingItemURL: &trashed)
    defer { if let trashed { try? fm.removeItem(at: trashed as URL) } }
    let reconcileDeadline = ContinuousClock.now + .seconds(8)
    while controller.session.imageLoader.fileURL != nil && ContinuousClock.now < reconcileDeadline {
        controller.reconcileStandaloneImage()
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.session.imageLoader.fileURL == nil)
    #expect(window.representedURL == nil)
    #expect(window.attachedSheet == nil, "sheet: \(sheetText(window))")
}
