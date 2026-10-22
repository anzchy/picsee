import AppKit
import UniformTypeIdentifiers
import os
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
import PicseeMacUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let displayPreferences = InMemoryDisplayPreferencesStore()
    private var commandMenu: CommandMenu?
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

        commandMenu = CommandMenu { [weak self] in
            self?.viewer().route(.open, from: .menu)
        }
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
        let controller = CanvasWindowController(pipeline: ImageIOPipeline(), preferencesStore: displayPreferences)
        controller.onOpenRequest = { [weak self] in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url {
                self?.application(NSApp, open: [url])
            }
        }
        controller.menuTracking = { [weak self] in self?.commandMenu?.isTracking ?? false }
        windowController = controller
        return controller
    }
}
