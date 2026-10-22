import AppKit
import os
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
import PicseeMacUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: CanvasWindowController?
    private let logger = Logger(subsystem: "io.github.anzchy.picsee", category: "lifecycle")

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let sha = Bundle.main.object(forInfoDictionaryKey: "PicseeGitSHA") as? String ?? "unknown"
        logger.notice("Picsee launch git=\(sha, privacy: .public)")

        viewer().showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let file = urls.first(where: { $0.isFileURL }) else { return }
        viewer().open(file)
        application.activate(ignoringOtherApps: true)
    }

    private func viewer() -> CanvasWindowController {
        if let windowController { return windowController }
        let controller = CanvasWindowController(pipeline: ImageIOPipeline())
        windowController = controller
        return controller
    }
}
