import CoreGraphics
import Foundation
import Observation

/// User-controlled app settings, persisted via UserDefaults.
/// Single source of truth across the panel and Settings scene.
@MainActor
@Observable
final class AppSettings {
    /// Allowed range for the floating panel's width. Min just keeps the
    /// chevron + a stub of a folder tab visible; max stops a careless
    /// drag from filling the screen.
    static let panelWidthRange: ClosedRange<CGFloat> = 220...720
    static let defaultPanelWidth: CGFloat = 420

    /// Bounds for the "Days before Limbo starts to blink" stepper.
    /// Zero disables the feature entirely. Upper bound stops the
    /// stepper from running off into nonsense values.
    static let limboBlinkDaysRange: ClosedRange<Int> = 0...90
    static let defaultLimboBlinkDays: Int = 7

    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    var panelWidth: CGFloat {
        didSet {
            let clamped = Self.clamp(panelWidth)
            if clamped != panelWidth {
                panelWidth = clamped
                return
            }
            defaults.set(Double(panelWidth), forKey: Keys.panelWidth)
        }
    }

    /// When true, every window the app shows is excluded from screen
    /// captures, recordings, and screen sharing (`NSWindow.sharingType`
    /// is forced to `.none`). Default `true` matches the original
    /// always-on behaviour.
    var hideFromScreenSharing: Bool {
        didSet { defaults.set(hideFromScreenSharing, forKey: Keys.hideFromScreenSharing) }
    }

    /// User preference for iCloud sync. Defaults to `true`; the
    /// `CloudKitAccountWatcher` only flips the coordinator on when this is
    /// true *and* the iCloud account is available.
    var iCloudSyncEnabled: Bool {
        didSet { defaults.set(iCloudSyncEnabled, forKey: Keys.iCloudSyncEnabled) }
    }

    /// Days an item may sit untouched in Limbo before its row (and the
    /// Limbo tab's count badge) start blinking red. Zero disables the
    /// blink entirely. Persisted locally; the per-item idle timestamp
    /// (`Item.limboEnteredAt`) is what actually syncs across devices,
    /// so each user can pick their own threshold.
    var limboBlinkDays: Int {
        didSet {
            let clamped = Self.clampLimboBlinkDays(limboBlinkDays)
            if clamped != limboBlinkDays {
                limboBlinkDays = clamped
                return
            }
            defaults.set(limboBlinkDays, forKey: Keys.limboBlinkDays)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Keys.appearance) ?? AppearanceMode.auto.rawValue
        self.appearance = AppearanceMode(rawValue: raw) ?? .auto
        let storedWidth = defaults.object(forKey: Keys.panelWidth) as? Double
        self.panelWidth = Self.clamp(CGFloat(storedWidth ?? Double(Self.defaultPanelWidth)))
        self.hideFromScreenSharing = defaults.object(forKey: Keys.hideFromScreenSharing) as? Bool ?? true
        self.iCloudSyncEnabled = defaults.object(forKey: Keys.iCloudSyncEnabled) as? Bool ?? true
        let storedBlinkDays = defaults.object(forKey: Keys.limboBlinkDays) as? Int
        self.limboBlinkDays = Self.clampLimboBlinkDays(storedBlinkDays ?? Self.defaultLimboBlinkDays)
    }

    private static func clamp(_ width: CGFloat) -> CGFloat {
        min(max(width, panelWidthRange.lowerBound), panelWidthRange.upperBound)
    }

    private static func clampLimboBlinkDays(_ value: Int) -> Int {
        min(max(value, limboBlinkDaysRange.lowerBound), limboBlinkDaysRange.upperBound)
    }

    /// Reads the current persisted value of `hideFromScreenSharing`
    /// without instantiating an `AppSettings`. Used by `AppDelegate`'s
    /// window observer, which doesn't otherwise reach into the app's
    /// state graph.
    static func hideFromScreenSharing(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Keys.hideFromScreenSharing) as? Bool ?? true
    }

    private enum Keys {
        static let appearance = "todragdo.appearance"
        static let panelWidth = "todragdo.panelWidth"
        static let hideFromScreenSharing = "todragdo.hideFromScreenSharing"
        static let iCloudSyncEnabled = "todragdo.sync.icloud.userEnabled"
        static let limboBlinkDays = "todragdo.limboBlinkDays"
    }
}
