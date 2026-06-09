import SwiftUI

/// User-selectable appearance preference. `auto` follows the system.
/// iOS variant — no AppKit binding (macOS had `nsAppearance` for the
/// imperative `NSApp.appearance` override path).
enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case light
    case dark
    case auto

    var id: String { rawValue }

    var displayName: String {
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
}
