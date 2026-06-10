import SwiftUI
import UIKit
import ToDragDoCore
import ToDragDoSync

/// Sync pane (More → Sync). One row per registered provider — for now
/// just iCloud. Mirrors the macOS pane; the only platform delta is
/// `UIPasteboard` in place of `NSPasteboard` for "Copy Error".
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
                        if status.providerId == "icloud" {
                            HStack(spacing: 4) {
                                Text("Environment:")
                                Text(CloudKitEnvironmentProbe.summary)
                                    .monospaced()
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
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
                    UIPasteboard.general.string = error
                }
                .controlSize(.small)
            }
        }
    }
}
