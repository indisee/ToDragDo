import SwiftUI

/// Hover-revealed action icons on a row.
/// Pure UI: receives the action set + a single dispatch closure.
struct HoverActions: View {
    let actions: [RowAction]
    let perform: (RowAction) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(actions) { action in
                Button { perform(action) } label: {
                    Image(systemName: action.systemImage)
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(action.helpText)
            }
        }
    }
}
