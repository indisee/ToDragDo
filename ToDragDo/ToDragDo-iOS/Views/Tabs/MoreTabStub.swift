import SwiftUI
import ToDragDoCore
import ToDragDoSync

/// Phase 1 placeholder for the More tab — exposes just enough to satisfy
/// the exit criterion ("Sync tab shows 'Last sync: …' populated by the
/// coordinator"). Phase 5 replaces this with full settings panes.
struct MoreTabStub: View {
    @Environment(SyncCoordinator.self) private var coordinator

    var body: some View {
        NavigationStack {
            List {
                Section("Sync") {
                    if let status = coordinator.statuses.first {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(status.displayName)
                                .font(.body.weight(.medium))
                            Text(lastSyncCaption(status))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let err = status.lastError, !err.isEmpty {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(3)
                                    .truncationMode(.tail)
                            }
                        }
                    } else {
                        Text("No sync providers registered")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("Projects, Appearance, Sync, General, Trash land in Phase 5.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("More")
        }
    }

    private func lastSyncCaption(_ status: SyncStatus) -> String {
        if let date = status.lastSuccess {
            return "Last sync: \(date.formatted(date: .omitted, time: .shortened))"
        }
        return "Last sync: never"
    }
}
