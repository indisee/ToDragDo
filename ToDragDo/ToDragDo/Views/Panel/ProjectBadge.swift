import SwiftUI
import ToDragDoCore
import ToDragDoUI

/// Compact, colored project chip that doubles as a control. Drives
/// picking the project for new items, filtering the list, or
/// reassigning a single row's project.
///
/// Built on `Button` + `.popover` rather than `Menu` because the system
/// menu wraps its label in a control that strips custom background and
/// foreground styling — once a third project was added (knocking the
/// flip shortcut out), the chip lost its color fill and the per-row
/// dot rendered as a gray system tint.
struct ProjectBadge: View {
    enum Style {
        /// Pill with a name label — used in the input bar.
        case named
        /// Solid square — used as the list filter corner.
        case square
        /// Tiny dot — used as the per-row project indicator.
        case dot
    }

    /// What the badge represents and how taps mutate it.
    enum Behavior {
        /// Single-value pick. `current == nil` is a fallback display
        /// state (the item's project was deleted) — the popover never
        /// offers "No Project" as a selectable row, so `onPick` only
        /// fires with real project ids. `allowFlip` enables the
        /// two-projects one-tap-swap shortcut used by the input bar.
        case single(current: UUID?, allowFlip: Bool, onPick: (UUID) -> Void)
        /// Multi-value pick used by the list filter. Empty set = "All".
        /// `.none` in the set matches unassigned items.
        case multi(selected: Set<UUID?>, onToggle: (UUID?) -> Void, onAll: () -> Void)
    }

    @Environment(Repository.self) private var repository

    let behavior: Behavior
    let style: Style

    @State private var showingPicker = false

    var body: some View {
        Button(action: tap) { chipLabel }
            .buttonStyle(.plain)
            .help(tooltip)
            .popover(isPresented: $showingPicker, arrowEdge: popoverEdge) {
                ProjectPickerPopover(behavior: behavior) {
                    showingPicker = false
                }
                .environment(repository)
            }
    }

    private var popoverEdge: Edge {
        switch style {
        case .named, .square: return .top
        case .dot: return .leading
        }
    }

    // MARK: - Tap

    private func tap() {
        switch behavior {
        case let .single(current, allowFlip, onPick):
            let projects = repository.projects
            if allowFlip, projects.count == 2, current != nil,
               let other = projects.first(where: { $0.id != current }) {
                onPick(other.id)
                return
            }
            if projects.isEmpty { return }
            showingPicker = true
        case .multi:
            guard !repository.projects.isEmpty else { return }
            showingPicker = true
        }
    }

    // MARK: - Tooltip

    private var tooltip: String {
        switch behavior {
        case let .single(current, _, _):
            return repository.project(for: current)?.name ?? "No Project"
        case let .multi(selected, _, _):
            if selected.isEmpty { return "All Projects" }
            var names = repository.projects
                .filter { selected.contains($0.id) }
                .map(\.name)
            if selected.contains(nil) { names.insert("No Project", at: 0) }
            return names.joined(separator: ", ")
        }
    }

    // MARK: - Chip rendering

    @ViewBuilder
    private var chipLabel: some View {
        switch style {
        case .named: namedLabel
        case .square: squareLabel
        case .dot: dotLabel
        }
    }

    private var namedLabel: some View {
        let primary = primaryColor
        let text = primaryName
        return HStack(spacing: 6) {
            Circle()
                .fill(primary)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(primary.opacity(0.16))
        )
        .overlay(
            Capsule().strokeBorder(primary.opacity(0.45), lineWidth: 0.5)
        )
    }

