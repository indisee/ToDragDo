import Foundation
#if os(macOS)
import Security
#endif

/// Whether this binary may talk to CloudKit at all.
///
/// `CKContainer(identifier:)` traps (SIGTRAP) when the signed app lacks the
/// `com.apple.developer.icloud-container-identifiers` entitlement for that
/// container. That entitlement only survives signing with a team
/// certificate and a matching provisioning profile, so an ad-hoc signed
/// macOS build (or one signed for another team) has none. Check this before
/// creating any `CKContainer`; when it's `false` the app runs local-only.
public enum CloudKitAvailability {
    /// `true` when the signed entitlements list
    /// `CloudKitConfig.containerIdentifier`.
    public nonisolated static let isAvailable: Bool =
        isEntitled(for: CloudKitConfig.containerIdentifier)

    public nonisolated static func isEntitled(for containerIdentifier: String) -> Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        var unmanagedError: Unmanaged<CFError>?
        let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.icloud-container-identifiers" as CFString,
            &unmanagedError
        )
        unmanagedError?.release()
        guard let identifiers = value as? [String] else { return false }
        return identifiers.contains(containerIdentifier)
        #else
        // iOS can't read its own entitlements, and an iOS app can't be
        // installed without a provisioning profile, so it always has them.
        return true
        #endif
    }
}
