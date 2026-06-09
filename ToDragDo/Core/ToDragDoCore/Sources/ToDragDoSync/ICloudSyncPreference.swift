import Foundation

/// Host-side persisted "user wants iCloud sync on" flag. `AppSettings`
/// (or the iOS equivalent) conforms — keeps `CloudKitAccountWatcher`
/// independent of any particular settings store while still letting the
/// watcher write the flag back when the user toggles the Settings UI.
@MainActor
public protocol ICloudSyncPreference: AnyObject {
    var iCloudSyncEnabled: Bool { get set }
}
