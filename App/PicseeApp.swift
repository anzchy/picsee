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
    private let imagePipeline = ImageIOPipeline(cacheTrace: UntestedNativeResourceSnapshotTrace())
    private lazy var memoryPressure = UntestedNativeMemoryPressureForwarder(pipeline: imagePipeline)
    private let displayPreferences = InMemoryDisplayPreferencesStore()
    private var commandMenu: CommandMenu?
    private var windowController: CanvasWindowController?
    private lazy var accessServices: Task<AccessServices, Error> = {
        let sha = Bundle.main.object(forInfoDictionaryKey: "PicseeGitSHA") as? String ?? "unknown"
        return Task.detached { try AccessServices(buildSHA: sha) }
    }()
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
        _ = memoryPressure

        commandMenu = CommandMenu(preferencesStore: displayPreferences) { [weak self] in
            self?.viewer().route(.open, from: .menu)
        }
        viewer().showWindow(nil)
        viewer().refreshRecents()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let file = urls.first(where: { $0.isFileURL && !$0.hasDirectoryPath }) else { return }
        viewer().open(file)
        application.activate(ignoringOtherApps: true)
    }

    private func viewer() -> CanvasWindowController {
        if let windowController { return windowController }
        let controller = CanvasWindowController(pipeline: imagePipeline, preferencesStore: displayPreferences, accessServices: accessServices)
        controller.onOpenRequest = { [weak self] in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image, .folder]
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url {
                if url.hasDirectoryPath { self?.viewer().openGrantedFolder(url) }
                else { self?.application(NSApp, open: [url]) }
            }
        }
        controller.menuTracking = { [weak self] in self?.commandMenu?.isTracking ?? false }
        controller.onRecentsChanged = { [weak self] folders in
            self?.commandMenu?.setRecentFolders(folders) { [weak self] folder in self?.viewer().openRecent(folder) }
        }
        windowController = controller
        return controller
    }
}
