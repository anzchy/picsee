import Observation

/// App-level layout only. Search is deliberately not Codable preference state.
public struct DisplayPreferences: Codable, Equatable, Sendable {
    public var alwaysShowTools: Bool
    public var filmstripExpanded: Bool
    public init(alwaysShowTools: Bool = false, filmstripExpanded: Bool = false) {
        self.alwaysShowTools = alwaysShowTools
        self.filmstripExpanded = filmstripExpanded
    }
}

@MainActor public protocol DisplayPreferencesStore: AnyObject {
    var value: DisplayPreferences { get set }
}

/// P1-09 supplies real persistence. All windows share this one observable store.
@MainActor @Observable public final class InMemoryDisplayPreferencesStore: DisplayPreferencesStore {
    public var value: DisplayPreferences
    public init(_ value: DisplayPreferences = .init()) { self.value = value }
}
