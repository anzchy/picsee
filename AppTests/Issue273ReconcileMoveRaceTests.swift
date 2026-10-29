import AppKit
import Testing
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
import PicseeMacUI

@MainActor private final class RaceMotionSource: ReduceMotionSource {
    var reduceMotion = false
    var onChange: (@MainActor () -> Void)?
}

/// Once armed, moves the file inside the next header request, after the grant was resolved but before
/// the read. This is the order the CI runner hit: reconcile resolved the original path, then the file moved.
private final class MoveDuringRequestPipeline: ImagePipeline, @unchecked Sendable {
    let base = ImageIOPipeline()
    private let lock = NSLock()
    private let move: @Sendable () throws -> URL?
    private var armed = false
    private var movedURL: URL?
    private var ran = 0
    init(move: @escaping @Sendable () throws -> URL?) { self.move = move }
    func arm() { lock.withLock { armed = true } }
    var moves: Int { lock.withLock { ran } }
    var moved: URL? { lock.withLock { movedURL } }
    func request(for fileURL: URL, maximumPixelSize: Int) async throws -> ImageDecodeRequest {
        let fire = lock.withLock { () -> Bool in
            defer { armed = false }
            return armed
        }
        if fire {
            let url = try move()
            lock.withLock { ran += 1; movedURL = url }
        }
        return try await base.request(for: fileURL, maximumPixelSize: maximumPixelSize)
    }
    func request(for fileURL: URL, maximumPixelSize: Int, identityRoot: ItemIdentityRoot?) async throws -> ImageDecodeRequest {
        try await base.request(for: fileURL, maximumPixelSize: maximumPixelSize, identityRoot: identityRoot)
    }
    func image(for request: ImageDecodeRequest) async throws -> DecodedImage {
        try await base.image(for: request)
    }
}

@MainActor private func raceController(in base: URL, pipeline: MoveDuringRequestPipeline) throws -> CanvasWindowController {
    _ = NSApplication.shared
    let scope = SystemSecurityScope()
    let access = try FileAccess(scope: scope, bookmarks: scope,
        store: BookmarkStore(url: base.appendingPathComponent("roots.json")), buildSHA: "issue273-race")
    let services = AccessServices(files: access,
        recent: RecentFolderStore(url: base.appendingPathComponent("recent.json")),
        browser: FolderBrowser(),
        watch: WatchHub(access: access, source: FSEventSource(), scheduler: DispatchWatchScheduler()))
    return CanvasWindowController(pipeline: pipeline,
        preferencesStore: InMemoryDisplayPreferencesStore(), accessServices: Task { services },
        motionPolicy: MotionPolicy(source: RaceMotionSource()))
}

private func raceFixture() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("TestAssets/synthetic/landscape-3x2.png")
}

/// Opens a File Grant, waits for the viewer to settle, arms the move and starts one reconcile.
@MainActor private func openThenArm(_ file: URL, _ controller: CanvasWindowController,
                                    _ pipeline: MoveDuringRequestPipeline) async throws {
    controller.open(file, accessRequest: .fileGrant(file))
    let deadline = ContinuousClock.now + .seconds(8)
    while controller.session.imageLoader.phase != .settled && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(controller.session.imageLoader.phase == .settled)
    pipeline.arm()
    controller.reconcileStandaloneImage()
}

@Test @MainActor func issue273TrashDuringReconcileReadClearsWithoutReconnectSheet() async throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    let file = base.appendingPathComponent("image.png")
    try fm.copyItem(at: raceFixture(), to: file)
    let pipeline = MoveDuringRequestPipeline {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: file, resultingItemURL: &trashed)
        return trashed as URL?
    }
    defer { if let trashed = pipeline.moved { try? fm.removeItem(at: trashed) } }
    let controller = try raceController(in: base, pipeline: pipeline)
    let window = try #require(controller.window)
    defer { window.close() }
    try await openThenArm(file, controller, pipeline)
    let deadline = ContinuousClock.now + .seconds(8)
    while (pipeline.moves == 0 || controller.session.imageLoader.fileURL != nil) &&
          window.attachedSheet == nil && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(pipeline.moves == 1)
    #expect(controller.session.imageLoader.fileURL == nil)
    #expect(window.representedURL == nil)
    #expect(window.attachedSheet == nil)
}

@Test @MainActor func issue273DotTrashMoveDuringReconcileReadFollowsWithoutSheet() async throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let ordinaryTrash = base.appendingPathComponent(".Trash")
    try fm.createDirectory(at: ordinaryTrash, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }
    let original = base.appendingPathComponent("image.png")
    let moved = ordinaryTrash.appendingPathComponent("image.png")
    try fm.copyItem(at: raceFixture(), to: original)
    let pipeline = MoveDuringRequestPipeline {
        try FileManager.default.moveItem(at: original, to: moved)
        return moved
    }
    let controller = try raceController(in: base, pipeline: pipeline)
    let window = try #require(controller.window)
    defer { window.close() }
    try await openThenArm(original, controller, pipeline)
    let deadline = ContinuousClock.now + .seconds(8)
    while (pipeline.moves == 0 ||
           controller.session.imageLoader.presented?.fileURL.standardizedFileURL != moved.standardizedFileURL) &&
          window.attachedSheet == nil && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(pipeline.moves == 1)
    #expect(controller.session.imageLoader.presented?.fileURL.standardizedFileURL == moved.standardizedFileURL)
    #expect(window.representedURL?.standardizedFileURL == moved.standardizedFileURL)
    #expect(window.attachedSheet == nil)
}
