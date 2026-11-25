import SwiftUI
import ToDragDoCore
import ToDragDoUI

/// Projects pane (More → Projects). Lets the user rename, recolor, add,
/// and delete projects. Deleting a project clears its items' assignments
/// (they show up under "No Project" in the filter).
struct ProjectsSettingsView: View {
    @Environment(Repository.self) private var repository

    @State private var newName: String = ""
    @State private var newColor: String = ProjectColor.palette.first ?? Project.workColorHex
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Projects") {
                ForEach(repository.projects) { project in
                    ProjectRow(project: project) { action in
                        handle(action, on: project)
                    }
                }
            }

            Section {
                HStack(spacing: 8) {
                    ColorSwatchPicker(hex: $newColor)
                    TextField("Project name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .onSubmit(submitNew)
                    Button("Add", action: submitNew)
                        .disabled(trimmedNewName.isEmpty)
                }
            } header: {
                Text("Add Project")
            } footer: {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Projects")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var trimmedNewName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitNew() {
        let name = trimmedNewName
        guard !name.isEmpty else { return }
        Task {
            do {
                _ = try await repository.addProject(name: name, colorHex: newColor)
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
                .submitLabel(.done)
                .onSubmit(commitRename)
                .onChange(of: project.name) { _, new in
                    if new != draftName { draftName = new }
                }

            Spacer(minLength: 0)

            Button(role: .destructive) {
                onAction(.delete)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
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
