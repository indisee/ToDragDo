import AppKit
import SwiftUI

/// User-selectable appearance preference. `auto` follows the system.
enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case light
    case dark
    case auto

    var id: String { rawValue }

    /// LocalizedStringKey so `Text(mode.displayName)` flows through the
    /// string catalog instead of being treated as a verbatim string.
    var displayName: LocalizedStringKey {
        switch self {
        case .light: "Light"
        case .dark:  "Dark"
        case .auto:  "Auto"
        }
    }

    /// `nil` means "follow the system" — handed to `.preferredColorScheme(_:)`.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark:  .dark
        case .auto:  nil
        }
    }

    /// Direct AppKit binding. `nil` lets the system choose.
    /// Used to override SwiftUI's `.preferredColorScheme` which can leave
    /// chrome stuck in a previous appearance after switching to `auto`.
    var nsAppearance: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark:  NSAppearance(named: .darkAqua)
        case .auto:  nil
        }
    }
}
