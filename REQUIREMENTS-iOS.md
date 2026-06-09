# ToDragDo iOS — Requirements

iOS port of ToDragDo. Shares the Swift package (`ToDragDoCore`) and
the CloudKit sync stack with the existing macOS app; the UI is rebuilt
for touch.

## Platforms

- **iOS 17+ / iPadOS 17+** (matches Core).
- One app, adaptive layout driven by `horizontalSizeClass`.
  - **Compact** (iPhone portrait, iPad Slide Over): bottom tab bar,
    full-width single-column list.
  - **Regular** (iPad landscape / full, large iPhone landscape): same
    tab bar; the list is constrained to a comfortable reading width
    with empty space on either side. No split-view sidebar — the tab
    bar names the folder.

## Navigation: bottom tab bar

Five tabs, in order:

| # | Tab      | Icon                    | Drives                                  |
|---|----------|-------------------------|-----------------------------------------|
| 1 | Today    | `sun.max`               | `selectedFolder = .today`               |
| 2 | Tomorrow | `arrow.right`           | `.tomorrow`                             |
| 3 | Limbo    | `tray`                  | `.libmo` (badge blinks red when stale)  |
| 4 | Done     | `checkmark.circle`      | `.done` (summary pills on top)          |
| 5 | More     | `ellipsis.circle`       | Projects / Sync / Appearance / General / Trash / Data location |

- Tab badges show folder counts.
- Limbo badge animates red while any item crosses the user's idle
  threshold (`LimboStaleness.anyStale`).
- The macOS inline `FolderTabBar`, status-bar menu, and gear-shape
  overflow menu are all replaced by this tab bar.

## Per-folder tab structure

```
NavigationStack
  ├─ navigationTitle(folder.title)
  ├─ toolbar trailing: ProjectBadge(.square, .multi)   // filter
  ├─ InputBar (sticky top)
  └─ ItemListView                                       // no pagination
```

## Items

Functional parity with macOS. Same model (`Item`), same payload
(`ItemPayload` = note + attachments), same fields (`projectId`,
`dueDate`, `completedAt`, `limboEnteredAt`, `deletedAt`, `orderKey`,
`lastEditedBy`).

- New items prepend to the selected folder.
- Tap row → expand in place (multi-line, selectable text, clickable
  attachment previews).
- Tap row body again → collapse.
- Expanded row floating action panel: hover actions + date assign +
  edit + close (same composition as macOS, anchored above the row).
- Per-item project assignment via the `ProjectBadge` chip / picker.
- Link detection on note text → tappable blue links.

## List

- Plain `ScrollView { LazyVStack }`. `List` is avoided so the custom
  swipe gesture (see below) isn't shadowed by `swipeActions`.
- **No pagination**. The list scrolls naturally.
- Empty-state copy: `Nothing here.` / `Trash is empty.` (verbatim from
  macOS).

## Row actions: two-phased swipe

Standard `.swipeActions` doesn't fit — we want a continuous reveal.

- **Trailing swipe (leftward):**
  - **Phase 1** (0 … −50%): row slides left exposing the **primary
    action set** for that folder.
  - **Phase 2** (−50% … −90%): continuing reveals the **extended
    action set** (primary + secondary).
  - Release in phase 1 / phase 2 → latch open at that phase (tap row
    body or scroll dismisses).
  - Release past −90% → fires the folder's **default destructive**
    action (Today / Tomorrow / Limbo → Delete; Done → Delete; Trash →
    Purge).
- Haptic feedback on every phase boundary.
- Opening another row's swipe collapses the previously latched one
  (`PanelState.latchedSwipeItemId`).

Action sets per folder:

| Folder   | Phase 1                  | Phase 2 adds                                  |
|----------|--------------------------|-----------------------------------------------|
| Today    | Tomorrow, Delete, Done   | Limbo, Edit, Assign date, Project             |
| Tomorrow | Delete, Done             | Today, Limbo, Edit, Assign date, Project      |
| Limbo    | Delete, Done             | Today, Tomorrow, Edit, Assign date, Project   |
| Done     | Delete                   | Today, Tomorrow, Limbo, Edit, Project         |
| Trash    | Today, Done, Purge       | (no phase 2 — short set)                      |

All actions dispatch through `Repository` (same code path as macOS
`HoverActions`).

## Drag and drop

**Deferred to post-v1.** All capture flows in v1 work without
drag-and-drop:

- Type a note in the input bar.
- Paste from the system clipboard via the input bar's keyboard
  accessory paste button.
- Share Extension (see §Capture flows).
- Shortcuts / AppIntent (`AppendToTodayIntent`).

The drop targets on input bar + each row are not built for v1. The
underlying `Attachment` model + storage already support every kind
the macOS app does, so adding drop later is purely a UI layer
addition.

## Folders + lifecycle

