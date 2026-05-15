import SwiftUI
import ToDragDoCore

/// Read-only row used inside the Done-summary window.
///
/// Deliberately *not* `ItemRow`: that row pulls in `HoverTracker` (an
/// `NSViewRepresentable` that updates SwiftUI state from
/// `updateTrackingAreas`). When the row's overlay layout flips on hover,
/// AppKit recomputes tracking areas inside the hosting view, which
/// triggers another state change, which retriggers tracking-area
/// recompute — eventually macOS aborts the window with an
/// UpdateConstraints loop assertion. Keeping the summary row built from
/// pure SwiftUI sidesteps that entirely.
///
/// What this row supports:
/// - Tap to toggle expand/collapse (uses `PanelState.expandedItemId`).
/// - Full note + attachment previews when expanded.
/// - X close button when expanded *and* the summary's "all expanded"
///   segment is off — the segment is the way to collapse everything.
struct SummaryItemRow: View {
    @Environment(\.theme) private var theme
    @Environment(Repository.self) private var repository
    @Environment(PanelState.self) private var panelState

    let item: Item

    private var payload: ItemPayload { ItemPayload.decode(item.payload) }
    private var isExpanded: Bool {
        panelState.allExpanded || panelState.expandedItemId == item.id
    }
    private var stamp: Date { item.completedAt ?? item.updatedAt }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
            if isExpanded, !payload.attachments.isEmpty {
                attachmentPreviews
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .overlay(alignment: .topTrailing) { closeOverlay }
    }

    private var mainRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            headerLine
            contentLine
        }
        .padding(.horizontal, 10)
        .frame(minHeight: theme.rowHeight)
    }

    /// One-line header: project dot, date, time. Kept on its own row so
    /// the note width below is independent of any hover/expand state.
    private var headerLine: some View {
        HStack(spacing: 6) {
            ProjectBadge(
                behavior: .single(
                    current: item.projectId,
                    allowFlip: false,
                    onPick: { _ in }
                ),
                style: .dot
            )
            .allowsHitTesting(false)
            Text(stamp, format: .dateTime.day(.twoDigits).month(.abbreviated))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(stamp, format: .dateTime.hour().minute())
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 14)
    }

    private var contentLine: some View {
        HStack(alignment: isExpanded ? .top : .center, spacing: 8) {
            noteText
            AttachmentIconStrip(attachments: payload.attachments)
                .frame(height: theme.rowHeight)
        }
    }

    @ViewBuilder
    private var noteText: some View {
        if isExpanded {
            Text(attributedDisplay)
                .font(.system(size: theme.bodySize))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: theme.rowHeight, alignment: .topLeading)
                .padding(.vertical, 6)
                .layoutPriority(1)
        } else {
            Text(attributedDisplay)
                .font(.system(size: theme.bodySize))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, minHeight: theme.rowHeight, alignment: .leading)
                .layoutPriority(1)
        }
    }

    private var attachmentPreviews: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(payload.attachments.enumerated()), id: \.offset) { _, attachment in
                AttachmentPreview(attachment: attachment)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    /// Per-row X, anchored inside the row's top-right corner. Only shown
    /// when this row is individually expanded — while the summary segment
    /// forces every row open we hide the X so a single click can't kick
    /// off a global collapse (which is what tripped the constraint-pass
    /// loop earlier). Kept inside the row's bounds so it doesn't slide
    /// under the segment bar when the first row is the one expanded.
    @ViewBuilder
    private var closeOverlay: some View {
        if isExpanded, !panelState.allExpanded {
            Button(action: collapse) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: theme.bodySize, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Close")
            .padding(.trailing, 8)
            .padding(.top, 4)
        }
    }

    private func toggle() {
        if panelState.expandedItemId == item.id {
            panelState.closeItem()
        } else {
            panelState.openItem(item.id)
        }
    }

    private func collapse() {
        panelState.closeItem()
    }

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
