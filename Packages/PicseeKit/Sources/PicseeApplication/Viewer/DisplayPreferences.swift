import Observation

public enum DisplayAppearance: String, Codable, Sendable {
    case system, light, dark
}

/// App-level layout only. Search is deliberately not Codable preference state.
public struct DisplayPreferences: Codable, Equatable, Sendable {
    public var alwaysShowTools: Bool
    public var filmstripExpanded: Bool
    public var appearance: DisplayAppearance
    public init(alwaysShowTools: Bool = false, filmstripExpanded: Bool = false, appearance: DisplayAppearance = .system) {
        self.alwaysShowTools = alwaysShowTools
        self.filmstripExpanded = filmstripExpanded
        self.appearance = appearance
    }

    private enum CodingKeys: String, CodingKey { case alwaysShowTools, filmstripExpanded, appearance }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        alwaysShowTools = try values.decode(Bool.self, forKey: .alwaysShowTools)
        filmstripExpanded = try values.decode(Bool.self, forKey: .filmstripExpanded)
        appearance = DisplayAppearance(rawValue: try values.decodeIfPresent(String.self, forKey: .appearance) ?? "") ?? .system
    }
}

@MainActor public protocol DisplayPreferencesObserver: AnyObject {
    func preferencesDidChange(_ preferences: DisplayPreferences)
}

@MainActor public protocol DisplayPreferencesStore: AnyObject {
    var value: DisplayPreferences { get set }
    func observe(_ observer: any DisplayPreferencesObserver)
}

/// P1-09 supplies real persistence. All windows share this one observable store.
@MainActor @Observable public final class InMemoryDisplayPreferencesStore: DisplayPreferencesStore {
    private struct WeakObserver {
        weak var value: (any DisplayPreferencesObserver)?
    }
    private var observers: [WeakObserver] = []
    public var value: DisplayPreferences {
        didSet {
            observers.removeAll { $0.value == nil }
            for observer in observers { observer.value?.preferencesDidChange(value) }
        }
    }
    public func observe(_ observer: any DisplayPreferencesObserver) {
        observers.append(WeakObserver(value: observer))
    }
    public init(_ value: DisplayPreferences = .init()) { self.value = value }
}
