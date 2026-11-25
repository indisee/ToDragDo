import SwiftUI
#if os(macOS)
import AppKit
#endif

/// User-selectable appearance preference. `auto` follows the system.
public enum AppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case light
    case dark
    case auto

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .light: "Light"
        case .dark:  "Dark"
        case .auto:  "Auto"
        }
    }

    /// `nil` means "follow the system" — handed to `.preferredColorScheme(_:)`.
    public var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark:  .dark
        case .auto:  nil
        }
    }

    #if os(macOS)
    /// Direct AppKit binding. `nil` lets the system choose.
    /// Used to override SwiftUI's `.preferredColorScheme` which can leave
    /// chrome stuck in a previous appearance after switching to `auto`.
    @MainActor
    public var nsAppearance: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark:  NSAppearance(named: .darkAqua)
        case .auto:  nil
        }
    }
    #endif
}
