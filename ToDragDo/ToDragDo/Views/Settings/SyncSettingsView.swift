import SwiftUI
import ToDragDoCore

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

    var body: some View {
        // Plain VStack (not Form/.grouped) so the pane sizes to its actual
        // content height — matches the General/Appearance panes' pattern
        // of `.padding(20).frame(width:)` with no height constraint.
        VStack(alignment: .leading, spacing: 16) {
            if let notice = storageHealth.notice {
                StorageNoticeBanner(notice: notice)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Providers")
                    .font(.headline)
                HStack(spacing: 6) {
                    Text("iCloud environment:")
                        .foregroundStyle(.secondary)
                    Text(CloudKitEnvironmentProbe.summary)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .font(.caption)
                if coordinator.statuses.isEmpty {
                    Text("No sync providers configured.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(coordinator.statuses.enumerated()), id: \.element.id) { idx, status in
                            if idx > 0 { Divider() }
                            ProviderRow(
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
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(20)
        .frame(width: 480)
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
        if status.providerId == "icloud" {
            await accountWatcher.setUserPreference(newValue)
            if newValue {
                await coordinator.sync("icloud")
            }
        } else {
            coordinator.setEnabled(newValue, for: status.providerId)
        }
    }
}

private struct StorageNoticeBanner: View {
    let notice: StorageHealth.Notice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(notice.title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)
            Text(notice.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
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

private struct ProviderRow: View {
    let status: SyncStatus
    let resyncInFlight: Bool
    let onToggle: (Bool) -> Void
    let onSyncNow: () -> Void
    let onResyncAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(status.displayName)
                    .font(.headline)
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { status.enabled },
                        set: onToggle
                    )
                )
                .labelsHidden()
            }

            HStack(spacing: 12) {
                metric("Last sync", value: relative(status.lastSuccess))
                metric("Pending", value: "\(status.pendingPushCount)")
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

            if let error = status.lastError {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button("Copy Error") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(error, forType: .string)
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                }
                .padding(8)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 4)
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
        }
    }

    private func relative(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: .now)
    }
}

private func makeSyncSettingsPreviewHost() -> some View {
    let storage = try! StorageFactory.makeItemStorage(inMemory: true)
    let repo = Repository(storage: storage)
    let coordinator = SyncCoordinator(applier: repo)
    coordinator.register(NoopRemoteAdapter(providerId: "icloud", displayName: "iCloud"))
    coordinator.setEnabled(true, for: "icloud")
    let settings = AppSettings()
    let watcher = CloudKitAccountWatcher(
        containerIdentifier: "iCloud.com.turtle.todragdo.sync.container",
        coordinator: coordinator,
        settings: settings
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
        .frame(width: 480, height: 360)
}

#Preview {
    makeSyncSettingsPreviewHost()
}
