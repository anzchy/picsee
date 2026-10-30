import AppKit
import Testing
import PicseeApplication
import PicseeInfrastructure
import PicseeMacUI

@MainActor private func settingsEntryPointPanel(
    openURL: @escaping (URL) -> Void = { _ in }
) -> SettingsPanelWindow {
    let preferences = InMemoryDisplayPreferencesStore()
    return SettingsPanelWindow(
        cache: ThumbnailDiskCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
        appearanceAdapter: WindowAppearanceAdapter(preferencesStore: preferences),
        preferencesStore: preferences,
        defaults: UserDefaults(suiteName: "issue218-entry-points-\(UUID().uuidString)")!,
        openURL: openURL)
}

@MainActor private func settingsEntryPointView(_ id: String, in root: NSView) -> NSView? {
    if root.accessibilityIdentifier() == id { return root }
    for child in root.subviews {
        if let found = settingsEntryPointView(id, in: child) { return found }
    }
    return nil
}

@MainActor private func disabledSettingsControls(in root: NSView) -> [NSControl] {
    let own = (root as? NSControl).map { $0.isEnabled ? [] : [$0] } ?? []
    return own + root.subviews.flatMap(disabledSettingsControls(in:))
}

@MainActor @Test func issue218EveryGreyedSettingsControlUsesDeclaredEntryPoint() throws {
    let panel = settingsEntryPointPanel()
    defer { panel.window.close() }
    let root = try #require(panel.window.contentView)
    let expected: [String: EntryPoint] = [
        "settings.display.size": .settingsDisplayThumbnailSize,
        "settings.display.names": .settingsDisplayFileNames,
        "settings.display.fit.0": .settingsDisplayFitMode,
        "settings.display.fit.1": .settingsDisplayFitMode,
        "settings.update.automatic": .settingsUpdatesAutomaticCheck,
        "settings.update.now": .settingsUpdatesCheckNow,
    ]

    for (id, entry) in expected {
        let control = try #require(settingsEntryPointView(id, in: root) as? NSControl)
        #expect(!control.isEnabled, "\(id)")
        #expect(!control.acceptsFirstResponder, "\(id)")
        if let button = control as? NSButton {
            #expect(button.refusesFirstResponder, "\(id)")
            #expect(button.keyEquivalent.isEmpty, "\(id)")
        }
        let marker = entry.accessibilityLabel(for: .preferred)
        #expect(control.accessibilityLabel()?.contains(" · \(marker)") == true, "\(id)")
        #expect(panel.entryPoint(for: control) == entry, "\(id)")
        #expect(entry.state == .comingSoon, "\(id)")
    }

    let disabled = disabledSettingsControls(in: root)
    #expect(Set(disabled.compactMap { $0.accessibilityIdentifier() }) == Set(expected.keys))
    #expect(disabled.allSatisfy { panel.entryPoint(for: $0) != nil })
}

@MainActor @Test func issue218AboutReportIssueOpensSharedEntryPointURL() throws {
    var openedURLs: [URL] = []
    let panel = settingsEntryPointPanel(openURL: { openedURLs.append($0) })
    defer { panel.window.close() }
    panel.select(.about)
    let root = try #require(panel.window.contentView)
    let report = try #require(settingsEntryPointView("settings.about.link.0", in: root) as? NSButton)
    #expect(report.isEnabled)
    #expect(report.accessibilityLabel()?.contains(String(localized: "Coming Soon")) == false)
    #expect(panel.entryPoint(for: report) == .reportIssue)
    report.performClick(nil)
    #expect(openedURLs == [EntryPoint.reportIssueURL])
}
