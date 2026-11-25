import SwiftUI
import ToDragDoCore
import ToDragDoUI

/// Compact, colored project chip that doubles as a control. Port of the
/// macOS ProjectBadge. The picker is presented with `.popover` —
/// SwiftUI on iPhone adapts it to a sheet automatically; the
/// `presentationCompactAdaptation(.popover)` modifier keeps it as a
/// popover on iPhone for the small project list, which reads better
/// than a half-screen sheet for 2–6 choices.
struct ProjectBadge: View {
    enum Style {
        /// Pill with a name label — used in the input bar.
        case named
        /// Solid square — used as the list filter toolbar item.
        case square
        /// Tiny dot — used as the per-row project indicator.
        case dot
    }

    enum Behavior {
        case single(current: UUID?, allowFlip: Bool, onPick: (UUID) -> Void)
        case multi(selected: Set<UUID?>, onToggle: (UUID?) -> Void, onAll: () -> Void)
    }

    @Environment(Repository.self) private var repository

    let behavior: Behavior
    let style: Style

    @State private var showingPicker = false

    var body: some View {
        Button(action: tap) {
            chipLabel
                .frame(minWidth: hitTargetSize, minHeight: hitTargetSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tooltip)
        .popover(isPresented: $showingPicker, arrowEdge: popoverEdge) {
            ProjectPickerPopover(behavior: behavior) {
                showingPicker = false
            }
            .environment(repository)
            .presentationCompactAdaptation(.popover)
        }
    }

    /// Minimum hit target. `.square` / `.named` live in the toolbar /
    /// input bar where the chip is visually small (14pt square or a
    /// pill) but the surrounding empty space looks tappable — fill it.
    /// `.dot` is the small in-row corner overlay; keeping it tight so it
    /// doesn't swallow taps meant for the row body or note text.
    private var hitTargetSize: CGFloat {
        switch style {
        case .dot:            return 16
        case .square, .named: return 44
        }
    }

    private var popoverEdge: Edge {
        switch style {
        case .named, .square: return .top
        case .dot: return .leading
        }
    }

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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(primary.opacity(0.16)))
        .overlay(Capsule().strokeBorder(primary.opacity(0.45), lineWidth: 0.5))
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
                .frame(width: 14, height: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(.black.opacity(0.18), lineWidth: 0.5)
                )
            if count > 1 {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
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
            .frame(width: 5, height: 5)
            .accessibilityLabel(tooltip)
    }

    private var primaryColor: Color {
        switch behavior {
        case let .single(current, _, _):
            return repository.project(for: current)?.color ?? .gray
        case let .multi(selected, _, _):
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
        .frame(minWidth: 200)
    }

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
                    .frame(width: 14, height: 14)
                Text("No Project")
                    .font(.system(size: 14))
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
                    .frame(width: 14, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(.black.opacity(0.18), lineWidth: 0.5)
                    )
                Text("All Projects")
                    .font(.system(size: 14))
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
                    .frame(width: 14, height: 14)
                Text(project.name)
                    .font(.system(size: 14))
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
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary)
            .opacity(visible ? 1 : 0)
            .frame(width: 14)
    }
}

/// Tap highlight for picker rows. iOS variant — the macOS version used
/// `.onHover`, which has no analogue on touch. `isPressed` flips the
/// background while the finger is down.
private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.12) : .clear)
            )
    }
}
