import AppKit
import SwiftUI
import ToDragDoUI

/// Wrapper around SwiftUI's native `ColorPicker` that round-trips the
/// selected color through a hex string (the persisted representation
/// on `Project.colorHex`). The chrome is the system color well — same
/// affordance the user already knows from Notes, Reminders, etc.
struct ColorSwatchPicker: View {
    @Binding var hex: String

    var body: some View {
        ColorPicker("", selection: colorBinding, supportsOpacity: false)
            .labelsHidden()
            .help("Change color")
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
    /// `#RRGGBB` string in the device RGB color space. Returns nil if
    /// the color can't be converted (e.g. pattern colors).
    var hexRGBString: String? {
        guard let rgb = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
