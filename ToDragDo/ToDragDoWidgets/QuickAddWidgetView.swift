import SwiftUI
import ToDragDoCore
import ToDragDoIntents
import WidgetKit

struct QuickAddWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        switch family {
        case .systemSmall:
            small
        case .systemMedium:
            medium
        case .accessoryRectangular:
            accessoryRect
        case .accessoryInline:
            Link("Add to Today", destination: DeepLink.inputURL(folder: .today))
        default:
            small
        }
    }

    private var small: some View {
        Link(destination: DeepLink.inputURL(folder: .today)) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.tint)
                Spacer(minLength: 0)
                Text("Add to Today")
                    .font(.headline)
                    .lineLimit(1)
                Text("ToDragDo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var medium: some View {
        VStack(spacing: 8) {
            folderButton(.today, title: "Today", system: "sun.max")
            HStack(spacing: 8) {
                folderButton(.tomorrow, title: "Tomorrow", system: "arrow.right.circle.fill")
                folderButton(.libmo, title: "Limbo", system: "tray.circle.fill")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var accessoryRect: some View {
        Link(destination: DeepLink.inputURL(folder: .today)) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                Text("Add to Today")
                    .font(.headline)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.circle.fill")
            }
        }
    }

    private func folderButton(_ folder: Folder, title: String, system: String) -> some View {
        Link(destination: DeepLink.inputURL(folder: folder)) {
            HStack(spacing: 8) {
                Image(systemName: system)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
                    .widgetAccentable()
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(buttonFill)
            )
            .foregroundStyle(.primary)
        }
    }

    /// Tinted / clear Home Screen modes render every pixel as a single
    /// color keyed by alpha, so an opaque fill turns into a solid block
    /// that swallows the label. Use a translucent fill there instead.
    private var buttonFill: AnyShapeStyle {
        renderingMode == .fullColor
            ? AnyShapeStyle(.background.secondary)
            : AnyShapeStyle(Color.primary.opacity(0.15))
    }
}
