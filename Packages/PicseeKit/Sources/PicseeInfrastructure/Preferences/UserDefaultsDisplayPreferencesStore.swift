import Foundation
import PicseeApplication

@MainActor public final class UserDefaultsDisplayPreferencesStore: DisplayPreferencesStore {
    private static let key = "displayPreferences.v1"
    private static let logURL = URL(fileURLWithPath: "/UserDefaults/displayPreferences.v1")
    private struct Header: Decodable { let schemaVersion: Int? }
    private struct Envelope: Codable {
        let schemaVersion: Int
        let value: DisplayPreferences
    }
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
            if let existing = defaults.data(forKey: Self.key), Self.isUnsupported(existing) {
                StoredSchema.logUnsupportedOnce(at: Self.logURL, category: "preferences")
            } else {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                if let data = try? encoder.encode(Envelope(schemaVersion: StoredSchema.current, value: normalized)) {
                    defaults.set(data, forKey: Self.key)
                }
            }
            observers.removeAll { $0.value == nil }
            for observer in observers { observer.value?.preferencesDidChange(normalized) }
        }
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), Self.isUnsupported(data) {
            StoredSchema.logUnsupportedOnce(at: Self.logURL, category: "preferences")
            storedValue = DisplayPreferences()
        } else {
            storedValue = defaults.data(forKey: Self.key).flatMap { data in
                let decoder = JSONDecoder()
                if let header = try? decoder.decode(Header.self, from: data), header.schemaVersion == StoredSchema.current {
                    return try? decoder.decode(Envelope.self, from: data).value
                }
                return try? decoder.decode(DisplayPreferences.self, from: data)
            } ?? DisplayPreferences()
        }
    }

    private static func isUnsupported(_ data: Data) -> Bool {
        guard let header = try? JSONDecoder().decode(Header.self, from: data),
              let version = header.schemaVersion else { return false }
        return version != StoredSchema.current
    }

    public func observe(_ observer: any DisplayPreferencesObserver) {
        observers.append(WeakObserver(value: observer))
    }
}
