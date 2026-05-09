import Foundation
import Observation

/// User-controlled app settings, persisted via UserDefaults.
/// Single source of truth across the panel and Settings scene.
@MainActor
@Observable
final class AppSettings {
    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Keys.appearance) ?? AppearanceMode.auto.rawValue
        self.appearance = AppearanceMode(rawValue: raw) ?? .auto
    }

    private enum Keys {
        static let appearance = "todragdo.appearance"
    }
}
