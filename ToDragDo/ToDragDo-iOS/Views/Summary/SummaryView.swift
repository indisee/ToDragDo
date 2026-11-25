import SwiftUI
import ToDragDoCore
import ToDragDoUI

/// Done-items review sheet. iOS variant — presented from the Done tab
/// via `.sheet`. Top: segmented Day/Week picker, then chevron-paged
/// period header. Below: SummaryItemRow per item.
struct SummaryView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(Repository.self) private var repository
    @Environment(PanelState.self) private var panelState
    @Environment(SummaryWindowState.self) private var state

    private let calendar: Calendar = .autoupdatingCurrent

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    expandPills
                    Spacer(minLength: 0)
                    ProjectBadge(
                        behavior: .multi(
                            selected: panelState.filterProjectIds,
                            onToggle: { panelState.toggleFilterProject($0) },
                            onAll: { panelState.filterProjectIds = [] }
                        ),
                        style: .square
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                header
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                Divider()
                itemList
                    .padding(.top, 8)
            }
            .navigationTitle("Done summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var expandPills: some View {
        HStack(spacing: 2) {
            pill(label: "Closed", isSelected: !panelState.allExpanded) {
                panelState.allExpanded = false
            }
            pill(label: "Open", isSelected: panelState.allExpanded) {
                panelState.allExpanded = true
            }
        }
    }

    @ViewBuilder
    private func pill(label: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: theme.captionSize, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .foregroundStyle(isSelected ? Color.primary : .secondary)
                .background(
                    Capsule().fill(isSelected ? theme.accent.opacity(0.12) : Color.clear)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: previous) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)

            Text(periodLabel)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            Button(action: next) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
    }

    private var itemList: some View {
        let items = filteredItems
        return Group {
            if items.isEmpty {
                Text("No items finished in this \(state.mode == .day ? "day" : "week").")
                    .font(.system(size: theme.bodySize))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: panelState.allExpanded ? 0 : 4) {
                        ForEach(items) { item in
                            SummaryItemRow(item: item)
                                .padding(.horizontal, 8)
                            if !panelState.allExpanded, item.id != items.last?.id {
                                Divider().opacity(0.4)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var filteredItems: [Item] {
        let interval = currentInterval
        let dones = repository.items[.done] ?? []
        let projectFilter = panelState.filterProjectIds
        return dones
            .filter { interval.contains($0.completedAt ?? $0.updatedAt) }
            .filter { projectFilter.isEmpty || projectFilter.contains($0.projectId) }
            .sorted { ($0.completedAt ?? $0.updatedAt) < ($1.completedAt ?? $1.updatedAt) }
    }

    private var currentInterval: DateInterval {
        switch state.mode {
        case .day:
            let end = calendar.date(byAdding: .day, value: 1, to: state.anchor) ?? state.anchor
            return DateInterval(start: state.anchor, end: end)
        case .week:
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: state.anchor) ?? state.anchor
            return DateInterval(start: state.anchor, end: end)
        }
    }

    private var periodLabel: String {
        let interval = currentInterval
        switch state.mode {
        case .day:
            return state.anchor.formatted(date: .complete, time: .omitted)
        case .week:
            let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            let startStr = state.anchor.formatted(.dateTime.day().month(.abbreviated))
            let endStr = lastDay.formatted(.dateTime.day().month(.abbreviated).year())
            return "\(startStr) — \(endStr)"
        }
    }

    private func previous() { shift(by: -1) }
    private func next() { shift(by: 1) }

    private func shift(by step: Int) {
        let component: Calendar.Component = state.mode == .day ? .day : .weekOfYear
        if let next = calendar.date(byAdding: component, value: step, to: state.anchor) {
            state.anchor = SummaryWindowState.normalize(next, mode: state.mode, calendar: calendar)
        }
    }
}
