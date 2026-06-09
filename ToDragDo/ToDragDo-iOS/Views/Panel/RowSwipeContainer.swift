import SwiftUI
import ToDragDoCore
import UIKit

/// Two-phased trailing swipe for an item row. Wraps an arbitrary
/// content view (the row body) and renders the folder's `RowAction`
/// set behind it on the trailing edge. The content slides over the
/// action strip; releasing snaps to one of three latch states
/// (`none`, `phase1`, `phase2`) based on how far the user pulled.
///
/// Mechanics (mirrors PLAN-iOS.md §Phase 3):
/// - Trailing swipe (`dx < 0`): reveals `primary` actions (phase 1) and
///   then `secondary` actions (phase 2) as the pull deepens.
/// - Release past ~-90% on trailing → fires the folder's default
///   destructive (rightmost primary) and snaps the row closed.
/// - `PanelState.latchedSwipeItemId` carries the currently-open row;
///   each container observes it and collapses when another row claims
///   the latch.
/// - `UIImpactFeedbackGenerator` fires on every phase boundary so the
///   user feels the latch points before releasing.
struct RowSwipeContainer<Content: View>: View {
    @Environment(Repository.self) private var repository
    @Environment(PanelState.self) private var panelState
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let item: Item
    var trashMode: Bool = false
    @ViewBuilder var content: () -> Content

    @State private var translation: CGFloat = 0
    @State private var latched: Latch = .none
    @State private var lastHapticPhase: Int = 0
    @State private var assignDateSheet: Bool = false
    @State private var assignProjectSheet: Bool = false
    /// Captured at the start of each gesture (first `onChanged` call) and
    /// read in `onEnded`. Decision logic must key off the starting latch
    /// because "where the user dragged from" determines what a release
    /// means — releasing while already at phase 2 with no movement
    /// shouldn't fire destructive.
    @GestureState private var dragStart: Latch? = nil

    /// Static stored properties aren't legal on generic structs; the
    /// constants live on the non-generic `Const` enum at file scope and
    /// this forwarder keeps call sites tidy.
    private var actionWidth: CGFloat { RowSwipeConst.actionWidth }

    enum Latch: Equatable {
        case none, phase1, phase2
    }

    // MARK: - Action sets

    private var primary: [RowAction] {
        RowAction.actions(for: item.folder, phase: .primary, inTrash: trashMode)
    }
    private var secondary: [RowAction] {
        RowAction.actions(for: item.folder, phase: .secondary, inTrash: trashMode)
    }
    private var phase1Width: CGFloat { CGFloat(primary.count) * actionWidth }
    private var phase2Width: CGFloat { CGFloat(secondary.count) * actionWidth }
    /// Total trailing reveal when both phases are exposed.
    private var fullWidth: CGFloat { phase1Width + phase2Width }
    // MARK: - Offset math

    private var latchBase: CGFloat {
        switch latched {
        case .none:   return 0
        case .phase1: return -phase1Width
        case .phase2: return -fullWidth
        }
    }

    /// Raw + clamped horizontal offset applied to the row content.
    /// Capped so the row can't slide past the trailing strip's full
    /// reveal, and so a small rightward pull doesn't visibly drag the
    /// row off the left edge.
    private var offset: CGFloat {
        max(-fullWidth, min(0, latchBase + translation))
    }

    /// 0 … 1 fraction of the trailing reveal currently exposed.
    private var trailingFraction: CGFloat {
        guard fullWidth > 0 else { return 0 }
        return min(1, max(0, -offset / fullWidth))
    }

    private var isLatched: Bool { latched != .none }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Strip stays a plain sibling of the content layer — no
            // gesture attached here so the action Buttons receive taps
            // cleanly.
            trailingActionStrip

