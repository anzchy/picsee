import Foundation
import Testing
import PicseeApplication
@testable import PicseeInfrastructure

@Test @MainActor func gridSidebarPreferenceSurvivesRelaunchAndLegacyPayload() throws {
    let suite = "grid-sidebar-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = UserDefaultsDisplayPreferencesStore(defaults: defaults)
    #expect(first.value.gridSidebarWidth == 196)
    #expect(first.value.gridSidebarVisible)

    var changed = first.value
    changed.gridSidebarWidth = 284
    changed.gridSidebarVisible = false
    first.value = changed
    let reopened = UserDefaultsDisplayPreferencesStore(defaults: defaults)
    #expect(reopened.value.gridSidebarWidth == 284)
    #expect(!reopened.value.gridSidebarVisible)
    changed.gridSidebarVisible = true
    reopened.value = changed
    #expect(UserDefaultsDisplayPreferencesStore(defaults: defaults).value.gridSidebarWidth == 284)

    defaults.set(Data(#"{"alwaysShowTools":false,"filmstripExpanded":false,"appearance":"system"}"#.utf8),
                 forKey: "displayPreferences.v1")
    let legacy = UserDefaultsDisplayPreferencesStore(defaults: defaults)
    #expect(legacy.value.gridSidebarWidth == 196)
    #expect(legacy.value.gridSidebarVisible)
}
