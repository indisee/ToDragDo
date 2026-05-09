import SwiftUI
import ToDragDoCore

/// Top-of-panel input row.
///
/// - Type a note and press Return to add a text item.
/// - Drag text/URL/file/image onto this row to stage an attachment;
///   it shows as a chip beneath the field, the typed note becomes the
///   item's body, and Return commits both as one new item.
///
/// While the cursor is over this row during a drag, the text field and
/// chip are removed from the hierarchy. That's what lets the
/// `.dropTarget` overlay claim the entire input area — otherwise the
/// underlying `NSTextField` registers for `.url`/`.fileURL` and pastes
/// a path string instead of yielding the bytes.
struct InputBar: View {
    @Environment(\.theme) private var theme
    @Environment(Repository.self) private var repository
    @Environment(PanelState.self) private var panelState
    @Environment(DragSession.self) private var session

    private var isDropping: Bool { session.target == .input }

    var body: some View {
        @Bindable var state = panelState
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: leadingIcon)
                    .font(.system(size: theme.bodySize, weight: .medium))
                    .foregroundStyle(.secondary)
                if isDropping {
                    Color.clear.frame(height: theme.bodySize + 6)
                } else {
                    TextField("Type, paste, or drop…", text: $state.inputDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: theme.bodySize))
                        .onSubmit { Task { await submit() } }
                }
            }

            if !state.pendingAttachments.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(state.pendingAttachments.enumerated()), id: \.offset) { index, attachment in
                        AttachmentChip(attachment: attachment) {
                            state.pendingAttachments.remove(at: index)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .strokeBorder(.separator, lineWidth: 0.5)
                .opacity(isDropping ? 0 : 1)
        )
        .dropTarget(
            .input,
            label: "Drop to add",
            icon: "plus",
            types: DropTargetTypes.withText,
            onAttachment: { attachment in
                panelState.pendingAttachments.append(attachment)
            }
        )
    }

    private var leadingIcon: String {
        panelState.pendingAttachments.isEmpty ? "plus" : "paperclip"
    }

    private func submit() async {
        let note = panelState.inputDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = panelState.pendingAttachments
        guard !note.isEmpty || !attachments.isEmpty else { return }
        do {
            let payload = ItemPayload(note: note, attachments: attachments)
            let typeIdentifier = attachments.first?.typeIdentifier ?? "text/plain"
            try await repository.add(
                folder: panelState.selectedFolder,
                typeIdentifier: typeIdentifier,
                payload: try payload.encoded()
            )
            panelState.inputDraft = ""
            panelState.pendingAttachments = []
        } catch {
            print("InputBar submit failed: \(error)")
        }
    }
}
