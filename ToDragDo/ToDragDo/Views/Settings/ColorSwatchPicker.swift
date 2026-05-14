import SwiftUI

/// Small colored square that, on click, opens a popover with the
/// `ProjectColor.palette` laid out as a grid of swatches. The currently
/// selected color shows a check overlay.
///
/// Built as Button + popover for the same reason `ProjectBadge` is —
/// `Menu` wraps its label and strips the colored fill, which made the
/// per-project color in Settings look indistinguishable from a plain
/// disabled control.
struct ColorSwatchPicker: View {
    @Binding var hex: String
    var diameter: CGFloat = 20

    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            RoundedRectangle(cornerRadius: 5)
                .fill(ProjectColor.color(forHex: hex))
                .frame(width: diameter, height: diameter)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(.black.opacity(0.18), lineWidth: 0.5)
                )
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(1)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .offset(x: 3, y: 3)
                }
        }
        .buttonStyle(.plain)
        .help("Change color")
        .popover(isPresented: $showing, arrowEdge: .top) {
            grid
                .padding(10)
                .focusEffectDisabled()
        }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.fixed(26), spacing: 6), count: 5)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(ProjectColor.palette, id: \.self) { value in
                Button {
                    hex = value
                    showing = false
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(ProjectColor.color(forHex: value))
                            .frame(width: 24, height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(.black.opacity(0.18), lineWidth: 0.5)
                            )
                        if value.lowercased() == hex.lowercased() {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(value)
            }
        }
    }
}
