import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Wrapper around SwiftUI's native `ColorPicker` that round-trips the
/// selected color through a hex string (the persisted representation
/// on `Project.colorHex`). The chrome is the system color well.
public struct ColorSwatchPicker: View {
    @Binding var hex: String

    public init(hex: Binding<String>) {
        self._hex = hex
    }

    public var body: some View {
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
    /// `#RRGGBB` string. Returns nil if the color can't be converted
    /// (e.g. pattern colors).
    var hexRGBString: String? {
        #if os(macOS)
        guard let rgb = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        let r = rgb.redComponent, g = rgb.greenComponent, b = rgb.blueComponent
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #endif
        func byte(_ v: CGFloat) -> Int { Int(round(max(0, min(1, v)) * 255)) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
