# ToDragDo iOS — Implementation Plan

Plan to ship the iOS app described in `REQUIREMENTS-iOS.md`. Each
phase leaves the repo in a shippable state; later phases unlock
surfaces but earlier phases work without them.

## Phase 0 · Core reorg (prep)

Goal: cut every iOS-relevant module loose from the macOS app target
so iOS can `import` them.

1. New SwiftPM targets in `Core/ToDragDoCore/Package.swift`:
   - `ToDragDoSync` — depends on `ToDragDoCore`. CloudKit only, no
     AppKit / UIKit.
   - `ToDragDoContentTypes` — depends on `ToDragDoCore`. SwiftUI
     allowed, no AppKit / UIKit.
2. Move files (no logic changes, just imports):
   - macOS `Services/CloudKitRemoteAdapter.swift`,
     `CloudKitAccountWatcher.swift`, `CloudKitSchema.swift`,
     `CloudKitStateStore.swift`, `CloudKitEnvironmentProbe.swift`,
     `CloudKitErrorDescribe.swift`, `SyncTicker.swift`
     → `Sources/ToDragDoSync/`.
   - Strip the one `AppKit` import from `SyncTicker`
     (`NSWorkspace.didWakeNotification`): move that subscription into
     a small platform shim that lives in the macOS app target and
     forwards into the ticker.
3. New types in `ToDragDoContentTypes`:
   - `DropPayload` — portable wrapper around bytes + advertised
     UTType strings. No `NSItemProvider` leakage.
   - `ContentTypeProvider` protocol + `ContentTypeRegistry`
     (`@MainActor @Observable`).
   - Built-in providers: `TextProvider`, `URLProvider`,
     `FileURLProvider`, `ImageProvider`. Each owns preview + full
     view; both apps consume `registry.resolve(_:).full(for: item)`.
4. macOS app target swaps its hard-coded `AttachmentPreview` /
   `TypeBadge` switches for `registry.resolve(_:)`. Parity preserved.
5. `xcodebuild` smoke: macOS target still builds + runs.

Exit criterion: `import ToDragDoCore` + `import ToDragDoSync` +
`import ToDragDoContentTypes` compile on both `os(macOS)` and
`os(iOS)`. macOS app behaves identically.

## Phase 1 · iOS app skeleton

1. New Xcode target `ToDragDo-iOS` (App, SwiftUI, iOS 17 deployment).
2. Entitlements:
   - `com.apple.developer.icloud-container-identifiers =
     ["iCloud.com.turtle.todragdo.sync.container"]` (reuses existing
     container).
   - `com.apple.developer.icloud-services = ["CloudKit"]`.
   - `com.apple.security.application-groups =
     ["group.com.turtle.todragdo"]` (used by share ext + widgets).
   - `aps-environment = development` (sync push later).
3. Shared scaffolding — lift from macOS, drop AppKit pieces:
   - `AppSettings`: swap `UserDefaults.standard` →
     `UserDefaults(suiteName: "group.com.turtle.todragdo")`. Remove
     `panelWidth` + range. Keep `hideFromScreenSharing` (rewire in
     Phase 6).
   - `DataLocation`: iOS path is the App Group container URL
     (`containerURL(forSecurityApplicationGroupIdentifier:)`).
   - `DayRollover`: swap `NSWorkspace.didWakeNotification` for
     `UIScene.willEnterForegroundNotification`. Keep midnight timer +
     `runIfNeeded`.
   - `StorageHealth`: unchanged.
4. `ToDragDoApp` (iOS): build the same object graph
   (storage → repository → coordinator → adapter → account watcher →
   sync ticker → day rollover) in `init`, inject through
   `.environment(...)`, single `WindowGroup { RootView() }`.
5. `RootView`: bottom `TabView` with 5 tabs, all stubbed.

Exit criterion: app launches; all five tabs render placeholders;
repository reload works against the iCloud-synced SwiftData store;
Sync tab shows "Last sync: …" populated by the coordinator.

## Phase 2 · Folder tab views

Each of Today / Tomorrow / Limbo / Done is one `FolderTabView(folder:)`
— only the bound folder differs.

Port from macOS (mostly verbatim, AppKit calls swapped):

- `InputBar.swift` — `TextField`, project chip, attachment chip flow
  all work on iOS as-is.
- `AttachmentChip.swift` — pure SwiftUI.
- `ProjectBadge.swift` + popover — switch popover-vs-sheet by size
  class.
- `DateAssignButton.swift` — `DatePicker(.graphical)` is iOS-native;
  present in `.sheet(detents: [.medium])` on compact, `.popover` on
  regular.
