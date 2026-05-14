import Foundation
import Security

/// Reads the actual entitlement values baked into the signed app binary at
/// runtime. The CloudKit framework reads
/// `com.apple.developer.icloud-container-environment` from the signed
/// entitlements at startup to pick which CloudKit environment (Development
/// vs Production) to talk to — so if the value here disagrees with what you
/// put in `ToDragDo.entitlements`, the build wasn't re-signed with the new
/// file, or Xcode's signing pipeline stripped/overrode it.
enum CloudKitEnvironmentProbe {
    /// The raw entitlement value as embedded in the signed binary.
    /// Returns nil when the entitlement isn't set (CloudKit then uses its
    /// own default: Development for Debug, Production for Release).
    static var entitlementValue: String? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        var unmanagedError: Unmanaged<CFError>?
        let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.icloud-container-environment" as CFString,
            &unmanagedError
        )
        unmanagedError?.release()
        guard let value else { return nil }
        // Apple accepts both string and array shapes in this entitlement.
        if let string = value as? String {
            return string
        }
        if let array = value as? [String] {
            return array.joined(separator: ", ")
        }
        return String(describing: value)
    }

    /// Human-readable summary for surfacing in the Sync settings UI.
    static var summary: String {
        switch entitlementValue {
        case .none:
            return "not set — CloudKit chooses based on build config"
        case .some(let value):
            return value
        }
    }
}
