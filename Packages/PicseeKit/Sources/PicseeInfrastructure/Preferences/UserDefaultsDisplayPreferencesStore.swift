import Foundation
import Observation
import PicseeApplication

@MainActor @Observable public final class UserDefaultsDisplayPreferencesStore: DisplayPreferencesStore {
    private static let key = "displayPreferences.v1"
    private let defaults: UserDefaults
    private struct WeakObserver { weak var value: (any DisplayPreferencesObserver)? }
    @ObservationIgnored private var observers: [WeakObserver] = []

    public var value: DisplayPreferences {
        didSet {
            guard value != oldValue else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            // This fixed Codable value contains only Booleans and string enum cases.
            defaults.set(try! encoder.encode(value), forKey: Self.key)
            observers.removeAll { $0.value == nil }
            for observer in observers { observer.value?.preferencesDidChange(value) }
        }
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        value = defaults.data(forKey: Self.key).flatMap {
            try? JSONDecoder().decode(DisplayPreferences.self, from: $0)
        } ?? DisplayPreferences()
    }

    public func observe(_ observer: any DisplayPreferencesObserver) {
        observers.append(WeakObserver(value: observer))
    }
}
