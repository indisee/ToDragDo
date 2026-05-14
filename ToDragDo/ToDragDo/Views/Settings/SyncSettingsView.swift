import SwiftUI
import ToDragDoCore

/// Sync pane. Renders one row per registered provider; for now that's just
/// iCloud. Users toggle the provider on/off, force a manual sync, and see
/// the most recent attempt/success/error and pending push count.
struct SyncSettingsView: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @Environment(CloudKitAccountWatcher.self) private var accountWatcher
    @Environment(StorageHealth.self) private var storageHealth

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
                                onToggle: { newValue in
                                    Task { await handleToggle(status: status, newValue: newValue) }
                                },
                                onSyncNow: {
                                    Task { await coordinator.sync(status.providerId) }
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
    let onToggle: (Bool) -> Void
    let onSyncNow: () -> Void

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
                Button("Sync Now", action: onSyncNow)
                    .disabled(!status.enabled)
            }

            if let error = status.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
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
        .environment(coordinator)
        .environment(settings)
        .environment(watcher)
        .environment(health)
        .frame(width: 480, height: 360)
}

#Preview {
    makeSyncSettingsPreviewHost()
}
