import Foundation

/// Persists `AppSettings` as a single JSON blob in UserDefaults. SQLite is
/// reserved (per spec) for higher-volume data like trip logs/DTC history in
/// later phases — plain preferences don't need it.
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults: UserDefaults
    private let storageKey = "com.diy.obd2dashboard.appSettings.v1"

    let settings: Observable<AppSettings>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Observable(SettingsStore.load(from: defaults, key: storageKey))
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        var current = settings.value
        mutate(&current)
        settings.value = current
        persist(current)
    }

    private func persist(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func load(from defaults: UserDefaults, key: String) -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return decoded
    }
}
