import SwiftUI
import ToDragDoCore
import ToDragDoContentTypes

/// Read-only row used inside the Done-summary sheet. iOS variant —
/// same shape as macOS (which already used pure SwiftUI to dodge the
/// HoverTracker constraint-pass loop). Tap toggles expand/collapse,
/// `allExpanded` flips every row at once, the X close button shows
/// when an individual row is expanded *and* the segment is on
/// "Closed".
struct SummaryItemRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.contentTypes) private var contentTypes
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
        .padding(.horizontal, 12)
        .frame(minHeight: theme.rowHeight)
    }

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
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(stamp, format: .dateTime.hour().minute())
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 16)
    }

    private var contentLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
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
                .frame(maxWidth: .infinity, minHeight: theme.rowHeight, alignment: .leading)
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
                contentTypes.resolve(attachment: attachment).fullView(for: attachment)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var closeOverlay: some View {
        if isExpanded, !panelState.allExpanded {
            Button(action: collapse) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: theme.bodySize, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .padding(.trailing, 10)
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
