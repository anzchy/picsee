import AppKit
import os
import PicseeCore
import PicseeApplication
import PicseeInfrastructure
import PicseeMacUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController?
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

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Picsee"
        window.center()
        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
