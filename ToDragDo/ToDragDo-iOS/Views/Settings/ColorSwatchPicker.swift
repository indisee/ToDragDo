import SwiftUI
import UIKit

/// iOS port of the macOS `ColorSwatchPicker`. Same affordance — SwiftUI's
/// `ColorPicker` color well — but hex round-trips through `UIColor` since
/// `NSColor` is AppKit-only.
struct ColorSwatchPicker: View {
    @Binding var hex: String

    var body: some View {
        ColorPicker("", selection: colorBinding, supportsOpacity: false)
            .labelsHidden()
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { ProjectColor.color(forHex: hex) },
            set: { newColor in
                if let encoded = newColor.hexRGBString {
                    hex = encoded
                }
            }
        )
    }
}

private extension Color {
    /// `#RRGGBB` string in sRGB. Returns nil if the color can't be
    /// converted (e.g. pattern colors).
    var hexRGBString: String? {
        let ui = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let ri = Int(round(max(0, min(1, r)) * 255))
        let gi = Int(round(max(0, min(1, g)) * 255))
        let bi = Int(round(max(0, min(1, b)) * 255))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}
