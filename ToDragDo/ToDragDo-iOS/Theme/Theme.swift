import SwiftUI

/// Visual tokens shared across the folder tab views. iOS variant — same
/// values as macOS but `rowHeight` widens to 44 to match the system tap
/// target.
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
        rowHeight: 44,
        bodySize: 15,
        captionSize: 12,
        cornerRadius: 10,
        accent: Color(red: 94 / 255, green: 92 / 255, blue: 230 / 255), // #5E5CE6
        expandedMaxHeight: 480
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
