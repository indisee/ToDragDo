import SwiftUI

/// Visual tokens shared across the panel.
///
/// Two directions exist in the design — Index (compact) and Dark Glass.
/// For now we ship Index defaults and parameterize by EnvironmentValues so
/// alternate themes can be wired in later without touching call sites.
struct Theme: Sendable {
    let rowHeight: CGFloat
    let bodySize: CGFloat
    let captionSize: CGFloat
    let cornerRadius: CGFloat
    let accent: Color
    /// Maximum height for an expanded item before its body becomes
    /// internally scrollable.
    let expandedMaxHeight: CGFloat

    static let index = Theme(
        rowHeight: 28,
        bodySize: 13,
        captionSize: 11,
        cornerRadius: 10,
        accent: Color(red: 94 / 255, green: 92 / 255, blue: 230 / 255), // #5E5CE6
        expandedMaxHeight: 380
    )
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .index
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
