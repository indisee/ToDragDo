import SwiftUI
import ToDragDoCore
import ToDragDoSync

/// More tab — `NavigationStack` over a `List` of `NavigationLink`s that
/// push the individual settings panes. Replaces the Phase 1 stub.
struct MoreView: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ProjectsSettingsView()
                    } label: {
                        Label("Projects", systemImage: "folder")
                    }
                    NavigationLink {
                        SyncSettingsView()
                    } label: {
                        SyncRowLabel(status: coordinator.statuses.first)
                    }
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("Appearance", systemImage: "paintbrush")
                    }
                    NavigationLink {
                        GeneralSettingsView()
                    } label: {
                        Label("General", systemImage: "gearshape")
                    }
                }

                Section {
                    NavigationLink {
                        TrashView()
                    } label: {
                        Label("Trash", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}

/// Sync row carries a live last-sync caption in the trailing slot so the
/// user can see fresh-vs-stale without drilling in.
private struct SyncRowLabel: View {
    let status: SyncStatus?

    var body: some View {
        HStack {
            Label("Sync", systemImage: "arrow.triangle.2.circlepath.icloud")
            Spacer()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var caption: String {
        guard let status else { return "" }
        if let date = status.lastSuccess {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .abbreviated
            return f.localizedString(for: date, relativeTo: .now)
        }
        return "Never"
    }
}