- `DoneSummaryRow.swift`, `SummaryView.swift`,
  `SummaryWindowState.swift` — present `SummaryView` as a sheet from
  Done's `DoneSummaryRow`. Drop the AppKit `SummaryWindow` wrapper.
- `AttachmentIconStrip.swift`, `FlowLayout.swift`, `TypeBadge.swift`
  — port as-is.
- `AttachmentPreview.swift` — `NSImage` → `UIImage`,
  `NSWorkspace.shared.open(_:)` → `UIApplication.shared.open(_:)`.
  `LPMetadataProvider` works identically on iOS.

New `ItemListView` (replaces `ItemList`):

- `ScrollView { LazyVStack(spacing: 0) }`. No `List`.
- Filter by `panelState.filterProjectIds` (same logic).
- No pagination, no missing-rows spacer, no `EndDropZone`.
- Empty-state copy preserved.

Drop the drag/drop modifiers on `InputBar` and `ItemRow` for v1 —
neither registers as a drop target. The attachment-loading code path
(`Attachment.from(provider:)`) stays in the shared content-types
target; it's reused by the Share Extension in Phase 7.

Exit criterion: every folder tab shows real items, input bar adds
them, project chip + filter + due-date all work. Rows are tap-to-open
only — no row actions yet.

## Phase 3 · Two-phased swipe

New file: `Views/Row/RowSwipeContainer.swift` in the iOS target.

```
RowSwipeContainer(item:) {
    ItemRow(item: item)
}
.gesture(DragGesture(minimumDistance: 12) ... )
```

Mechanics:

- `@State translation: CGFloat`, `@State latched: LatchState`
  (`.none | .phase1 | .phase2`).
- Render the row offset by `translation` over two `HStack`s of
  buttons (`primaryActions`, `secondaryActions`) anchored to the
  trailing edge.
- `phase1Width = primary.count * 56pt`, `phase2Width = secondary.count
  * 56pt`. Reveal caps at `phase1Width + phase2Width`.
- DragGesture `.onChanged` clamps translation, fires
  `UIImpactFeedbackGenerator` on phase-boundary crossings, sets
  latch on release using:
  - Released ≤ 25%        → close.
  - 25% … 75%             → latch phase 1.
  - 75% … 90%             → latch phase 2.
  - ≥ 90%                 → fire default destructive + slide off.
- `latchedSwipeItemId` on `PanelState` so opening another row's
  swipe collapses the prior one.
