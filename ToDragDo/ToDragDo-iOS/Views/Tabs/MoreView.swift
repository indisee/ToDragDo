import SwiftUI
import ToDragDoCore
import ToDragDoSync
import ToDragDoUI

/// More tab — `NavigationStack` over a `List` of `NavigationLink`s that
/// push the individual settings panes. Replaces the Phase 1 stub.
struct MoreView: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(Repository.self) private var repository
    @Environment(AppSettings.self) private var settings

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ProjectsSettingsView()
                    } label: {
                        DetailRowLabel(
                            title: "Projects",
                            systemImage: "folder",
                            detail: "\(repository.projects.count)"
                        )
                    }
                    NavigationLink {
                        SyncSettingsView()
                    } label: {
                        SyncRowLabel(status: coordinator.statuses.first)
                    }
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        DetailRowLabel(
                            title: "Appearance",
                            systemImage: "paintbrush",
                            detail: settings.appearance.displayName
                        )
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
                        DetailRowLabel(
                            title: "Trash",
                            systemImage: "trash",
                            detail: "\(repository.trashItems.count)"
                        )
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}

/// Label with a secondary detail in the trailing slot — the standard
/// `List` disclosure chevron still appears because `NavigationLink`
/// inserts it. Mirrors the iOS Settings.app "Name → value" pattern.
private struct DetailRowLabel: View {
    let title: String
    let systemImage: String
    let detail: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Sync row carries a live last-sync caption in the trailing slot so the
/// user can see fresh-vs-stale without drilling in. The caption is wrapped
/// in a `TimelineView` so it keeps aging between SyncTicker fires (the
/// row would otherwise only re-render when an observable mutates, which
/// is roughly once per 20 s tick — making the user see "Just now" for
/// most of the window).
private struct SyncRowLabel: View {
    let status: SyncStatus?

    var body: some View {
        HStack {
            Label("Sync", systemImage: "arrow.triangle.2.circlepath.icloud")
            Spacer()
            TimelineView(.periodic(from: .now, by: 5)) { context in
                Text(caption(now: context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func caption(now: Date) -> String {
        guard let status else { return "" }
        return relativeSyncTime(from: status.lastSuccess, now: now)
    }
}
