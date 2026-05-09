import SwiftUI
import ToDragDoCore

/// Top-of-panel input row. Currently text-only — drag-and-drop visual
/// state lands when the ContentTypeProvider system is wired up.
struct InputBar: View {
    @Environment(\.theme) private var theme
    @Environment(Repository.self) private var repository
    @Environment(PanelState.self) private var panelState

    var body: some View {
        @Bindable var state = panelState
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: theme.bodySize, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Type, paste, or drop…", text: $state.inputDraft)
                .textFieldStyle(.plain)
                .font(.system(size: theme.bodySize))
                .onSubmit { Task { await submit() } }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    private func submit() async {
        let text = panelState.inputDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            try await repository.add(
                folder: panelState.selectedFolder,
                typeIdentifier: "text/plain",
                payload: Data(text.utf8)
            )
            panelState.inputDraft = ""
        } catch {
            // Round 1: swallow; surface in UI in a later round.
            print("InputBar add failed: \(error)")
        }
    }
}
