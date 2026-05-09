import SwiftUI
import ToDragDoCore
import UniformTypeIdentifiers

/// A single (collapsed) item row.
///
/// - Hover reveals folder-specific action icons.
/// - Quick click toggles fold/unfold.
/// - Press + drag the row body to reorder; dropping on a row places the
///   dragged item immediately above it.
struct ItemRow: View {
    @Environment(\.theme) private var theme
    @Environment(Repository.self) private var repository
    @Environment(PanelState.self) private var panelState

    let item: Item

    @State private var isHovering = false
    @State private var isDropTargeted = false

    private var actions: [RowAction] { RowAction.actions(for: item.folder) }

    private var isExpanded: Bool { panelState.expandedItemId == item.id }

    private var payload: ItemPayload { ItemPayload.decode(item.payload) }

    var body: some View {
        VStack(spacing: 0) {
            collapsedContent
            if isExpanded {
                expandedContent
                    .transition(.opacity)
            }
        }
        .background(rowBackground)
        .overlay(alignment: .top) { dropIndicator }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) {
                panelState.toggleExpanded(item.id)
            }
        }
        .draggable(item.id.uuidString) {
            dragPreview
        }
        .dropDestination(for: String.self) { droppedIds, _ in
            handleReorderDrop(droppedIds)
        } isTargeted: { isDropTargeted = $0 }
        .dropTarget(
            .item(item.id),
            label: "Attach to item",
            icon: "paperclip"
        ) { attachment in
            Task {
                try? await repository.addAttachment(to: item.id, attachment)
            }
        }
    }

    // MARK: - Collapsed row

    private var collapsedContent: some View {
        HStack(spacing: 8) {
            TypeBadge(typeIdentifier: item.typeIdentifier)
            Text(displayText)
                .font(.system(size: theme.bodySize))
                .lineLimit(1)
                .truncationMode(.tail)
            AttachmentIconStrip(attachments: extraAttachments)
            Spacer(minLength: 8)
            if isHovering {
                HoverActions(actions: actions) { action in
                    dispatch(action)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: theme.rowHeight)
    }

    // MARK: - Expanded body

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !payload.note.isEmpty {
                Text(payload.note)
                    .font(.system(size: theme.bodySize))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(payload.attachments.enumerated()), id: \.offset) { _, attachment in
                AttachmentPreview(attachment: attachment)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    /// Attachments to render as mini icons next to the row text.
    /// The leading `TypeBadge` already shows the first attachment's kind,
    /// so the strip starts from the second one.
    private var extraAttachments: [Attachment] {
        Array(payload.attachments.dropFirst())
    }

    // MARK: - Drag preview

    private var dragPreview: some View {
        HStack(spacing: 6) {
            TypeBadge(typeIdentifier: item.typeIdentifier)
            Text(displayText)
                .font(.system(size: theme.bodySize))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
    }

    // MARK: - Visual feedback

    @ViewBuilder
    private var rowBackground: some View {
        if isHovering {
            theme.accent.opacity(0.06)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var dropIndicator: some View {
        if isDropTargeted {
            Rectangle()
                .fill(theme.accent)
                .frame(height: 2)
        }
    }

    // MARK: - Helpers

    private var displayText: String {
        if !payload.note.isEmpty { return payload.note }
        if let label = payload.attachments.first?.displayLabel, !label.isEmpty {
            return label
        }
        return "—"
    }

    private func handleReorderDrop(_ droppedIds: [String]) -> Bool {
        guard let raw = droppedIds.first, let droppedId = UUID(uuidString: raw) else {
            return false
        }
        guard droppedId != item.id else { return false }
        Task {
            try? await repository.reorder(id: droppedId, before: item.id)
        }
        return true
    }

    private func dispatch(_ action: RowAction) {
        Task {
            do {
                switch action {
                case .moveToToday:    try await repository.move(id: item.id, to: .today)
                case .moveToTomorrow: try await repository.move(id: item.id, to: .tomorrow)
                case .moveToLimbo:    try await repository.move(id: item.id, to: .libmo)
                case .markDone:       try await repository.move(id: item.id, to: .done)
                case .delete:         try await repository.softDelete(id: item.id)
                }
            } catch {
                print("ItemRow action failed: \(error)")
            }
        }
    }
}
