import Observation

/// One state owner per window. It never creates a native window.
@MainActor @Observable public final class ViewerSession {
    private let preferencesStore: any DisplayPreferencesStore
    public var searchTerm = ""
    public var displayPreferences: DisplayPreferences { preferencesStore.value }
    public init(preferencesStore: any DisplayPreferencesStore = InMemoryDisplayPreferencesStore()) {
        self.preferencesStore = preferencesStore
    }
}
