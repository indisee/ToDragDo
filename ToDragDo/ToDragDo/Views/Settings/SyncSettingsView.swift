import SwiftUI
import ToDragDoCore
import ToDragDoSync
import ToDragDoUI

/// Sync pane. Renders one row per registered provider; for now that's just
/// iCloud. Users toggle the provider on/off, force a manual sync, and see
/// the most recent attempt/success/error and pending push count.
struct SyncSettingsView: View {
    @Environment(Repository.self) private var repository
    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @Environment(CloudKitAccountWatcher.self) private var accountWatcher
    @Environment(StorageHealth.self) private var storageHealth

    @State private var resyncTarget: SyncStatus?
    @State private var resyncInFlight = false
    @State private var resyncSummary: String?
    @AppStorage(ProductionMigration.summaryKey) private var productionMigrationSummary = ""

    var body: some View {
        Form {
            if let notice = storageHealth.notice {
                Section {
                    StorageNoticeBanner(notice: notice)
                }
            }

            if coordinator.statuses.isEmpty {
                Section("Providers") {
                    Text("No sync providers configured.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(coordinator.statuses, id: \.id) { status in
                    Section {
                        ProviderRows(
                            status: status,
                            resyncInFlight: resyncInFlight && resyncTarget?.providerId == status.providerId,
                            onToggle: { newValue in
                                Task { await handleToggle(status: status, newValue: newValue) }
                            },
                            onSyncNow: {
                                Task { await coordinator.sync(status.providerId) }
                            },
                            onResyncAll: {
                                resyncTarget = status
                            }
                        )
                    } header: {
                        Text(status.displayName)
                    } footer: {
                        if status.providerId == CloudKitConfig.providerId {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text("Environment:")
                                    Text(CloudKitEnvironmentProbe.summary)
                                        .monospaced()
                                        .textSelection(.enabled)
                                }
                                if !productionMigrationSummary.isEmpty {
                                    Text("Production migration: \(productionMigrationSummary)")
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .confirmationDialog(
            "Re-sync everything to \(resyncTarget?.displayName ?? "iCloud")?",
            isPresented: Binding(
                get: { resyncTarget != nil && !resyncInFlight },
                set: { if !$0 { resyncTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: resyncTarget
        ) { target in
            Button("Re-upload every item", role: .destructive) {
                Task { await runResync(for: target) }
            }
            Button("Cancel", role: .cancel) {
                resyncTarget = nil
            }
        } message: { target in
            Text("""
            Appends a fresh current-state outbox row for every local item — including soft-deleted ones — so the next sync pushes them all to \(target.displayName) again.

            Use this after switching CloudKit environments (Dev → Prod) or to recover from a sync that silently lost data. Existing already-pushed history is untouched; this just adds new pending rows.
            """)
        }
        .alert(
            "Re-sync queued",
            isPresented: Binding(
                get: { resyncSummary != nil },
                set: { if !$0 { resyncSummary = nil } }
            ),
            presenting: resyncSummary
        ) { _ in
            Button("OK") { resyncSummary = nil }
        } message: { summary in
            Text(summary)
        }
    }

    private func runResync(for status: SyncStatus) async {
        resyncInFlight = true
        defer {
            resyncInFlight = false
            resyncTarget = nil
        }
        do {
            let count = try await repository.resyncAllItems()
            if count == 0 {
                resyncSummary = "No local items to re-sync."
            } else {
                await coordinator.sync(status.providerId)
                resyncSummary = "Queued \(count) item\(count == 1 ? "" : "s") for re-push to \(status.displayName). Watch the Pending counter."
            }
        } catch {
            resyncSummary = "Re-sync failed: \(error.localizedDescription)"
        }
    }

    private func handleToggle(status: SyncStatus, newValue: Bool) async {
        if status.providerId == CloudKitConfig.providerId {
            await accountWatcher.setUserPreference(newValue)
            if newValue {
                await coordinator.sync(CloudKitConfig.providerId)
            }
        } else {
            coordinator.setEnabled(newValue, for: status.providerId)
        }
    }
}

private struct StorageNoticeBanner: View {
    let notice: StorageHealth.Notice

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font(.headline)
                Text(notice.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var icon: String {
        switch notice {
        case .rescued: return "checkmark.shield"
        case .rebuiltEmpty: return "exclamationmark.triangle"
        case .inMemoryFallback: return "exclamationmark.octagon"
        }
    }

    private var tint: Color {
        switch notice {
        case .rescued: return .green
        case .rebuiltEmpty: return .orange
        case .inMemoryFallback: return .red
        }
    }
}

/// All the rows that belong inside a provider's Section. Returned as a
/// `Group` so the parent `Section` shows them as discrete rows rather
/// than collapsing them into one nested view.
private struct ProviderRows: View {
    let status: SyncStatus
    let resyncInFlight: Bool
    let onToggle: (Bool) -> Void
    let onSyncNow: () -> Void
    let onResyncAll: () -> Void

    var body: some View {
        Toggle("Enable sync", isOn: Binding(
            get: { status.enabled },
            set: onToggle
        ))

        LabeledContent("Last sync") {
            TimelineView(.periodic(from: .now, by: 5)) { context in
                Text(relativeSyncTime(from: status.lastSuccess, now: context.date))
                    .foregroundStyle(.secondary)
            }
        }
        LabeledContent("Pending") {
            Text("\(status.pendingPushCount)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }

        if let error = status.lastError {
            ProviderErrorRow(error: error)
        }

        HStack {
            Spacer()
            if resyncInFlight {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Re-sync All…", action: onResyncAll)
                .disabled(!status.enabled || resyncInFlight)
            Button("Sync Now", action: onSyncNow)
                .disabled(!status.enabled || resyncInFlight)
        }
    }

}

/// Format a sync timestamp as a short relative string.
/// Special-cases sub-3-second intervals to "Just now" — `RelativeDateTimeFormatter`
/// with `.abbreviated` rounds tiny positive past intervals into "in 0s" right
/// after a sync writes `lastSuccess = .now`, which reads as "in the future".
func relativeSyncTime(from date: Date?, now: Date = .now) -> String {
    guard let date else { return "Never" }
    let interval = now.timeIntervalSince(date)
    if interval < 3 { return "Just now" }
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f.localizedString(for: date, relativeTo: now)
}

private struct ProviderErrorRow: View {
    let error: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Copy Error") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(error, forType: .string)
                }
                .controlSize(.small)
            }
        }
    }
}

private func makeSyncSettingsPreviewHost() -> some View {
    let storage = try! StorageFactory.makeItemStorage(inMemory: true)
    let repo = Repository(storage: storage)
    let coordinator = SyncCoordinator(applier: repo)
    coordinator.register(NoopRemoteAdapter(providerId: CloudKitConfig.providerId, displayName: "iCloud"))
    coordinator.setEnabled(true, for: CloudKitConfig.providerId)
    let settings = AppSettings()
    let watcher = CloudKitAccountWatcher(
        containerIdentifier: CloudKitConfig.containerIdentifier,
        coordinator: coordinator,
        preference: settings
    )
    let health = StorageHealth(notice: .rescued(
        itemCount: 42,
        originalError: "loadIssueModelContainer"
    ))
    return SyncSettingsView()
        .environment(repo)
        .environment(coordinator)
        .environment(settings)
        .environment(watcher)
        .environment(health)
        .frame(width: SettingsLayout.width, height: SettingsLayout.height)
}

#Preview {
    makeSyncSettingsPreviewHost()
}
