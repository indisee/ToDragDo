import SwiftUI
import ToDragDoCore
import ToDragDoUI

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
    @Environment(AppSettings.self) private var settings

    private var isDropping: Bool { session.target == .input }
    private var isEditing: Bool { panelState.editingItemId != nil }

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        @Bindable var state = panelState
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                leadingControl
                if isDropping {
                    Color.clear.frame(height: theme.bodySize + 6)
                } else {
                    TextField(placeholder, text: $state.inputDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: theme.bodySize))
                        .focused($isFieldFocused)
                        .onSubmit { Task { await submit() } }
                        .onExitCommand {
                            if isEditing { panelState.endEdit() }
                        }
                        .onChange(of: panelState.editingItemId) { _, newValue in
                            if newValue != nil { isFieldFocused = true }
                        }
                    ProjectBadge(
                        behavior: badgeBehavior,
                        style: .named
                    )
                }
            }

            if !state.pendingAttachments.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(state.pendingAttachments.enumerated()), id: \.offset) { index, attachment in
                        AttachmentChip(
                            attachment: attachment,
                            // Panel padding + InputBar padding + the chip's own badge,
                            // remove button and spacing.
                            maxLabelWidth: max(80, settings.panelWidth - 110)
                        ) {
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

    private var placeholder: String {
        isEditing ? "Edit and press Return…" : "Type, paste, or drop…"
    }

    /// Project chip behavior. In add mode the chip drives the per-input
    /// `inputProjectId`. In edit mode it reflects the item being edited
    /// and reassigns its project immediately on pick (consistent with
    /// the per-row dot — independent of the Return-to-save note edit).
    /// Chip behavior. Edit mode mutates the local `editingProjectId`
    /// (committed alongside the note on Return); add mode mutates
    /// `inputProjectId`. Either way the badge change is pure UI — no
    /// repository write, no CloudKit push — until submit.
    ///
    /// New items default to the first available project rather than
    /// "no project" — the unassigned state is a deletion fallback, not
    /// something the user picks while creating a row.
    private var badgeBehavior: ProjectBadge.Behavior {
        if panelState.editingItemId != nil {
            return .single(
                current: panelState.editingProjectId,
                allowFlip: true,
                onPick: { panelState.editingProjectId = $0 }
            )
        }
        return .single(
            current: panelState.inputProjectId ?? repository.projects.first?.id,
            allowFlip: true,
            onPick: { panelState.inputProjectId = $0 }
        )
    }

    /// Leading slot. Edit mode swaps in a clickable cancel icon; add
    /// mode shows a static plus/paperclip indicator.
    @ViewBuilder
    private var leadingControl: some View {
        if isEditing {
            Button(action: { panelState.endEdit() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: theme.bodySize, weight: .medium))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("Cancel edit")
        } else {
            Image(systemName: panelState.pendingAttachments.isEmpty ? "plus" : "paperclip")
                .font(.system(size: theme.bodySize, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func submit() async {
        let note = panelState.inputDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editId = panelState.editingItemId {
            // Editing path: rewrite the existing item's note + project
            // in one update, then restore the pre-edit draft.
            let projectId = panelState.editingProjectId
            do {
                try await repository.update(id: editId) { item in
                    var payload = ItemPayload.decode(item.payload)
                    payload.note = note
                    if let data = try? payload.encoded() {
                        item.payload = data
                    }
                    if projectId != item.projectId {
                        item.projectId = projectId
                    }
                }
            } catch {
                print("InputBar edit failed: \(error)")
            }
            panelState.endEdit()
            return
        }

        let attachments = panelState.pendingAttachments
        guard !note.isEmpty || !attachments.isEmpty else { return }
        do {
            let payload = ItemPayload(note: note, attachments: attachments)
            let typeIdentifier = attachments.first?.typeIdentifier ?? "text/plain"
            try await repository.add(
                folder: panelState.selectedFolder,
                typeIdentifier: typeIdentifier,
                payload: try payload.encoded(),
                projectId: panelState.inputProjectId ?? repository.projects.first?.id
            )
            panelState.inputDraft = ""
            panelState.pendingAttachments = []
        } catch {
            print("InputBar submit failed: \(error)")
        }
    }
}
