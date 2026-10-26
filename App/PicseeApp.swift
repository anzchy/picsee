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
    private let thumbnailCache = ThumbnailDiskCache()
    private lazy var imagePipeline = ImageIOPipeline(cacheTrace: UntestedNativeResourceSnapshotTrace(),
                                                     thumbnailCache: thumbnailCache)
    private lazy var memoryPressure = UntestedNativeMemoryPressureForwarder(pipeline: imagePipeline) { [weak self] level in
        self?.windowController?.memoryPressure(level != .normal)
    }
    private let displayPreferences = UserDefaultsDisplayPreferencesStore(defaults: .standard)
    private lazy var appearanceAdapter = WindowAppearanceAdapter(preferencesStore: displayPreferences)
    private lazy var motionPolicy = MotionPolicy(source: UntestedNativeReduceMotionSource())
    private var commandMenu: CommandMenu?
    private var cacheSettingsWindow: CacheSettingsWindow?
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

        commandMenu = CommandMenu(preferencesStore: displayPreferences,
                                  openWithoutWindow: { [weak self] in self?.viewer().route(.open, from: .menu) },
                                  openSettings: { [weak self] in self?.showSettings() })
        viewer().showWindow(nil)
        viewer().refreshRecents()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Returning to the foreground reconciles every watched folder (events may have been coalesced or lost),
    /// and a window whose watch failed rescans and subscribes again.
    func applicationDidBecomeActive(_ notification: Notification) {
        let services = accessServices
        Task { try? await services.value.watch.reconcileAll() }
        windowController?.session.folderScan?.reconcileUnwatched()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        viewer().openInput(urls)
        application.activate(ignoringOtherApps: true)
    }

    private func viewer() -> CanvasWindowController {
        if let windowController { return windowController }
        let controller = CanvasWindowController(pipeline: imagePipeline, preferencesStore: displayPreferences, accessServices: accessServices, motionPolicy: motionPolicy)
        controller.appearanceAdapter = appearanceAdapter
        controller.onOpenRequest = { [weak self] in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image, .folder]
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url {
                if url.hasDirectoryPath { self?.viewer().openGrantedFolder(url) }
                else { self?.viewer().openInput([url]) }
            }
        }
        controller.menuTracking = { [weak self] in self?.commandMenu?.isTracking ?? false }
        controller.onRecentsChanged = { [weak self] folders in
            self?.commandMenu?.setRecentFolders(folders) { [weak self] folder in self?.viewer().openRecent(folder) }
        }
        windowController = controller
        return controller
    }

    private func showSettings() {
        if cacheSettingsWindow == nil {
            cacheSettingsWindow = CacheSettingsWindow(cache: thumbnailCache, appearanceAdapter: appearanceAdapter)
        }
        cacheSettingsWindow?.show()
    }
}

/// Untested native forwarding only; injected source behavior is covered in PicseeMacUI.
@MainActor private final class UntestedNativeReduceMotionSource: NSObject, ReduceMotionSource {
    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var onChange: (@MainActor () -> Void)?
    override init() {
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(changed(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }
    @objc private func changed(_ notification: Notification) { onChange?() }
}
