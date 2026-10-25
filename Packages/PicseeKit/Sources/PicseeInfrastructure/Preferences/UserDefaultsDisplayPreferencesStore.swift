import Foundation
import PicseeApplication

@MainActor public final class UserDefaultsDisplayPreferencesStore: DisplayPreferencesStore {
    private static let key = "displayPreferences.v1"
    private let defaults: UserDefaults
    private struct WeakObserver { weak var value: (any DisplayPreferencesObserver)? }
    private var observers: [WeakObserver] = []
    private var storedValue: DisplayPreferences

    public var value: DisplayPreferences {
        get { storedValue }
        set {
            var normalized = newValue
            normalized.gridSidebarWidth = DisplayPreferences.normalizedSidebarWidth(normalized.gridSidebarWidth)
            guard normalized != storedValue else { return }
            storedValue = normalized
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            if let data = try? encoder.encode(normalized) { defaults.set(data, forKey: Self.key) }
            observers.removeAll { $0.value == nil }
            for observer in observers { observer.value?.preferencesDidChange(normalized) }
        }
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        storedValue = defaults.data(forKey: Self.key).flatMap {
            try? JSONDecoder().decode(DisplayPreferences.self, from: $0)
        } ?? DisplayPreferences()
    }

    public func observe(_ observer: any DisplayPreferencesObserver) {
        observers.append(WeakObserver(value: observer))
    }
}
