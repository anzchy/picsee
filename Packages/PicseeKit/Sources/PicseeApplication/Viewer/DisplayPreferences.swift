public enum DisplayAppearance: String, Codable, Sendable {
    case system, light, dark
}

/// App-level layout only. Search is deliberately not Codable preference state.
public struct DisplayPreferences: Codable, Equatable, Sendable {
    public var alwaysShowTools: Bool
    public var filmstripExpanded: Bool
    public var appearance: DisplayAppearance
    public var gridSidebarWidth: Double
    public var gridSidebarVisible: Bool
    public init(alwaysShowTools: Bool = false, filmstripExpanded: Bool = false, appearance: DisplayAppearance = .system,
                gridSidebarWidth: Double = 196, gridSidebarVisible: Bool = true) {
        self.alwaysShowTools = alwaysShowTools
        self.filmstripExpanded = filmstripExpanded
        self.appearance = appearance
        self.gridSidebarWidth = Self.normalizedSidebarWidth(gridSidebarWidth)
        self.gridSidebarVisible = gridSidebarVisible
    }

    private enum CodingKeys: String, CodingKey { case alwaysShowTools, filmstripExpanded, appearance, gridSidebarWidth, gridSidebarVisible }

    public static func normalizedSidebarWidth(_ width: Double) -> Double {
        width.isFinite ? min(320, max(160, width)) : 196
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        alwaysShowTools = try values.decode(Bool.self, forKey: .alwaysShowTools)
        filmstripExpanded = try values.decode(Bool.self, forKey: .filmstripExpanded)
        appearance = DisplayAppearance(rawValue: try values.decodeIfPresent(String.self, forKey: .appearance) ?? "") ?? .system
        gridSidebarWidth = Self.normalizedSidebarWidth((try? values.decode(Double.self, forKey: .gridSidebarWidth)) ?? 196)
        gridSidebarVisible = (try? values.decode(Bool.self, forKey: .gridSidebarVisible)) ?? true
    }
}

@MainActor public protocol DisplayPreferencesObserver: AnyObject {
    func preferencesDidChange(_ preferences: DisplayPreferences)
}

@MainActor public protocol DisplayPreferencesStore: AnyObject {
    var value: DisplayPreferences { get set }
    func observe(_ observer: any DisplayPreferencesObserver)
}

/// In-memory preferences for tests and callers that do not need persistence.
@MainActor public final class InMemoryDisplayPreferencesStore: DisplayPreferencesStore {
    private struct WeakObserver {
        weak var value: (any DisplayPreferencesObserver)?
    }
    private var observers: [WeakObserver] = []
    private var storedValue: DisplayPreferences
    public var value: DisplayPreferences {
        get { storedValue }
        set {
            var normalized = newValue
            normalized.gridSidebarWidth = DisplayPreferences.normalizedSidebarWidth(normalized.gridSidebarWidth)
            storedValue = normalized
            observers.removeAll { $0.value == nil }
            for observer in observers { observer.value?.preferencesDidChange(normalized) }
        }
    }
    public func observe(_ observer: any DisplayPreferencesObserver) {
        observers.append(WeakObserver(value: observer))
    }
    public init(_ value: DisplayPreferences = .init()) { storedValue = value }
}
