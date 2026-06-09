import SwiftUI
import ToDragDoCore
import ToDragDoContentTypes

/// A single (closed or open) item row. iOS port — Phase 2 ships tap-to-
/// open only. Phase 3 wraps this view in `RowSwipeContainer` to add the
/// two-phased swipe gesture; Phase 5+ may layer in an expanded-row
/// action panel.
///
/// Closed:
/// - One line: collapsed badge + truncated text + optional due-date
///   stamp + attachment icon strip.
///
/// Open:
/// - Multi-line text (selectable / copyable) + clickable attachment
///   previews resolved through the content-type registry.
///
/// Drag, drop, hover, and the floating action panel that lived in the
/// macOS row are intentionally absent here per PLAN-iOS.md Phase 2.
struct ItemRow: View {
    @Environment(\.theme) private var theme
    @Environment(Repository.self) private var repository
    @Environment(PanelState.self) private var panelState
    @Environment(AppSettings.self) private var settings
    @Environment(\.contentTypes) private var contentTypes

    let item: Item
    var trashMode: Bool = false

    private var isExpanded: Bool { panelState.expandedItemId == item.id }
    private var payload: ItemPayload { ItemPayload.decode(item.payload) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isExpanded {
                expandedBody
            } else {
                mainRow
            }
        }
        .background(rowBackground)
        .contentShape(Rectangle())
        .overlay(alignment: .topLeading) { projectDotCorner }
        .onTapGesture {
            if isExpanded { close() } else { open() }
        }
    }

    // MARK: - Main row

    private var mainRow: some View {
        contentLine
            .padding(.leading, 24)
            .padding(.trailing, 16)
            .padding(.top, isExpanded ? 10 : 8)
            .padding(.bottom, 8)
            .frame(minHeight: theme.rowHeight, alignment: isExpanded ? .top : .center)
    }

    /// Top-left project dot floated as an overlay so the content area
    /// can use uniform padding without reserving header space.
    private var projectDotCorner: some View {
        ProjectBadge(
            behavior: .single(
                current: item.projectId,
                allowFlip: false,
                onPick: { picked in
                    guard picked != item.projectId else { return }
                    Task {
                        try? await repository.setProject(itemId: item.id, to: picked)
                    }
                }
            ),
            style: .dot
        )
        .padding(.leading, 12)
        .padding(.top, 16)
    }

    /// Done items show completion; other folders show due-date when set.
    private var headerDate: Date? {
        if item.folder == .done { return completedStamp }
        return item.dueDate
    }

    /// Past due in non-Done folders renders in red.
    private var headerDateColor: Color {
        if item.folder != .done,
           let due = item.dueDate,
           Calendar.autoupdatingCurrent.startOfDay(for: due)
            < Calendar.autoupdatingCurrent.startOfDay(for: .now) {
            return .red
        }
        return .secondary
    }

    /// Note + optional date stamp + attachment icon strip.
    private var contentLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            noteText
            if item.folder == .done {
                AttachmentIconStrip(attachments: payload.attachments)
                if let stamp = headerDate {
                    dateStamp(stamp)
                }
            } else {
                if let stamp = headerDate {
                    dateStamp(stamp)
                }
                AttachmentIconStrip(attachments: payload.attachments)
            }
        }
    }

    private func dateStamp(_ stamp: Date) -> some View {
        Text(stamp, format: .dateTime.day(.twoDigits).month(.abbreviated))
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(headerDateColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// Fallback to `updatedAt` for items completed before `completedAt`
    /// was introduced — close enough since Done items are rarely edited.
    private var completedStamp: Date? {
        item.completedAt ?? (item.folder == .done ? item.updatedAt : nil)
    }

    @ViewBuilder
    private var noteText: some View {
        if isExpanded {
            Text(attributedDisplay)
                .font(.system(size: theme.bodySize))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .layoutPriority(1)
        } else {
            Text(attributedDisplay)
                .font(.system(size: theme.bodySize))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
    }

    // MARK: - Expanded body

    private var expandedBody: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                mainRow
                if !payload.attachments.isEmpty {
                    attachmentPreviews
                }
            }
        }
        .frame(maxHeight: theme.expandedMaxHeight)
    }

    private var attachmentPreviews: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(payload.attachments.enumerated()), id: \.offset) { _, attachment in
                contentTypes.resolve(attachment: attachment).fullView(for: attachment)
            }
        }
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Background

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        if isStaleInLimbo {
            // Pulsing red wash signals "this has sat in Limbo too long".
            // TimelineView drives a continuous sin-based opacity so the
            // initial frame already sits at its steady-state value.
            TimelineView(.animation) { ctx in
                let phase = pulsePhase(at: ctx.date)
                shape
                    .fill(.red)
                    .opacity(0.10 + 0.08 * phase)
            }
        } else {
            Color.clear
        }
    }

    private var isStaleInLimbo: Bool {
        LimboStaleness.isStale(item, threshold: settings.limboBlinkDays)
    }

    private func pulsePhase(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        return 0.5 * (1 + sin(t * 2))
    }

    // MARK: - Open / close

    private func open() {
        panelState.openItem(item.id)
        if item.folder == .libmo {
            let id = item.id
            Task {
                try? await repository.noteOpened(id: id)
            }
        }
    }

    private func close() {
        panelState.closeItem()
    }

    // MARK: - Display text

    private var displayText: String {
        if !payload.note.isEmpty { return payload.note }
        if let label = payload.attachments.first?.displayLabel, !label.isEmpty {
            return label
        }
        return "—"
    }

    private var attributedDisplay: AttributedString {
        Self.linkify(displayText)
    }

    private static let linkDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    private static func linkify(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        guard !text.isEmpty, let detector = linkDetector else { return attr }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            guard let stringRange = Range(match.range, in: text),
                  let url = match.url,
                  let lower = AttributedString.Index(stringRange.lowerBound, within: attr),
                  let upper = AttributedString.Index(stringRange.upperBound, within: attr)
            else { continue }
            let attrRange = lower..<upper
            attr[attrRange].link = url
            attr[attrRange].foregroundColor = .blue
            attr[attrRange].underlineStyle = .single
        }
        return attr
    }
}