- Tap on row body when latched → reset latch (don't open the row).
- Reduce Motion → suppress the slide animation, but still respond to
  the gesture; phase changes snap.

Extend `RowAction.actions(for:phase:inTrash:)` to return primary +
secondary sets per the table in REQUIREMENTS-iOS.md §Row actions.

Exit criterion: every macOS `RowAction` reachable via swipe; haptics
fire on phase boundaries; latched state survives scroll; destructive
arm fires cleanly.

## Phase 4 · Sync wiring on iOS

- `CloudKitAccountWatcher` + `SyncTicker` from `ToDragDoSync` —
  instantiate in `ToDragDoApp.init`, mirror macOS wiring.
- Foreground hook: `.onChange(of: scenePhase)` in `RootView` → call
  `coordinator.sync("icloud")` when entering `.active`.
- `BGAppRefreshTask`:
  - Register `com.turtle.todragdo.refresh` in `init`.
  - On fire → `coordinator.syncAll()` + reschedule.
- CloudKit silent push:
  - Create `CKDatabaseSubscription(subscriptionID: "todragdo-private")`
    once, gated on a `UserDefaults` flag.
  - `UIApplicationDelegateAdaptor` to hook
    `application(_:didReceiveRemoteNotification:)` →
    `coordinator.sync("icloud")`.
  - No user-visible notifications in v1 — silent only.
- `WidgetCenter.shared.reloadAllTimelines()` after each successful
  sync (no-op if widgets aren't installed; cheap if they are).

Exit criterion: change on macOS lands on iOS within seconds; change
on iOS lands on macOS; Sync settings shows last sync, pending count,
errors copy correctly.

## Phase 5 · More tab + settings panes

`MoreView` = `NavigationStack` with a `List` of `NavigationLink`s.
Destinations port from macOS Settings:

- **Projects** — port of `ProjectsSettingsView.swift`.
- **Appearance** — port of `AppearanceSettingsView.swift`.
- **Sync** — port of `SyncSettingsView.swift`. Replace
  `NSPasteboard` "Copy Error" → `UIPasteboard.general.string = ...`.
- **General** — hide-during-capture toggle, Limbo blink stepper, data
  location row (Copy path + ShareLink to the store URL).
- **Trash** — renders `ItemListView` in `trashMode: true` against
  `repository.trashItems`.

Hide-during-capture wiring:

- `RootView` observes `UIScreen.capturedDidChangeNotification` +
  `UIScreen.isCaptured`.
- When capturing → hide the list (`ItemListView`), keep the input
  bar, show "list hidden — sharing" caption above the input bar.
- Lock-Screen widget views call `.privacySensitive()`.

Exit criterion: all settings panes reachable, all writes survive a
relaunch, capture flag flips the list visibility live.

## Phase 6 · Share Extension

Target: `ToDragDo-iOS-Share` (Share Extension template, SwiftUI host).

- Shares App Group + iCloud entitlements with the main app.
- Compose a `Repository` from the same SwiftData store URL.
- UI: SwiftUI sheet with:
  - Segmented `[Today | Tomorrow | Limbo]` folder picker.
  - Optional project picker (`ProjectBadge` reused).
  - Optional note field.
  - Add button.
- On submit:
  - Convert each `NSExtensionContext` input attachment via
    `Attachment.from(provider:)` (the iOS variant lifted into
    `ToDragDoContentTypes` with `#if canImport(UIKit)`).
  - `repository.add(folder:typeIdentifier:payload:projectId:)`.
  - `coordinator.sync("icloud")` before extension dismisses so the
    change propagates without waiting for the main app to launch.

Exit criterion: share a Safari URL / Photos image / Files document →
item appears in the main app immediately, with correct folder and
project assignment.

## Phase 7 · Widgets + AppIntents

Target: `ToDragDo-iOS-Widgets` (WidgetKit extension).

- Reads from the App Group SwiftData store (read-only path).
- Widgets:
  - Small: Today count + Limbo-stale dot.
  - Medium: first 3 Today items (title + project dot).
  - Large: first 6 Today items.
  - Lock-Screen rectangular: Today count + "Add" deeplink.
  - Lock-Screen circular: Today count.
- AppIntents (iOS 17+):
  - `MarkDoneIntent(itemId: UUID)` — fire from widget tap.
  - `AppendToTodayIntent(text: String)` — Shortcuts entry point.
- Timeline refresh: every 30 min + on `WidgetCenter.shared
  .reloadAllTimelines()` from the main app after each Repository
  write.
- Quick-action Home-Screen shortcuts: "Add to Today", "Add to
  Tomorrow" via `UIApplicationShortcutItem`.

Exit criterion: widgets render real data on home + lock screen; tap
deep-links into the right folder tab; Shortcuts can append items.

## Phase 8 · Polish

- Haptics: phase-1↔phase-2 boundary, destructive arm, mark-done full
  swipe.
- Dynamic Type: audit hard-coded `.system(size:)` in ported views;
  convert leaves to `.font(.body)` / `.font(.caption)` where the
  design tolerates it.
- VoiceOver:
  - Row reads "Today, 3 of 12, Buy milk, Personal, due tomorrow".
  - Swipe actions exposed via `.accessibilityActions`.
- iPad hardware keyboard:
  - ⌘N → focus input bar.
  - ⌘1…⌘5 → tab switch.
  - ⌘F → focus project filter.
  - Esc → close expanded row.
- Reduce Motion → skip Limbo pulse opacity animation; static red
  tint instead.

## After v1 (out of scope for first ship)

- **Drop / drag**:
  - `.dropDestination` on input bar + each row (mirrors macOS).
  - Row drag (`.draggable(ItemDragURL.url(for: item.id))`) on iPad —
    gated on `horizontalSizeClass == .regular`.
  - iPhone reorder via long-press context menu → "Move to position…"
    (drag inside a `ScrollView` fights the swipe gesture on phone).
- **iPad floating mode** — small Stage-Manager overlay window.
- **Third-party content-type providers** — Jira, Zillow, GitHub PR,
  Linear, etc. The plugin spine ships in Phase 0; providers land one
  PR at a time afterwards.

## Suggested PR sequence

1. Phase 0 — Core reorg (separate PR, no iOS).
2. Phase 1 — iOS skeleton + folder tabs reading items.
3. Phase 2 — full folder tab views (input bar, expanded row,
   summaries).
4. Phase 3 — two-phased swipe.
5. Phase 4 — sync + push (gate behind a build flag until verified
   end-to-end).
6. Phase 5 — More tab + settings panes.
7. Phase 6 — Share Extension.
8. Phase 7 — Widgets + AppIntents.
9. Phase 8 — polish.

Each PR is independently shippable to TestFlight — every step leaves
the app in a working state, just with fewer surfaces lit up than the
next one.
