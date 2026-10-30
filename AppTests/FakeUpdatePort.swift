import Foundation
import PicseeApplication

/// In-memory stand-in for the Sparkle updater; the real path is device-verified (#223).
@MainActor final class FakeUpdatePort: AppUpdatePort {
    var versionInfo: AppVersionInfo
    var automaticallyChecksForUpdates: Bool
    var lastUpdateCheckDate: Date?
    var nextCheckDate: Date?
    private(set) var checkCount = 0
    private var observers: [@MainActor () -> Void] = []

    init(version: String? = "2.0.0", build: String? = "40", automatic: Bool = false,
         lastCheck: Date? = nil, nextCheckDate: Date? = nil) {
        var info: [String: Any] = [:]
        info["CFBundleShortVersionString"] = version
        info["CFBundleVersion"] = build
        versionInfo = AppVersionInfo(infoDictionary: info)
        automaticallyChecksForUpdates = automatic
        lastUpdateCheckDate = lastCheck
        self.nextCheckDate = nextCheckDate
    }

    func checkForUpdates() {
        checkCount += 1
        lastUpdateCheckDate = nextCheckDate
        notify()
    }

    func observe(_ onChange: @escaping @MainActor () -> Void) {
        observers.append(onChange)
    }

    /// A change made outside Settings (Sparkle's own prompt, an update cycle), announced to observers.
    func simulateExternal(automatic: Bool? = nil, date: Date?? = nil) {
        if let automatic { automaticallyChecksForUpdates = automatic }
        if let date { lastUpdateCheckDate = date }
        notify()
    }

    private func notify() { observers.forEach { $0() } }
}