    private var squareLabel: some View {
        let color = primaryColor
        let count: Int = {
            if case let .multi(selected, _, _) = behavior { return selected.count }
            return 0
        }()
        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(.black.opacity(0.18), lineWidth: 0.5)
                )
            if count > 1 {
                Text("\(count)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 2)
                    .background(Capsule().fill(.black.opacity(0.65)))
                    .offset(x: 4, y: -4)
            }
        }
        .accessibilityLabel(tooltip)
    }

    private var dotLabel: some View {
        Circle()
            .fill(primaryColor)
            .frame(width: 4, height: 4)
            .accessibilityLabel(tooltip)
    }

    /// Color shown on the chip itself. Multi mode with empty selection
    /// (= "All") is rendered gray; everything else uses the chip's
    /// project color, falling back to gray when nothing's resolvable.
    private var primaryColor: Color {
        switch behavior {
        case let .single(current, _, _):
            return repository.project(for: current)?.color ?? .gray
        case let .multi(selected, _, _):
            // "All" and "more than one" both render gray — the chip
            // only reflects a project's color when exactly one is
            // selected and the picker collapses to a single value.
            if selected.count == 1, let id = selected.first {
                return repository.project(for: id)?.color ?? .gray
            }
            return .gray
        }
    }

    private var primaryName: String {
        switch behavior {
        case let .single(current, _, _):
            if current == nil { return "No Project" }
            return repository.project(for: current)?.name ?? "No Project"
        case let .multi(selected, _, _):
            if selected.isEmpty { return "All" }
            if selected.count == 1, let entry = selected.first {
                if entry == nil { return "No Project" }
                return repository.project(for: entry)?.name ?? "No Project"
            }
            return "\(selected.count) projects"
        }
    }
}

/// Popover body used by every `ProjectBadge`. Single-select rows close
/// the popover on tap; multi-select rows toggle without closing so the
/// user can change several projects in one open.
private struct ProjectPickerPopover: View {
    @Environment(Repository.self) private var repository

    let behavior: ProjectBadge.Behavior
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if case .multi = behavior {
                allRow
                Divider().opacity(0.4)
                noProjectRow
                Divider().opacity(0.4)
            }
            ForEach(repository.projects) { project in
                row(for: project)
                if project.id != repository.projects.last?.id {
                    Divider().opacity(0.4)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 180)
        // Suppress the macOS keyboard-focus ring that would otherwise
        // land on the first row when the popover opens.
        .focusEffectDisabled()
    }

    /// Toggle the unassigned-items bucket in the filter. Only rendered
    /// in `.multi` mode — "no project" is a fallback state for items
    /// whose project was deleted, never something the user picks
    /// explicitly when assigning a project.
    @ViewBuilder
    private var noProjectRow: some View {
        let isSelected: Bool = {
            if case let .multi(set, _, _) = behavior { return set.contains(nil) }
            return false
        }()
        Button {
            if case let .multi(_, onToggle, _) = behavior {
                onToggle(nil)
            }
        } label: {
            HStack(spacing: 8) {
                checkmark(visible: isSelected)
                Circle()
                    .strokeBorder(.secondary.opacity(0.6), lineWidth: 1)
                    .frame(width: 12, height: 12)
                Text("No Project")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }

    @ViewBuilder
    private var allRow: some View {
        let selected: Bool = {
            if case let .multi(set, _, _) = behavior { return set.isEmpty }
            return false
        }()
        Button {
            if case let .multi(_, _, onAll) = behavior {
                onAll()
            }
        } label: {
            HStack(spacing: 8) {
                checkmark(visible: selected)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray)
                    .frame(width: 12, height: 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(.black.opacity(0.18), lineWidth: 0.5)
                    )
                Text("All Projects")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }

    @ViewBuilder
    private func row(for project: Project) -> some View {
        let isSelected: Bool = {
            switch behavior {
            case let .single(current, _, _): return current == project.id
            case let .multi(set, _, _): return set.contains(project.id)
            }
        }()
        Button {
            switch behavior {
            case let .single(_, _, onPick):
                // Apply the pick first so the parent re-renders the chip
                // this frame. Defer the popover dismiss to the next
                // runloop tick — calling `dismiss()` in the same tick
                // batches both state changes into one SwiftUI transaction
                // that NSPopover's dismissal then holds back, which is
                // what made single-picks feel ~1 s late (filter multi
                // picks didn't, because they never call `dismiss()`).
                onPick(project.id)
                DispatchQueue.main.async { dismiss() }
            case let .multi(_, onToggle, _):
                onToggle(project.id)
            }
        } label: {
            HStack(spacing: 8) {
                checkmark(visible: isSelected)
                Circle()
                    .fill(project.color)
                    .frame(width: 12, height: 12)
                Text(project.name)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }

    @ViewBuilder
    private func checkmark(visible: Bool) -> some View {
        Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.primary)
            .opacity(visible ? 1 : 0)
            .frame(width: 12)
    }
}

/// Button style with a hover highlight; AppKit's plain button style
/// flattens the row and removes any feedback.
private struct RowButtonStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(hover ? Color.primary.opacity(0.08) : .clear)
            )
            .onHover { hover = $0 }
    }
}
