import Testing
import PicseeApplication

@Test func issue215EntryPointLanguageFollowsResolvedBundleLocalization() {
    #expect(EntryPointLanguage(preferredLocalization: "zh-Hans") == .simplifiedChinese)
    #expect(EntryPointLanguage(preferredLocalization: "en") == .english)
    #expect(EntryPointLanguage(preferredLocalization: "fr") == .english)
}

@Test func issue215EntryPointModelCoversEveryReleaseSurfaceEntry() {
    let expectedComingSoon: Set<EntryPoint> = [
        .keyboardShortcuts, .contextMenu, .filmstrip, .favorites, .recents, .footerInfo, .footerDisplay,
    ]
    #expect(Set(EntryPoint.allCases) == expectedComingSoon.union([.reportIssue, .diagnostics]))
    #expect(Set(EntryPoint.allCases.map(\.rawValue)).count == EntryPoint.allCases.count)
    #expect(EntryPoint.reportIssueURL.absoluteString == "https://github.com/anzchy/picsee/issues/new?template=bug_report.yml")

    for entry in EntryPoint.allCases {
        #expect(EntryPointState.allCases.contains(entry.state))
        if expectedComingSoon.contains(entry) {
            #expect(entry.state == .comingSoon)
            #expect(!entry.isEnabled)
            #expect(!entry.isFocusable)
            #expect(entry.keyEquivalent == nil)
            #expect(entry.accessibilityLabel(for: .english) == "Coming Soon")
            #expect(entry.accessibilityLabel(for: .simplifiedChinese) == "即将推出")
        } else {
            #expect(entry.state == .implemented)
            #expect(entry.isEnabled)
            #expect(entry.isFocusable)
        }
    }
}
