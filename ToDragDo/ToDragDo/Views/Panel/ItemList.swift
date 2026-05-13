import AppKit
import SwiftUI
import ToDragDoCore

/// Lists items for the currently-selected folder.
///
/// Pagination: 10 items per page. The page index lives on `PanelState`
/// so it survives view re-renders triggered by item edits. The footer
/// shows the visible range and a chevron + numbered page indicator;
/// it's hidden entirely when the folder fits on a single page.
struct ItemList: View {
    @Environment(\.theme) private var theme
    @Environment(Repository.self) private var repository
    @Environment(PanelState.self) private var panelState
    @Environment(PanelController.self) private var panelController

    private static let pageSize = 10

    var body: some View {
        let allItems = panelState.isTrashOpen
            ? repository.trashItems
            : (repository.items[panelState.selectedFolder] ?? [])
        VStack(spacing: 0) {
            if allItems.isEmpty {
                emptyPlaceholder
            } else {
                paginated(items: allItems)
            }
            bottomBar(items: allItems)
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func paginated(items: [Item]) -> some View {
        let totalPages = max(1, (items.count + Self.pageSize - 1) / Self.pageSize)
        let page = min(max(0, panelState.currentPage), totalPages - 1)
        let start = page * Self.pageSize
        let end = min(start + Self.pageSize, items.count)
        let visible = Array(items[start..<end])
        // Once the list spans more than one page, every page reserves
        // 10 rows of vertical space so the panel doesn't snap shorter
        // when the user lands on a partial last page.
        let missingRows = totalPages > 1 ? max(0, Self.pageSize - visible.count) : 0

        VStack(spacing: 0) {
            ForEach(visible) { item in
                ItemRow(item: item, trashMode: panelState.isTrashOpen)
                if item.id != visible.last?.id {
                    Divider().opacity(0.4)
                }
            }
            if missingRows > 0 {
                // rowHeight + 1pt accounts for the divider between rows.
                Color.clear
                    .frame(height: CGFloat(missingRows) * (theme.rowHeight + 1))
            }
            // EndDropZone appends to the underlying list, so it only
            // makes sense at the actual end. On intermediate pages we
            // still reserve its vertical slot (Color.clear of the same
            // height) so the panel doesn't grow when the user lands on
            // the last page.
            if page == totalPages - 1 {
                EndDropZone()
            } else {
                Color.clear.frame(height: EndDropZone.reservedHeight)
            }
        }
    }

    @ViewBuilder
    private func bottomBar(items: [Item]) -> some View {
        let totalPages = max(1, (items.count + Self.pageSize - 1) / Self.pageSize)
        let page = min(max(0, panelState.currentPage), totalPages - 1)
        let start = page * Self.pageSize
        let end = min(start + Self.pageSize, items.count)

        HStack(spacing: 4) {
            settingsButton
            if items.count > 0, totalPages > 1 {
                PaginationBar(
                    page: page,
                    totalPages: totalPages,
                    rangeStart: start + 1,
                    rangeEnd: end,
                    total: items.count
                ) { newPage in
                    guard newPage != page else { return }
                    panelState.currentPage = newPage
                    panelState.closeItem()
                }
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    /// Gear icon → menu with Settings / Trash / Quit. Trash toggles the
    /// hidden-folder view; the label flips to reflect current state so
    /// the same row both opens and closes it.
    private var settingsButton: some View {
        Menu {
            Button("Settings…") { panelController.showSettings() }
                .keyboardShortcut(",", modifiers: .command)
            Button(panelState.isTrashOpen ? "Hide Trash" : "Trash") {
                panelState.isTrashOpen.toggle()
            }
            Divider()
            Button("Quit ToDragDo") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: theme.captionSize, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Menu")
    }

    private var emptyPlaceholder: some View {
        Text(panelState.isTrashOpen ? "Trash is empty." : "Nothing here.")
            .font(.system(size: theme.captionSize))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
    }
}

/// Compact footer with the visible range, chevron navigation, and
/// numbered page pills. For lists with more than five pages we show
/// first / current-window / last with `…` separators so the bar stays
/// inside the panel even at the minimum width.
private struct PaginationBar: View {
    @Environment(\.theme) private var theme

    let page: Int
    let totalPages: Int
    let rangeStart: Int
    let rangeEnd: Int
    let total: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("\(rangeStart)–\(rangeEnd) of \(total)")
                .font(.system(size: theme.captionSize))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 6)
            chevron(systemImage: "chevron.left", enabled: page > 0) {
                onSelect(max(0, page - 1))
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                switch entry {
                case .page(let n): pageButton(n)
                case .gap:         gap
                }
            }
            chevron(systemImage: "chevron.right", enabled: page < totalPages - 1) {
                onSelect(min(totalPages - 1, page + 1))
            }
        }
    }

    // MARK: - Page entry plumbing

    private enum Entry { case page(Int); case gap }

    private var entries: [Entry] {
        let pages = visiblePages
        var result: [Entry] = []
        for (i, n) in pages.enumerated() {
            if i > 0, n - pages[i - 1] > 1 {
                result.append(.gap)
            }
            result.append(.page(n))
        }
        return result
    }

    private var visiblePages: [Int] {
        if totalPages <= 3 {
            return Array(0..<totalPages)
        }
        // For four or more pages, show only first / current / last —
        // gaps between them collapse into a single `…` via `entries`.
        let set: Set<Int> = [0, totalPages - 1, page]
        return set.sorted()
    }

    // MARK: - Pieces

    @ViewBuilder
    private func pageButton(_ n: Int) -> some View {
        let isCurrent = n == page
        Button {
            onSelect(n)
        } label: {
            Text("\(n + 1)")
                .font(.system(size: theme.captionSize, weight: isCurrent ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? Color.white : .primary)
                .frame(minWidth: 18, minHeight: 18)
                .padding(.horizontal, 4)
                .background(
                    Capsule()
                        .fill(isCurrent ? AnyShapeStyle(theme.accent) : AnyShapeStyle(Color.clear))
                )
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
    }

    private var gap: some View {
        Text("…")
            .font(.system(size: theme.captionSize))
            .foregroundStyle(.tertiary)
            .frame(minWidth: 12)
    }

    @ViewBuilder
    private func chevron(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: theme.captionSize, weight: .semibold))
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.35))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
