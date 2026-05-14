import SwiftUI
import ToDragDoCore

/// Projects pane in the Settings scene.
///
/// Lets the user rename and recolor any project, add new ones, and
/// delete custom projects (the seed Work project is undeletable — it's
/// the migration fallback for orphaned items).
struct ProjectsSettingsView: View {
    @Environment(Repository.self) private var repository

    @State private var newName: String = ""
    @State private var newColor: String = ProjectColor.palette.first ?? Project.workColorHex
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            list
            Divider()
            addRow
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 16)
        .frame(width: 480, height: 360)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(repository.projects) { project in
                    ProjectRow(project: project) { action in
                        handle(action, on: project)
                    }
                    Divider().opacity(0.4)
                }
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            ColorSwatchPicker(hex: $newColor)
            TextField("New project", text: $newName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitNew)
            Button("Add", action: submitNew)
                .disabled(trimmedNewName.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var trimmedNewName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitNew() {
        let name = trimmedNewName
        guard !name.isEmpty else { return }
        Task {
            do {
                try await repository.addProject(name: name, colorHex: newColor)
                newName = ""
                errorMessage = nil
            } catch {
                errorMessage = "Couldn't add project: \(error.localizedDescription)"
            }
        }
    }

    private func handle(_ action: ProjectRow.Action, on project: Project) {
        Task {
            do {
                switch action {
                case .rename(let value):
                    try await repository.renameProject(id: project.id, to: value)
                case .recolor(let hex):
                    try await repository.recolorProject(id: project.id, to: hex)
                case .delete:
                    try await repository.deleteProject(id: project.id)
                }
                errorMessage = nil
            } catch {
                errorMessage = "Action failed: \(error.localizedDescription)"
            }
        }
    }
}

private struct ProjectRow: View {
    enum Action {
        case rename(String)
        case recolor(String)
        case delete
    }

    let project: Project
    let onAction: (Action) -> Void

    @State private var draftName: String
    @State private var colorHex: String

    init(project: Project, onAction: @escaping (Action) -> Void) {
        self.project = project
        self.onAction = onAction
        self._draftName = State(initialValue: project.name)
        self._colorHex = State(initialValue: project.colorHex)
    }

    var body: some View {
        HStack(spacing: 10) {
            ColorSwatchPicker(hex: Binding(
                get: { colorHex },
                set: { newValue in
                    colorHex = newValue
                    if newValue != project.colorHex {
                        onAction(.recolor(newValue))
                    }
                }
            ))

            TextField("", text: $draftName)
                .textFieldStyle(.plain)
                .onSubmit(commitRename)
                .onChange(of: project.name) { _, new in
                    if new != draftName { draftName = new }
                }

            Spacer(minLength: 0)

            if project.id != Project.workId {
                Button(role: .destructive) {
                    onAction(.delete)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete (items move to Work)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onChange(of: project.colorHex) { _, new in
            if new != colorHex { colorHex = new }
        }
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != project.name else {
            draftName = project.name
            return
        }
        onAction(.rename(trimmed))
    }
}