- Four folders: **Today**, **Tomorrow**, **Limbo**, **Done**.
- Day rollover (Core's `Repository.rolloverDay`) runs on:
  - app foreground (`UIScene.willEnterForegroundNotification`),
  - midnight timer while the app is in memory.
- Due-date promotion (`promoteScheduledItems`): Limbo items whose
  `dueDate ≤ today` → Today; `dueDate == tomorrow` → Tomorrow.

## Trash

- 30-day retention (`Repository.trashRetention`, Core).
- Accessed under **More → Trash**.
- Renders the same row view in `trashMode: true`. Swipe actions:
  restore to Today / Tomorrow / Done; purge.

## Projects

- Two seeded defaults (Work, Personal) with stable UUIDs (Core).
- Add / rename / recolor / delete from **More → Projects**.
- Per-item project chip + picker.
- Multi-select **project filter** in each folder tab's navigation bar
  (trailing). Picker presented as `.sheet` on compact, `.popover` on
  regular.

## Limbo blink

- `SettingsSnapshot.limboBlinkDays` synced cross-device via the
  existing change-record pipe.
- Row pulse + Limbo tab badge red when an item's idle exceeds the
  threshold (`LimboStaleness.isStale`).
- Opening a Limbo row resets `limboEnteredAt`
  (`Repository.noteOpened`).

## Done summary

- Day / Week summary opens from the Done tab's `DoneSummaryRow`,
  presented as a sheet on iPhone, popover on iPad.
- Reuses `SummaryView` + `SummaryWindowState` from macOS.

## Sync

- iCloud via `CKSyncEngine` (`CloudKitRemoteAdapter`) — shared across
  macOS and iOS.
- `CKDatabaseSubscription` + APNS silent push so iOS picks up remote
  writes promptly without polling.
- `BGAppRefreshTask` for periodic background syncs.
- Sync settings pane (under More): per-provider toggle, last sync
  (relative), pending push count, last error with Copy, Sync Now,
  Re-sync All… (confirmation dialog). Parity with macOS.

## Appearance

- Light / Dark / Auto.
- Drives `.preferredColorScheme(_:)` only — no `NSApp.appearance`
  shim.

## Settings (under More)

- **General:** hide-during-capture toggle, Limbo blink stepper, data
  location row (Copy path, share to Files).
- **Projects.**
- **Sync.**
- **Appearance.**
- **Trash.**

## Privacy: hide during screen capture

- Replaces macOS `NSWindow.sharingType = .none`.
- `UIScreen.capturedDidChangeNotification` + `UIScreen.isCaptured`
  drive a top-level boolean.
- When capturing: hide Area 2 (the list), show a small "list hidden —
  sharing" caption. Area 1 (input bar) stays visible.
- Lock-Screen widgets use `.privacySensitive()` so contents redact on
  the lock screen.

## Capture flows (replace macOS drag-in / status-bar add)

- **Share Extension** — accept text / URL / image / file from any
  iOS app's share sheet. Picks folder (Today / Tomorrow / Limbo),
  optional project, optional note. Writes through `Repository.add`.
- **Shortcuts / AppIntents** — `AppendToTodayIntent(text:)`,
  `MarkDoneIntent(itemId:)`. Drives Siri, Home-Screen quick actions,
  widget tap targets.
- **Widgets:**
  - Small: Today count + Limbo-stale dot.
  - Medium: first 3 Today items.
  - Large: first 6 Today items.
  - Lock-Screen rectangular: Today count + "Add" deeplink.
  - Lock-Screen circular: Today count.
- **Quick-action Home-Screen shortcuts:** "Add to Today", "Add to
  Tomorrow".

## Plugins / extensibility

The macOS spec calls for content-type providers but never landed
them. iOS is the moment to ship them — both targets benefit.

- New shared target `ToDragDoContentTypes` holds the
  `ContentTypeProvider` protocol, `ContentTypeRegistry`
  (`@MainActor @Observable`), and four built-in providers:
  - `TextProvider`
  - `URLProvider` (with `LPMetadataProvider` link preview)
  - `FileURLProvider`
  - `ImageProvider`
- Adding a new type = one new file + one `registry.register(...)`
  call at launch. Identical on macOS and iOS.
- Per-provider auth lives in `AuthStore` (Keychain) — kept separate
  from sync auth.

For v1 ship the four built-ins above. Third-party-style providers
(Jira, Zillow, GitHub PR, Linear, …) land afterwards without
touching the host UI.

## What's removed from macOS

- `PanelController` / `FloatingPanel` / `NSPanel`.
- `MenuBarStatusItem` (no menu bar; More tab + widgets replace it).
- `FolderTabBar` + `CollapseChevron` + `CollapsedCaption` (tab bar
  replaces).
- Pagination: `ItemList.PaginationBar`, `PanelState.currentPage`,
  missing-rows spacer, intermediate-page `EndDropZone` placeholder.
- `WindowDragArea`, `WidthResizeHandle`, `AppSettings.panelWidth`.
- Gear-shape overflow menu inside the list footer.
- Hover-revealed row action overlay (replaced by swipe).

## What stays unchanged

- `ItemRow` collapsed + expanded body, attachment preview, project
  dot corner, due-date stamp, link-detection on the note text.
- `InputBar` at the top of each folder tab.
- `DateAssignButton`, project picker popover, attachment chip strip,
  `SummaryView` + state.
- Limbo blink (row pulse + tab badge).
- Day rollover, due-date promotion, soft-delete, trash retention.
- iCloud sync, multi-provider coordinator, re-sync-all flow.

## Open questions (resolve before shipping)

1. **Background sync cadence** — `BGAppRefreshTask` minimum is
   ~15 min; rely on it + silent push, or push only?
2. **Widget interactivity** — wire "Mark Done" from the widget
   itself via `AppIntent`?
3. **Share Extension depth** — minimal (one-tap save to Today) vs
   full picker (folder + project + due date)?
4. **iPad floating mode** — match macOS spirit with a Stage-Manager
   small overlay window, or accept "iPad is a normal app window"?
