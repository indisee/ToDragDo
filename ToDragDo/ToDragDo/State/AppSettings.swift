import CoreGraphics
import Foundation
import Observation
import ToDragDoCore

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
    /// blink entirely. Synced across devices via the same change-record
    /// pipe that carries items and projects — `bindToSync(_:)` hooks
    /// emit on local writes and apply on remote pulls. The per-item
    /// idle timestamp (`Item.limboEnteredAt`) still rides the item
    /// record itself; this field only carries the user's threshold.
    var limboBlinkDays: Int {
        didSet {
            let clamped = Self.clampLimboBlinkDays(limboBlinkDays)
            if clamped != limboBlinkDays {
                limboBlinkDays = clamped
                return
            }
            defaults.set(limboBlinkDays, forKey: Keys.limboBlinkDays)
            // Skip the emit when we're applying a remote snapshot — the
            // sync path sets the value through this same property to
            // share clamping/persistence, but it shouldn't echo back.
            guard !isApplyingRemote else { return }
            let now = Date.now
            defaults.set(now.timeIntervalSinceReferenceDate, forKey: Keys.limboBlinkDaysAt)
            emitLimboBlinkDays(now: now)
        }
    }

    private let defaults: UserDefaults
    @ObservationIgnored private weak var repository: Repository?
    @ObservationIgnored private var isApplyingRemote = false

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

    /// Wires the synced settings (currently just `limboBlinkDays`) to
    /// the existing change-record pipe. Called once at launch after
    /// the `Repository` is constructed.
    func bindToSync(_ repository: Repository) {
        self.repository = repository
        repository.onRemoteSettings = { [weak self] snapshot, ts in
            self?.applyRemoteSettings(snapshot, at: ts)
        }
    }

    /// `ts` of the last `limboBlinkDays` write this device produced or
    /// applied. Compared against incoming snapshots to keep the merge
    /// last-write-wins without growing a SwiftData table for one int.
    private var limboBlinkDaysAppliedAt: Date {
        let raw = defaults.double(forKey: Keys.limboBlinkDaysAt)
        return raw == 0 ? .distantPast : Date(timeIntervalSinceReferenceDate: raw)
    }

    private func applyRemoteSettings(_ snapshot: SettingsSnapshot, at ts: Date) {
        guard let value = snapshot.limboBlinkDays else { return }
        guard ts > limboBlinkDaysAppliedAt else { return }
        let clamped = Self.clampLimboBlinkDays(value)
        defaults.set(ts.timeIntervalSinceReferenceDate, forKey: Keys.limboBlinkDaysAt)
        if clamped == limboBlinkDays { return }
        isApplyingRemote = true
        defer { isApplyingRemote = false }
        limboBlinkDays = clamped
    }

    private func emitLimboBlinkDays(now: Date) {
        let snapshot = SettingsSnapshot(limboBlinkDays: limboBlinkDays)
        let repository = repository
        Task { @MainActor in
            try? await repository?.emitSettingsChange(snapshot, at: now)
        }
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
        static let limboBlinkDaysAt = "todragdo.limboBlinkDays.appliedAt"
    }
}
