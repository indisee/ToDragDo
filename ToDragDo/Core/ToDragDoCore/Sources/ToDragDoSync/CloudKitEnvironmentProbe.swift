import Foundation
#if os(macOS)
import Security
#endif

/// Reads the actual entitlement values baked into the signed app binary at
/// runtime. The CloudKit framework reads
/// `com.apple.developer.icloud-container-environment` from the signed
/// entitlements at startup to pick which CloudKit environment (Development
/// vs Production) to talk to — so if the value here disagrees with what you
/// put in `ToDragDo.entitlements`, the build wasn't re-signed with the new
/// file, or Xcode's signing pipeline stripped/overrode it.
///
/// The probe relies on `SecTaskCreateFromSelf` / `SecTaskCopyValueForEntitlement`,
/// which are macOS-only. iOS returns a fixed "not probed" summary —
/// CloudKit picks its environment from the signed entitlement the same
/// way, but the introspection API isn't part of the public iOS SDK.
public enum CloudKitEnvironmentProbe {
    public static var entitlementValue: String? {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        var unmanagedError: Unmanaged<CFError>?
        let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.icloud-container-environment" as CFString,
            &unmanagedError
        )
        unmanagedError?.release()
        guard let value else { return nil }
        if let string = value as? String {
            return string
        }
        if let array = value as? [String] {
            return array.joined(separator: ", ")
        }
        return String(describing: value)
        #else
        return nil
        #endif
    }

    /// Info.plist key that iOS targets fill from the per-configuration
    /// `TODRAGDO_CLOUDKIT_ENV` build setting. It must match the
    /// `icloud-container-environment` in that configuration's entitlements
    /// file; iOS can't read its own entitlements at runtime, so this is the
    /// stand-in there.
    public static let infoPlistKey = "TDCloudKitEnvironment"

    /// Environment declared in Info.plist, ignoring an unexpanded
    /// `$(TODRAGDO_CLOUDKIT_ENV)` placeholder.
    public static var infoPlistValue: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String,
              !value.isEmpty, !value.hasPrefix("$(")
        else { return nil }
        return value
    }

    /// Best available answer to "which CloudKit environment does this
    /// binary talk to": the signed entitlement on macOS, the Info.plist
    /// value on iOS, `nil` when neither is known.
    public static var resolved: String? {
        entitlementValue ?? infoPlistValue
    }

    public static var summary: String {
        #if os(macOS)
        switch entitlementValue {
        case .none:
            return "not set — CloudKit chooses based on build config"
        case .some(let value):
            return value
        }
        #else
        if let value = infoPlistValue {
            return "\(value) (from Info.plist)"
        }
        return "not probed on iOS (CloudKit uses the signed entitlement)"
        #endif
    }
}
