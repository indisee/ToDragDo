import SwiftUI
import ToDragDoCore

/// SwiftUI bridge for the project palette and helpers around it. Verbatim
/// port from the macOS app.
enum ProjectColor {
    static let palette: [String] = [
        Project.workColorHex,
        Project.personalColorHex,
        "#FF6B6B",
        "#FF9F0A",
        "#5AC8FA",
        "#0A84FF",
        "#BF5AF2",
        "#FF2D55",
        "#30D158",
        "#64D2FF"
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
