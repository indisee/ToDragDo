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

    public static var summary: String {
        #if os(macOS)
        switch entitlementValue {
        case .none:
            return "not set — CloudKit chooses based on build config"
        case .some(let value):
            return value
        }
        #else
        return "not probed on iOS (CloudKit uses the signed entitlement)"
        #endif
    }
}
