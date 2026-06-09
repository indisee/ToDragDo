import SwiftUI
import ToDragDoCore

/// One folder tab — Today, Tomorrow, Limbo, or Done. Composition:
/// NavigationStack > InputBar (sticky) > optional DoneSummaryRow > ItemListView.
/// Project filter sits in the navigation bar trailing slot.
struct FolderTabView: View {
    let folder: Folder

    @State private var summaryMode: SummaryMode?
    @State private var summaryState = SummaryWindowState(mode: .day)
    @Environment(PanelState.self) private var panelState
    @Environment(AppSettings.self) private var settings
    @Environment(ScreenCaptureMonitor.self) private var captureMonitor

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                InputBar()
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                if hideForCapture {
                    Text("List hidden — sharing screen.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 16)
                } else {
                    if folder == .done {
                        DoneSummaryRow { mode in
                            summaryState.reset(to: mode)
                            summaryMode = mode
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                    ItemListView(folder: folder)
                }
            }
            .navigationTitle(folder.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProjectBadge(
                        behavior: .multi(
                            selected: panelState.filterProjectIds,
                            onToggle: { panelState.toggleFilterProject($0) },
                            onAll: { panelState.filterProjectIds = [] }
                        ),
                        style: .square
                    )
                }
            }
            .sheet(item: $summaryMode) { _ in
                SummaryView()
                    .environment(summaryState)
                    .presentationDetents([.large])
            }
        }
    }
}

private extension FolderTabView {
    var hideForCapture: Bool {
        settings.hideFromScreenSharing && captureMonitor.isCaptured
    }
}

extension SummaryMode: Identifiable {
    public var id: String { rawValue }
}

private extension Folder {
    var title: String {
        switch self {
        case .today:    "Today"
        case .tomorrow: "Tomorrow"
        case .libmo:    "Limbo"
        case .done:     "Done"
        }
    }
}
