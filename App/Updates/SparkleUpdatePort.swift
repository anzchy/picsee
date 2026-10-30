import Foundation
import PicseeApplication
import Sparkle

/// Untested native forwarding to Sparkle (network, XPC installer); the Settings side is covered with a fake
/// port, and the real path is checked on a device with a test appcast (#223). Excluded from PicseeAppTests.
@MainActor final class SparkleUpdatePort: NSObject, AppUpdatePort, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!
    private var observers: [@MainActor () -> Void] = []
    private var automaticObservation: NSKeyValueObservation?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        // Sparkle's second-launch question and Settings both change this flag; lastUpdateCheckDate is not
        // KVO-compliant, so the update-cycle callback below covers it.
        automaticObservation = controller.updater.observe(\.automaticallyChecksForUpdates) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.notify() }
        }
    }

    var versionInfo: AppVersionInfo { AppVersionInfo(infoDictionary: Bundle.main.infoDictionary ?? [:]) }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? { controller.updater.lastUpdateCheckDate }

    func checkForUpdates() { controller.checkForUpdates(nil) }

    func observe(_ onChange: @escaping @MainActor () -> Void) { observers.append(onChange) }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        notify()
    }

    private func notify() { observers.forEach { $0() } }
}