            content()
                // Force the row body to fill the available width before
                // it gets offset; without this it sizes to its natural
                // content (which can be either narrower than the screen
                // — leaving the action strip exposed at rest — or wider
                // than the screen for long notes, blowing past the
                // ZStack's clip).
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background)
                .overlay {
                    // While latched, taps on the row body close the latch
                    // instead of opening / closing the row. The overlay
                    // disappears when not latched so the wrapped row's
                    // own tap-to-expand keeps working.
                    if isLatched {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                animate { close() }
                            }
                    }
                }
                .offset(x: offset)
                // Gesture only on the content layer so the trailing
                // action strip's button taps don't compete with it.
                // `.simultaneousGesture` lets the DragGesture coexist
                // with the enclosing ScrollView's pan — vertical
                // motion still scrolls because our `.onChanged` bails
                // when `|dy| > |dx| * 1.4`.
                .simultaneousGesture(swipeGesture)
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .onChange(of: panelState.latchedSwipeItemId) { _, newValue in
            if isLatched, newValue != item.id {
                animate { close() }
            }
        }
        .sheet(isPresented: $assignDateSheet) {
            DateAssignSheet(item: item)
        }
        .sheet(isPresented: $assignProjectSheet) {
            ProjectAssignSheet(item: item)
        }
    }

    // MARK: - Trailing strip

    private var trailingActionStrip: some View {
        HStack(spacing: 0) {
            ForEach(secondary, id: \.self) { actionButton($0) }
            ForEach(primary, id: \.self) { actionButton($0) }
        }
        .frame(maxHeight: .infinity)
    }

    private func actionButton(_ action: RowAction) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            dispatch(action)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 16, weight: .medium))
                Text(action.shortLabel)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(width: actionWidth)
            .frame(maxHeight: .infinity)
            .background(action.tint)
            // Whole tile is the hit target — without this the
            // VStack-of-text shrinks the tappable area down to the
            // glyph/label union, which is much smaller than the
            // visible tile and makes the strip feel dead.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.helpText)
    }

    // MARK: - Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragStart) { _, state, _ in
                // Capture the latch state on this gesture's first event
                // so `onEnded` can branch on where the drag began.
                // SwiftUI keeps `state` populated for the gesture's
                // lifetime and clears it after `onEnded` returns.
                if state == nil { state = latched }
            }
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                // Suppress when the user is clearly scrolling vertically.
                if abs(dy) > abs(dx) * 1.4 { return }
                translation = dx
                fireHapticOnPhaseChange()
            }
            .onEnded { value in
                let dx = value.translation.width
                let startLatch = dragStart ?? latched
                lastHapticPhase = 0

                switch startLatch {
                case .none:
                    // From collapsed: leftward reveals the trailing
                    // strip, with the deepest pull firing the folder's
                    // default destructive.
                    if dx < -0.9 * fullWidth {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        dispatch(RowAction.defaultDestructive(for: item.folder, inTrash: trashMode))
                        return
                    }
                    if dx < -0.75 * fullWidth, phase2Width > 0 {
                        latchTo(.phase2)
                    } else if dx < -0.25 * fullWidth, phase1Width > 0 {
                        latchTo(.phase1)
                    } else {
                        animate { close() }
                    }

                case .phase1:
                    // Already at phase 1 — small rightward pull closes,
                    // deeper leftward pull extends to phase 2. Releases
                    // without meaningful motion keep the latch where it
                    // was (no accidental fires).
                    if dx > 50 {
                        animate { close() }
                    } else if dx < -0.5 * phase2Width, phase2Width > 0 {
                        latchTo(.phase2)
                    } else {
                        animate {
                            translation = 0
                            latched = .phase1
                        }
                    }

                case .phase2:
                    // Already fully open. Right-ward release pulls back
                    // toward phase 1 or closed; anything else holds.
                    // No destructive fire from this state — tapping a
                    // button is the explicit commit path.
                    if dx > 0.5 * fullWidth {
                        animate { close() }
                    } else if dx > 50 {
                        latchTo(.phase1)
                    } else {
                        animate {
                            translation = 0
                            latched = .phase2
                        }
                    }
                }
            }
    }

    private func latchTo(_ newLatch: Latch) {
        animate {
            translation = 0
            latched = newLatch
        }
        panelState.latchedSwipeItemId = item.id
    }

    private func fireHapticOnPhaseChange() {
        let phase: Int
        let pct = trailingFraction
        if pct >= 0.9 { phase = 3 }
        else if pct >= 0.75 { phase = 2 }
        else if pct >= 0.25 { phase = 1 }
        else { phase = 0 }
        if phase != lastHapticPhase {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            lastHapticPhase = phase
        }
    }

    private func close() {
        translation = 0
        latched = .none
        // Only clear the global latch if WE were the holder — another
        // row may have claimed it during our animation window.
        if panelState.latchedSwipeItemId == item.id {
            panelState.latchedSwipeItemId = nil
        }
        lastHapticPhase = 0
    }

    private func animate(_ block: () -> Void) {
        if reduceMotion {
            block()
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                block()
            }
        }
    }

    // MARK: - Dispatch

    private func dispatch(_ action: RowAction) {
        animate { close() }
        let itemId = item.id
        let folder = item.folder
        let projectId = item.projectId
        let note = ItemPayload.decode(item.payload).note
        Task { @MainActor in
            do {
                switch action {
                case .moveToToday:    try await repository.move(id: itemId, to: .today)
                case .moveToTomorrow: try await repository.move(id: itemId, to: .tomorrow)
                case .moveToLimbo:    try await repository.move(id: itemId, to: .libmo)
                case .markDone:       try await repository.move(id: itemId, to: .done)
                case .delete:         try await repository.softDelete(id: itemId)
                case .restore:        try await repository.restore(id: itemId)
                case .purge:          try await repository.purgeItem(id: itemId)
                case .edit:
                    panelState.beginEdit(itemId: itemId, note: note, projectId: projectId)
                    _ = folder
                case .assignDate:
                    assignDateSheet = true
                case .assignProject:
                    assignProjectSheet = true
                }
            } catch {
                print("RowSwipeContainer dispatch failed: \(error)")
            }
        }
    }
}

// MARK: - Constants

private enum RowSwipeConst {
    /// Per-action visual width in the trailing strip. Sized so a full
    /// phase 2 reveal (up to 7 buttons on Today/Tomorrow/Limbo) fits
    /// inside a standard iPhone portrait width.
    static let actionWidth: CGFloat = 48
}

// MARK: - Sheets

private struct DateAssignSheet: View {
    @Environment(Repository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    let item: Item
    @State private var draft: Date = .now

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Due date",
                    selection: $draft,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                Spacer(minLength: 0)
            }
            .navigationTitle("Due Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if item.dueDate != nil {
                        Button("Clear", role: .destructive) {
                            Task {
                                try? await repository.setDueDate(id: item.id, to: nil)
                                dismiss()
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Set") {
                        Task {
                            try? await repository.setDueDate(id: item.id, to: draft)
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                draft = item.dueDate ?? Calendar.autoupdatingCurrent.startOfDay(for: .now)
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ProjectAssignSheet: View {
    @Environment(Repository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    let item: Item

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(repository.projects) { project in
                        Button {
                            Task {
                                try? await repository.setProject(itemId: item.id, to: project.id)
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(project.color)
                                    .frame(width: 14, height: 14)
                                Text(project.name)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                                if item.projectId == project.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            try? await repository.setProject(itemId: item.id, to: nil)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .strokeBorder(.secondary, lineWidth: 1)
                                .frame(width: 14, height: 14)
                            Text("No Project")
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            if item.projectId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
