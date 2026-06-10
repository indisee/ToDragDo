import Foundation
import Observation
import ToDragDoCore
import ToDragDoIntents
import ToDragDoSync

/// iOS variant of the macOS `AppSettings`. Same shape, three deltas:
/// 1. `UserDefaults` is the App Group suite so the share extension /
///    widgets see the same values.
/// 2. `panelWidth` doesn't exist — there's no resizable floating panel.
/// 3. `hideFromScreenSharing` is rewired in Phase 5 to drive a SwiftUI
///    toggle on `UIScreen.isCaptured`. The persisted value stays here.
@MainActor
@Observable
final class AppSettings: ICloudSyncPreference {
    static let limboBlinkDaysRange: ClosedRange<Int> = 0...90
    static let defaultLimboBlinkDays: Int = 7

    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    var hideFromScreenSharing: Bool {
        didSet { defaults.set(hideFromScreenSharing, forKey: Keys.hideFromScreenSharing) }
    }

    var iCloudSyncEnabled: Bool {
        didSet { defaults.set(iCloudSyncEnabled, forKey: Keys.iCloudSyncEnabled) }
    }

    var limboBlinkDays: Int {
        didSet {
            let clamped = Self.clampLimboBlinkDays(limboBlinkDays)
            if clamped != limboBlinkDays {
                limboBlinkDays = clamped
                return
            }
            defaults.set(limboBlinkDays, forKey: Keys.limboBlinkDays)
            guard !isApplyingRemote else { return }
            let now = Date.now
            defaults.set(now.timeIntervalSinceReferenceDate, forKey: Keys.limboBlinkDaysAt)
            emitLimboBlinkDays(now: now)
        }
    }

    private let defaults: UserDefaults
    @ObservationIgnored private weak var repository: Repository?
    @ObservationIgnored private var isApplyingRemote = false

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Keys.appearance) ?? AppearanceMode.auto.rawValue
        self.appearance = AppearanceMode(rawValue: raw) ?? .auto
        self.hideFromScreenSharing = defaults.object(forKey: Keys.hideFromScreenSharing) as? Bool ?? true
        self.iCloudSyncEnabled = defaults.object(forKey: Keys.iCloudSyncEnabled) as? Bool ?? true
        let storedBlinkDays = defaults.object(forKey: Keys.limboBlinkDays) as? Int
        self.limboBlinkDays = Self.clampLimboBlinkDays(storedBlinkDays ?? Self.defaultLimboBlinkDays)
    }

    /// Wire the synced settings (currently just `limboBlinkDays`) to the
    /// existing change-record pipe. Called once at launch.
    func bindToSync(_ repository: Repository) {
        self.repository = repository
        repository.onRemoteSettings = { [weak self] snapshot, ts in
            self?.applyRemoteSettings(snapshot, at: ts)
        }
    }

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

    private static func clampLimboBlinkDays(_ value: Int) -> Int {
        min(max(value, limboBlinkDaysRange.lowerBound), limboBlinkDaysRange.upperBound)
    }

    private enum Keys {
        static let appearance = "todragdo.appearance"
        static let hideFromScreenSharing = "todragdo.hideFromScreenSharing"
        static let iCloudSyncEnabled = "todragdo.sync.icloud.userEnabled"
        static let limboBlinkDays = "todragdo.limboBlinkDays"
        static let limboBlinkDaysAt = "todragdo.limboBlinkDays.appliedAt"
    }
}
