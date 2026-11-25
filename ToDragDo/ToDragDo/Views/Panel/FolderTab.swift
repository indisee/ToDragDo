import SwiftUI
import ToDragDoCore
import ToDragDoUI
import UniformTypeIdentifiers

/// A single folder tab in the FolderTabBar.
///
/// Tapping switches to the folder; dropping an item-drag URL onto it
/// moves the item to that folder.
struct FolderTab: View {
    @Environment(\.theme) private var theme
    @Environment(Repository.self) private var repository
    let folder: Folder
    let isSelected: Bool
    let count: Int?
    let isCompact: Bool
    /// True when this tab's count badge should pulse red — used by Limbo
    /// to surface stale items at a glance. Independent of `isSelected`
    /// so the warning is visible from any tab.
    var blinkBadge: Bool = false
    let action: () -> Void

    @State private var isDropTargeted = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if !isCompact {
                    Text(folder.displayName)
                        .font(.system(size: theme.captionSize, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(isSelected ? 1 : 0)
                }
                countBadge
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(isSelected ? Color.primary : .secondary)
            .background(background, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onDrop(of: [.url], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    @ViewBuilder
    private var countBadge: some View {
        let label = Text("\(count ?? 0)")
            .font(.system(size: theme.captionSize - 1, weight: .bold))
            .foregroundStyle(badgeForeground)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .accessibilityLabel(folder.displayName)

        if blinkBadge {
            // TimelineView drives a continuous sin-based opacity so the
            // entry frame matches the steady-state value — phaseAnimator
            // ran an `.easeInOut` from a zero starting state when the
            // row was inserted, which read as the red shape "sliding in
            // from somewhere" on folder open.
            TimelineView(.animation) { ctx in
                let phase = pulsePhase(at: ctx.date)
                label
                    .background(Color.red, in: Capsule())
                    .opacity(0.78 + 0.22 * phase)
            }
        } else if isSelected {
            label.background(theme.accent, in: Capsule())
        } else {
            label.background(theme.accent.opacity(0.12), in: Capsule())
        }
    }

    private var badgeForeground: Color {
        if blinkBadge { return .white }
        return isSelected ? .white : .secondary
    }

    private var background: Color {
        if isDropTargeted { return theme.accent.opacity(0.25) }
        if isSelected     { return theme.accent.opacity(0.12) }
        return .clear
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        Task { @MainActor in
            guard let id = await ItemDragURL.itemID(from: provider) else { return }
            try? await repository.move(id: id, to: folder)
        }
        return true
    }
}

/// 0…1 sine phase with a 0.55s full cycle. Shared between the badge
/// and the row wash so both heartbeats tick in lockstep.
@inline(__always)
func pulsePhase(at date: Date) -> Double {
    let period: Double = 0.55
    let t = date.timeIntervalSinceReferenceDate
    return (sin(t * 2 * .pi / period) + 1) / 2
}

private extension Folder {
    var displayName: LocalizedStringKey {
        switch self {
        case .today:    "Today"
        case .tomorrow: "Tomorrow"
        case .libmo:    "Limbo"
        case .done:     "Done"
        }
    }
}
