import SwiftUI

/// Visual tokens shared across the panel (macOS) and folder tabs (iOS).
/// iOS uses larger rows and type to match system tap targets.
public struct Theme: Sendable {
    public let rowHeight: CGFloat
    public let bodySize: CGFloat
    public let captionSize: CGFloat
    public let cornerRadius: CGFloat
    public let accent: Color
    /// Maximum height for an expanded item before its body becomes
    /// internally scrollable.
    public let expandedMaxHeight: CGFloat

    #if os(macOS)
    public static let index = Theme(
        rowHeight: 28,
        bodySize: 13,
        captionSize: 11,
        cornerRadius: 10,
        accent: Color(red: 94 / 255, green: 92 / 255, blue: 230 / 255), // #5E5CE6
        expandedMaxHeight: 380
    )
    #else
    public static let index = Theme(
        rowHeight: 44,
        bodySize: 15,
        captionSize: 12,
        cornerRadius: 10,
        accent: Color(red: 94 / 255, green: 92 / 255, blue: 230 / 255), // #5E5CE6
        expandedMaxHeight: 480
    )
    #endif
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .index
}

extension EnvironmentValues {
    public var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
