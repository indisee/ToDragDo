import AppIntents
import SwiftUI
import ToDragDoCore
import ToDragDoIntents
import WidgetKit

struct ProjectListWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ProjectListEntry

    var body: some View {
        switch family {
        case .systemLarge:
            list(maxRows: 7)
        case .systemMedium:
            list(maxRows: 4)
        case .accessoryRectangular:
            accessory
        default:
            list(maxRows: 4)
        }
    }

    private func list(maxRows: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            chipStrip
            if entry.items.isEmpty {
                emptyState
            } else {
                ForEach(Array(entry.items.prefix(maxRows))) { item in
                    Link(destination: DeepLink.itemURL(id: item.id)) {
                        row(item)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var chipStrip: some View {
        HStack(spacing: 6) {
            ForEach(entry.projects) { project in
                chip(project)
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ project: ProjectChip) -> some View {
        let isSelected = project.id == entry.selectedProjectId
        return Button(intent: SetWidgetProjectIntent(projectId: project.id.uuidString)) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: project.colorHex))
                    .frame(width: 7, height: 7)
                Text(project.name)
                    .font(.caption2.weight(isSelected ? .bold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isSelected ? Color(hex: project.colorHex).opacity(0.25) : Color.clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color(hex: project.colorHex) : Color.secondary.opacity(0.4),
                        lineWidth: isSelected ? 1 : 0.5
                    )
            )
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private func row(_ item: ProjectListItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: glyph(for: item.folder))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(item.title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 3)
    }

    private var emptyState: some View {
        Text("No items in \(entry.selectedProject?.name ?? "this project")")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessory: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.selectedProject?.name ?? "Project")
                .font(.caption2.weight(.semibold))
            if let first = entry.items.first {
                Text(first.title)
                    .font(.headline)
                    .lineLimit(1)
                if let second = entry.items.dropFirst().first {
                    Text(second.title)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No items")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func glyph(for folder: Folder) -> String {
        switch folder {
        case .today: return "sun.max"
        case .tomorrow: return "arrow.right.circle.fill"
        case .libmo: return "tray.circle.fill"
        case .done: return "checkmark.circle"
        }
    }
}

private extension Color {
    init(hex: String) {
        let trimmed = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard let value = UInt32(trimmed, radix: 16), trimmed.count == 6 else {
            self = .accentColor
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
