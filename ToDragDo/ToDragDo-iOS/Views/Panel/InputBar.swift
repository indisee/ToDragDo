import SwiftUI
import ToDragDoCore
import ToDragDoUI

/// Top-of-folder input row. iOS port — keeps the same TextField + chip
/// flow as macOS, drops the `.dropTarget` overlay (drag/drop deferred
/// to post-v1).
///
/// - Type a note and press Return to add a text item.
/// - Project chip drives the new item's project (or the editing item's
///   project while in edit mode).
/// - Pending attachments (added via Share Extension or Shortcuts in
///   later phases) render as chips beneath the field; Return commits
///   them with the typed note as one new item.
struct InputBar: View {
    @Environment(\.theme) private var theme
    @Environment(Repository.self) private var repository
    @Environment(PanelState.self) private var panelState

    private var isEditing: Bool { panelState.editingItemId != nil }

    @FocusState private var isFieldFocused: Bool
    /// Set during the brief false→true focus toggle the widget path
    /// performs to force the keyboard to re-present when the field was
    /// already logically focused (e.g. user had focus, minimized, taps
    /// the widget). Suppresses the transient `!focused` event so it
    /// doesn't clear `widgetInputMode` before the keyboard reappears.
    @State private var suppressDefocusClear = false
    /// Most recent `focusInputBarRequest` token this InputBar already
    /// acted on. Switching tabs mounts a fresh InputBar that missed
    /// the `.onChange` for an earlier token; `.onAppear` consults this
    /// to catch up without re-firing on every render.
    @State private var lastHandledFocusToken: UUID?

    var body: some View {
        @Bindable var state = panelState
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                leadingControl
                TextField(placeholder, text: $state.inputDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: theme.bodySize))
                    .submitLabel(.done)
                    .focused($isFieldFocused)
                    .onSubmit { Task { await submit() } }
                    .onChange(of: panelState.editingItemId) { _, newValue in
                        if newValue != nil { isFieldFocused = true }
                    }
                    .onChange(of: panelState.focusInputBarRequest) { _, _ in
                        applyPendingFocusIfNeeded()
                    }
                    .onAppear {
                        // Fresh InputBar mount (e.g. widget switched tabs)
                        // missed the .onChange fire — replay any pending
                        // focus request now that the view exists.
                        applyPendingFocusIfNeeded()
                    }
                    .onChange(of: isFieldFocused) { _, focused in
                        // Widget-driven quick-add hides the list while the
                        // field is focused; clearing the flag the moment
                        // focus is lost (return, tap-out, swipe-down)
                        // brings the list back.
                        if !focused && !suppressDefocusClear {
                            panelState.widgetInputMode = false
                        }
                    }
                ProjectBadge(behavior: badgeBehavior, style: .named)
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
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    private var placeholder: String {
        isEditing ? "Edit and press Return…" : "Type or paste…"
    }

    /// Chip behavior — edit mode mutates the local `editingProjectId`,
    /// add mode mutates `inputProjectId`. Either way the badge change
    /// is pure UI until Return commits.
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

    @ViewBuilder
    private var leadingControl: some View {
        if isEditing {
            Button(action: { panelState.endEdit() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: theme.bodySize, weight: .medium))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel edit")
        } else {
            Image(systemName: panelState.pendingAttachments.isEmpty ? "plus" : "paperclip")
                .font(.system(size: theme.bodySize, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    /// Force-cycle `@FocusState` to re-present the keyboard. SwiftUI is
    /// a no-op when @FocusState is set to its current value, and the
    /// system can drop the keyboard on background without flipping the
    /// logical focus — so we drop focus, then bounce it back on the
    /// next tick. The token guard makes this safe to call from both
    /// `.onChange` and `.onAppear`.
    ///
    /// Consumes the token by clearing `focusInputBarRequest` after
    /// reading it — so subsequent InputBar mounts (manual tab switch
    /// after a widget tap, settings back-nav) don't re-fire the dance
    /// against a stale value.
    private func applyPendingFocusIfNeeded() {
        guard let token = panelState.focusInputBarRequest else { return }
        guard token != lastHandledFocusToken else { return }
        lastHandledFocusToken = token
        panelState.focusInputBarRequest = nil

        suppressDefocusClear = true
        isFieldFocused = false
        Task { @MainActor in
            isFieldFocused = true
            // One more yield so any pending focus events settle before
            // we re-arm the defocus handler.
            await Task.yield()
            suppressDefocusClear = false
        }
    }

    private func submit() async {
        let note = panelState.inputDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editId = panelState.editingItemId {
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
