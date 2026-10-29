import AppKit
import Testing
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
import PicseeMacUI

@MainActor private final class Issue150MotionSource: ReduceMotionSource {
    var reduceMotion = false
    var onChange: (@MainActor () -> Void)?
}

/// Closing the window ends a folder entry; a reused controller's Cancel Reading must not restore what was shown before.
@Test @MainActor func issue150ClosingWindowDropsFolderEntryRestorePoint() throws {
    _ = NSApplication.shared
    let controller = CanvasWindowController(pipeline: ImageIOPipeline(),
        preferencesStore: InMemoryDisplayPreferencesStore(), accessServices: Task { throw CancellationError() },
        motionPolicy: MotionPolicy(source: Issue150MotionSource()))
    let window = try #require(controller.window)
    let shown = URL(fileURLWithPath: "/tmp/issue150-close/a.png")
    controller.session.beginFolderEntry(shownImage: shown, hasCompleteGrid: false)
    window.close()
    #expect(controller.session.cancelFolderEntry() == nil)
}
