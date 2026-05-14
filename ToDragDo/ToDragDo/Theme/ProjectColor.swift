import SwiftUI
import ToDragDoCore

/// SwiftUI bridge for the project palette and helpers around it.
enum ProjectColor {
    /// Suggested colors offered in the Projects settings pane when the
    /// user creates a new project. Same hex strings used for the seed
    /// projects come first so they read as the "primary" choices.
    static let palette: [String] = [
        Project.workColorHex,
        Project.personalColorHex,
        "#FF6B6B", // coral
        "#FF9F0A", // orange
        "#5AC8FA", // sky
        "#0A84FF", // blue
        "#BF5AF2", // purple
        "#FF2D55", // pink
        "#30D158", // emerald
        "#64D2FF"  // cyan
    ]

    static func color(forHex hex: String) -> Color {
        var trimmed = hex.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else {
            return .gray
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }
}

extension Project {
    var color: Color { ProjectColor.color(forHex: colorHex) }
}
