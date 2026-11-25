# ToDragDo — Core Architecture

## Stack

- **Language:** Swift 6, strict concurrency on
- **UI (macOS):** SwiftUI + AppKit interop where needed (`NSPanel`, `NSStatusItem`)
- **App pattern:** **MV** (Model-View with `@Observable`). No view-model layer.
- **Core:** plain Codable structs, zero Apple frameworks in the public API
- **Persistence:** `ItemStorage` protocol; concrete impl chosen by
  `Platform.current` (today: `SwiftDataStorage` for macOS/iOS).
  Sync is built around a `ChangeRecord` outbox so any future backend —
  CloudKit, Supabase, custom — plugs in without schema or call-site changes.
- **Min OS:** macOS 14, iOS 17 (so SwiftData + `@Observable` are available)
- **Tests:** Swift Testing, run against an in-memory `ItemStorage` fake

## Why Swift / SwiftUI

Every "twist" feature is deeply macOS-specific: floating window level,
screen-share detection, status bar item, native drag types. Going native
is the fastest path to a great macOS app. The shared core reaches iOS
for free; Windows would need a second UI stack later (acceptable
tradeoff for "macOS first").

## App pattern: MV with `@Observable`

The app uses the **Model-View** pattern. Views observe `@Observable`
models (Repository, AppState, content-type-specific stores) **directly** —
no view-model layer. Justification:

- App is small: one floating panel + one status bar popover.
- State flow is straightforward: drag/type → Repository → views.
- `@Observable` (iOS 17 / macOS 14+) gives fine-grained tracking out of
  the box; intermediate view models would just forward properties.
- Tests target `@Observable` types directly without instantiating views.

Escalate to MVVM **only** if a specific surface grows logic that's awkward
to test through the model (e.g. complex provider full-views with their
own derived state). Don't pre-pay the cost.

## Top-level layout

```
ToDragDo/                                 (working copy root)
├── README.md, ARCHITECTURE.md, ReleaseInstructions.md, REQUIREMENTS*.md
├── scripts/                              build-prod.sh, build-dev-icloud.sh, test-build.sh
├── docs/screenshots/
└── ToDragDo/                             (Xcode project root)
    ├── ToDragDo.xcodeproj
    ├── ToDragDo/                         macOS app: ToDragDoApp, AppDelegate,
    │   ├── Window/                       FloatingPanel / PanelController, Settings & Summary windows
    │   ├── MenuBar/                      NSStatusItem
    │   ├── State/                        PanelState (panel-only UI state)
    │   └── Views/{Panel,Settings,Summary}  hover-driven panel UI
    ├── ToDragDo-iOS/                     iOS app: RootView, tab bar, swipe rows,
    │   └── Services/                     BackgroundRefresh, ScreenCaptureMonitor
    ├── ToDragDoWidgets/                  WidgetKit extension
    └── Core/ToDragDoCore/                Swift package
        └── Sources/
            ├── ToDragDoCore/             models, Repository (+Items, +Projects,
            │                             +Scheduling, +Sync, +Backup), SwiftData
            │                             storage, SyncCoordinator, DemoData
            ├── ToDragDoSync/             CloudKit adapter, environments, migration
            ├── ToDragDoContentTypes/     text / URL / file / image providers
            ├── ToDragDoIntents/          App Intents, App Group, deep links
            └── ToDragDoUI/               SwiftUI shared by both apps: AppSettings,
                                          DayRollover, DataLocation, Theme, settings
                                          panes, small row/badge views
```

`ToDragDoUI` holds everything the two apps render or store the same way;
platform differences inside it are `#if os(...)` branches (row metrics in
`Theme` / `PlatformMetrics`, App Group vs standard defaults in
`SharedDefaults`, the settings chrome in `settingsPaneStyle`). What stays
in the app targets is genuinely different UX: the macOS hover panel vs the
iOS tab bar and swipe rows (`PanelState`, `RowAction`, `ItemRow`,
`InputBar`, `ProjectBadge`, Summary views).

**Rule:** the `ToDragDoCore` module never imports `AppKit` or `UIKit` (only `ToDragDoUI` and the app targets do). The public API
imports no Apple frameworks at all (`SwiftData` is referenced *internally*
by `SwiftDataStorage`, gated behind `#if canImport(SwiftData)`). Anything
platform-specific lives behind a protocol in Core, with a concrete impl
selected by `StorageFactory` based on `Platform.current`.

## Data model

Public types in Core are **plain Codable structs**. No Apple frameworks
leak into the public API; the same `Item` value can be sent over the
wire, held by tests on any platform, or mapped onto any storage backend.

```swift
// Core/Models/Item.swift
public struct Item: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID                  // client-generated, sync-safe
    public var folder: Folder            // .today .tomorrow .libmo .done
    public var orderKey: Double          // fractional ordering, cheap reorders
    public var typeIdentifier: String    // matches ContentTypeProvider.id
    public var payload: Data             // provider-specific encoded blob
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?          // soft delete (sync-safe)
    public var lastEditedBy: String      // device id
}

public enum Folder: String, Codable, Sendable, CaseIterable {
    case today, tomorrow, libmo, done
}
```

`ChangeRecord` (the outbox row) follows the same pattern: a plain struct
with `id`, `entityType`, `entityId`, `op`, `snapshot` (JSON-encoded
`Item`), `ts`, `deviceId`, `syncedAt`.

The Apple-only `SwiftDataStorage` defines two **internal** `@Model`
classes — `PersistedItem` and `PersistedChange` — and maps them to/from
the public structs at the storage boundary. Other backends do the same
with their own row types.

Why these fields:

- **UUID PK** — no auto-increment ints; safe to merge across devices.
- **`updatedAt` + `deletedAt`** — required for any sync conflict
  resolution.
- **`lastEditedBy`** — useful for conflict UX later.
- **`orderKey: Double`** — drop a new item between two by averaging
  neighbors; rebalance lazily.

## Persistence: protocol + Platform-dispatched implementation

Storage is a protocol, not a concrete class. `Repository` only ever sees
`any ItemStorage` and the public `Item` / `ChangeRecord` structs.

```swift
public protocol ItemStorage: Sendable {
    func items(in folder: Folder, includeDeleted: Bool) async throws -> [Item]
    func item(id: UUID) async throws -> Item?

    // Writes are atomic with their accompanying ChangeRecord append.
    func upsert(_ item: Item, change: ChangeRecord) async throws
    func softDelete(id: UUID, at: Date, change: ChangeRecord) async throws
    func hardDelete(folder: Folder, changes: [ChangeRecord]) async throws

    // Outbox
    func pendingChanges(limit: Int) async throws -> [ChangeRecord]
    func markSynced(_ ids: [UUID], at: Date) async throws
}
```

Backends are selected by `StorageFactory` based on `Platform.current`:

```swift
public enum Platform: String, Sendable {
    case macOS, iOS, windows, linux, unknown
    public static var current: Platform { /* compile-time #if dispatch */ }
}

public enum StorageFactory {
    public static func makeItemStorage(
        platform: Platform = .current,
        inMemory: Bool = false
    ) throws -> any ItemStorage {
        switch platform {
        case .macOS, .iOS:  return try SwiftDataStorage(inMemory: inMemory)
        case .windows, .linux, .unknown: throw StorageError.unsupportedPlatform(platform)
        }
    }
}
```

Adding a Windows backend = one new `ItemStorage` conformer + one new
`switch` arm. No call site changes.

The `upsert(_:change:)` shape enforces the "every write produces one
outbox row" invariant *at the storage layer* — backends commit the
mutation and the `ChangeRecord` insert in a single transaction.
Repository can't accidentally skip the outbox.

## Extensible content types

The crux of the design. Every drag/paste/type goes through a registry
that picks the first provider whose `canHandle` matches.

```swift
public protocol ContentTypeProvider {
    static var id: String { get }                 // stable, persisted
    static func canHandle(_ payload: DropPayload) -> Bool
    func makeContent(from payload: DropPayload) async throws -> ItemContent
    func preview(for content: ItemContent) -> AnyView   // Area 2 row
    func full(for content: ItemContent) -> AnyView      // unfolded view
}
```

> **`AnyView` is intentional.** Heterogeneous providers must live in a
> single registry collection, which forbids `some View` / associated
> types here. The performance cost is irrelevant for a list of todo
> rows, and providers are free to use `some View` internally.
>
> SwiftUI is imported in Core (still no AppKit/UIKit; still portable to
> iOS). Split into `Core` + `CoreUI` only if Core grows non-UI consumers
> that shouldn't pay the SwiftUI import cost.

`ContentTypeRegistry` holds an ordered list. Adding a new type =
**one new file + one `register()` call** at app launch. Each provider
owns its own preview/full view, its own auth state (via the `AuthStore`
protocol), and its own payload encoding.

## Write funnel & sync

All mutations go through `Repository` (`@MainActor @Observable`). The
storage layer guarantees atomicity: the model row and its `ChangeRecord`
commit together or not at all.

### Multi-provider sync

v1 supports **multiple sync providers running concurrently**. iCloud
ships first; Supabase and custom backends slot in later via the same
protocol. Each provider has its own identity, its own pull cursor, and
its own per-change push state.

```swift
public protocol RemoteAdapter: Sendable {
    var providerId: String { get }      // stable, e.g. "icloud"
    var displayName: String { get }     // user-facing, e.g. "iCloud"

    func push(_ changes: [ChangeRecord]) async throws -> PushOutcome
    func pull(since cursor: SyncCursor) async throws
        -> (changes: [ChangeRecord], next: SyncCursor)
}

public struct PushOutcome: Sendable {
    public let succeeded: [UUID]
    public let failed: [Failure]
    public struct Failure: Sendable { let id: UUID; let error: String }
}
```

`push` returns a per-record outcome rather than throwing on partial
failure. The coordinator marks `succeeded` IDs pushed and calls
`recordPushFailure` for the rest — so a single bad record (schema
mismatch, conflict) doesn't poison the whole batch and, crucially,
records that CloudKit rejected don't get silently marked as pushed.
Throwing is reserved for batch-level errors (network, auth) where no
per-record breakdown exists; the coordinator then treats every ID in
the batch as failed.

### Per-change × per-provider push state

Sync state is normalized into its own type, **not** carried as a map on
the ChangeRecord itself:

```swift
public struct ChangeSyncStatus: Sendable, Codable, Hashable {
    public let changeId: UUID
    public let providerId: String
    public var pushedAt: Date?         // nil = pending
    public var lastAttemptAt: Date?
    public var lastError: String?
    public var attemptCount: Int
}
```

Identity is the composite `(changeId, providerId)`. The SwiftData
backend mirrors this with `PersistedChangeSyncStatus`, related to
`PersistedChange` via a cascade-delete to-many relationship. Predicates
on `change.syncStatuses.contains { … }` express "pending for provider X"
natively — no in-memory filtering.

Storage protocol surface:

```swift
extension ItemStorage {
    func pendingChanges(for providerId: String, limit: Int) async throws -> [ChangeRecord]
    func pendingPushCount(for providerId: String) async throws -> Int
    func markPushed(_ ids: [UUID], to providerId: String, at: Date) async throws
    func recordPushFailure(_ ids: [UUID], to providerId: String,
                           error: String, at: Date) async throws
    func syncStatus(forChange changeId: UUID,
                    providerId: String) async throws -> ChangeSyncStatus?
}
```

Each provider asks for the changes it hasn't pushed; on success it
marks them pushed-to-self. Failures bump `attemptCount` and store
`lastError` without flipping `pushedAt`, so the change stays in the
pending list. Other providers' state is untouched.

### `SyncCoordinator`

A single `@Observable SyncCoordinator` owns all enabled adapters and
publishes a `[SyncStatus]` array — one entry per provider:

```swift
public struct SyncStatus: Sendable, Identifiable {
    public var id: String { providerId }
    public let providerId: String
    public let displayName: String
    public var enabled: Bool
    public var lastAttempt: Date?
    public var lastSuccess: Date?
    public var lastError: String?
    public var pendingPushCount: Int
}

@MainActor @Observable
public final class SyncCoordinator {
    public private(set) var statuses: [SyncStatus]
    public func register(_ adapter: any RemoteAdapter)
    public func setEnabled(_ enabled: Bool, for providerId: String)
    public func syncAll() async
    public func sync(_ providerId: String) async
    /// Sees each successful pull before it is applied locally.
    public var pullObserver: (@MainActor (String, [ChangeRecord]) async -> Void)?
}
```

`pullObserver` is awaited inside the cycle, between `pull` and
`applyRemote`, so the observer can still read the pre-pull local state,
and any outbox rows it appends go out in the same cycle's push. Today
its only user is the Development → Production migration (below).

Settings binds directly to `SyncCoordinator.statuses` to render the
per-provider status list. Toggling a provider on/off flips its
`enabled` flag and (if turning off) leaves its outbox state intact so
re-enabling resumes from where it stopped.

### iCloud adapter

`CloudKitRemoteAdapter` (lives in the `ToDragDoSync` package target,
shared by the macOS app, the iOS app and the widget extension):
- Uses **`CKSyncEngine`** (the modern API) against the user's private
  CloudKit database.
- Encodes `ChangeRecord` to a `CKRecord` keyed by `id`; the JSON
  `snapshot` payload is a `CKAsset` for any non-trivial size.
- `CKSyncEngine`'s state serialization (server change tokens, zone
  state) is persisted by `CloudKitStateStore` in `UserDefaults`, keyed
  **per CloudKit environment**: `todragdo.cloudkit.state.icloud.<Environment>`.
  `SyncCursor.token` only carries a fingerprint of it.
- Tracks per-record success/failure during `sendChanges()` via the
  `.sentRecordZoneChanges` delegate event: `savedRecords` go into
  `cycleSucceeded`, `failedRecordSaves` go into `cycleFailed`. The
  `push` method composes those into a `PushOutcome` for the
  coordinator. CloudKit conflicts (`CKError.serverRecordChanged`) are
  treated as success because our zone is append-only — the record
  exists on the server already with our content.
- `CKAsset` files live in the app's Application Support directory
  (`CloudKitAssets/<change-id>.json`), **not** `/tmp`. CloudKit
  uploads assets asynchronously after the record is staged; the OS
  sweeps `/tmp` on its own schedule, which used to cause every push
  retry to fail permanently. Files are deleted after CloudKit
  confirms the save (or on conflict resolution).
- First-launch sequencing: `SyncTicker.start()` awaits
  `CloudKitAccountWatcher.refresh()` before its first `syncAll()`,
  so the initial sync doesn't no-op on the `enabled=false` default
  while the async account check is still in flight.

Identifiers live in one place: `CloudKitConfig.containerIdentifier`
and `CloudKitConfig.providerId` (`"icloud"`) in `ToDragDoSync`.
`AppGroup.iCloudContainerIdentifier` forwards to it. Loggers use
`Logger.todragdo(category:)` from `ToDragDoCore`.

### CloudKit environments

Development and Production are separate CloudKit databases; a binary
talks to exactly one, chosen by the signed
`com.apple.developer.icloud-container-environment` entitlement.

| Target / config | Entitlements | Environment |
|---|---|---|
| macOS Debug | `ToDragDo/ToDragDo.entitlements` | Development |
| macOS Release | `ToDragDo/ToDragDoRelease.entitlements` | Production |
| iOS Debug | `ToDragDo-iOS/ToDragDo-iOS.entitlements` | Development |
| iOS Release | `ToDragDo-iOS/ToDragDo-iOS-Release.entitlements` | Production |
| Widget Debug | `ToDragDoWidgets/ToDragDoWidgets.entitlements` | Development |
| Widget Release | `ToDragDoWidgets/ToDragDoWidgets-Release.entitlements` | Production |

`scripts/build-dev-icloud.sh` builds macOS Release with the
Development entitlements; `scripts/build-prod.sh` builds macOS Release
as configured and refuses to finish unless the signed app says
Production.

`CloudKitEnvironmentProbe.resolved` tells the code which environment it
runs in: on macOS it reads the signed entitlement
(`SecTaskCopyValueForEntitlement`); iOS has no public API for that, so
the iOS app and the widget carry `TDCloudKitEnvironment` in Info.plist,
filled from the per-configuration `TODRAGDO_CLOUDKIT_ENV` build
setting. Keep that setting equal to the entitlements file's value.

Caveat: the local SwiftData store and the outbox are **not** split by
environment. A Development and a Production build on the same device
share data and pending outbox rows, so edits made in a Development
build would later be pushed to Production too. Run Development builds
only on a separate machine, user account, or simulator.

### Development → Production migration

`ProductionMigration` (`ToDragDoSync`) runs once, on the first launch of
a Production build (flag `todragdo.migration.production.done`). It
hooks `SyncCoordinator.pullObserver`; on the first successful pull,
before the pulled records are applied, it:

1. writes a `RepositoryBackup` (all items incl. trashed, all projects)
   as JSON to `Backups/pre-production-<timestamp>.json` next to the
   store;
2. calls `Repository.resyncAllItems(excluding:)` with the entity ids the
   pull returned, so only records Production doesn't have yet are
   queued.

The first device finds Production empty and uploads everything; later
devices only add what they alone have. This matters because
`applyRemote` overwrites local rows without a newer-wins check, so a
blind full re-upload from a second device could clobber newer edits.
The result and backup path are stored under
`todragdo.migration.production.summary` and shown in Settings → Sync.
A failure leaves the flag unset and retries on the next pull.

Per-provider auth state for non-Apple backends lives in `AuthStore`
(Keychain-backed) — same pattern as content-provider auth.

### Conflict strategy

Last-write-wins per field, driven by `updatedAt`. Simple, correct
enough for a personal todo app on a small number of devices. Don't
reach for CRDTs.

## Day rollover

`DayRolloverService` is a pure function over `Repository`:

- On app launch, on wake, and on midnight tick:
  - If `lastRolloverDate < today`:
    1. Move all `today` items (not done) to end of `tomorrow`.
    2. Move all `tomorrow` items to `today` preserving order.
    3. Persist `lastRolloverDate = today`.

Trivial to unit-test; no UI dependency.

## Always-on-top window

`NSPanel` (not `NSWindow`) because panels can float above other apps'
fullscreen windows cleanly. Window has **no title bar / chrome**; the
user drags it by the body.

```swift
panel.styleMask = [.borderless, .nonactivatingPanel]
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
panel.isFloatingPanel = true
panel.isMovableByWindowBackground = true
panel.hidesOnDeactivate = false
panel.backgroundColor = .clear  // SwiftUI content paints the surface
```

Created in `AppDelegate.applicationDidFinishLaunching`, **not** via
SwiftUI's `WindowGroup` (which fights you on panel semantics). The
SwiftUI view tree is hosted inside the panel via `NSHostingView`.

The window **auto-sizes to its content**: no empty space below the
list. Achieved by computing the SwiftUI tree's `.fittingSize` and
resizing the panel after each layout pass.

`FloatingPanel` overrides `setFrame` to choose which edge stays put on
height changes. By default the top edge is fixed and the panel grows
down. It switches to a fixed bottom edge when growing down would run
off the visible screen, or when the user has parked the panel within
`bottomStickZone` (80 pt) of the bottom. The chosen edge is remembered
(`anchoredToBottom`) until the user moves the panel (detected by the
frame no longer matching `lastAnchoredFrame`), so a collapse mirrors
the preceding expansion instead of jumping the input bar. The result is
then clamped into the visible screen.

## Screen-share detection

`ScreenShareMonitor` protocol in Core, `MacScreenShareMonitor` in the
macOS app. Implementation strategy:

- Primary: `SCShareableContent` + `CGPreflightScreenCaptureAccess()` to
  detect active capture sessions.
- Fallback: watch `NSWorkspace.shared.runningApplications` for known
  sharing apps (Zoom, Meet, Teams, …) — handles the case where the
  user hasn't granted screen-recording permission to your app.

Publishes a `Bool` via Combine / `AsyncStream`. Area 2 binds to it and
hides when `true`.

## macOS menu-bar icon

`NSStatusItem` for **app-level controls only**. Folder access lives in
the floating panel's inline tab strip, not here.

Menu items:
- **Settings…** — opens a regular SwiftUI Settings scene
- **Quit**

Lives entirely in `App-macOS/MenuBar/`.

## Settings

A regular SwiftUI `Settings` scene (separate window, not a popover).

- **Appearance:** Dark / Light / Auto (follows system).
- More panes will land later (sync account, content-provider auth,
  hotkeys, …).

State is kept in an `@Observable AppSettings` model, persisted via
`@AppStorage` keys. Theme propagates to the panel by setting
`NSApp.appearance` (and SwiftUI's `.preferredColorScheme(...)` on the
hosted tree as a backup) so AppKit chrome and SwiftUI content stay in
sync.

## Folder navigation (in-panel)

The floating panel hosts an inline tab strip:
`Today (count) · Tomorrow · Limbo · Done · Cal · <date>`. Tab selection
drives Area 2's content via the same `Repository.items[folder]` lookup
already in place — no extra navigation stack needed for the four
folders. `Cal` (calendar view) is a future surface; treat it as a
placeholder tab that routes to a stub view for now.

## Per-row item actions

Hover-revealed icons in each row, calling `Repository`:
- **Move to Limbo** → `repository.move(id:, to: .libmo)`
- **Move to Tomorrow** → `repository.move(id:, to: .tomorrow)`
- **Mark Done** → `repository.move(id:, to: .done)`
- **Delete** → `repository.softDelete(id:)`

`Delete` is soft-delete (sets `deletedAt`, leaves the row, emits a
`ChangeRecord` for sync). The Done folder additionally exposes an
"empty trash" affordance that calls `repository.emptyDone()` for hard
deletion.

## Pagination

Area 2 caps at **10 items per page**. Pagination is a UI concern — it
slices `Repository.items[currentFolder]` for display and keeps the
selected page in view-local `@State`. No protocol or storage changes.

## Visual directions & design tokens

The design has two directions:

| Token | Dark Glass | Index |
|---|---|---|
| Body size | 13 pt | 12 pt |
| Row height | 36 pt | 28 pt |
| Accent | `#7AA7FF` | `#5E5CE6` |
| Surface | `NSVisualEffectView` (`.hudWindow`, vibrancy) | Solid + light interior card |

Both directions support light and dark themes via the same component
tree. Tokens are defined as SwiftUI environment values so a single
`Theme` switch reskins the whole app.

## Auth (per content provider)

`AuthStore` protocol in Core; `MacAuthStore` backs onto Keychain. Each
content provider that needs auth (Jira, …) asks the registry's shared
`AuthStore` for tokens keyed by provider id. **Provider auth is
separate from any future sync-account auth** — don't conflate them.

## Testing strategy

- `ToDragDoCoreTests` covers: registry dispatch, day rollover, repository
  invariants, change-log generation. No platform deps.
- macOS app target gets a thin smoke test only — most logic is in Core.

## Dependency injection

Init injection only. **No singletons.** The macOS app composes the
object graph once at launch and passes references down through
`@Environment` or initializer args.

```swift
// App-macOS/ToDragDoApp.swift
@main
struct ToDragDoApp: App {
    @State private var repository: Repository

    init() {
        let storage = try! StorageFactory.makeItemStorage()
        _repository = State(initialValue: Repository(storage: storage))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(repository)
                .task { try? await repository.reload() }
        }
    }
}
```

When real services land — `ContentTypeRegistry`, `ScreenShareMonitor`,
`PasteboardService`, `AuthStore` — they're constructed in the same place
and either:
- composed into a single `@Observable AppState` injected via
  `.environment(appState)`, or
- injected individually via `.environment(...)` on the root view.

Tests construct the same graph with fake conformers (e.g.
`InMemoryItemStorage` already lives in the test target).

## Navigation

Both surfaces are shallow; no Coordinator pattern.

- **Floating panel:** root view is `MainPanelView` (Area 1 + Area 2). No
  push navigation. Item full-views fold open in place via
  `matchedGeometryEffect`.
- **Status bar popover:** `NavigationStack` with a `[Folder]` path so
  Today / Tomorrow / Libmo / Done can deep-link from the menu and pop
  back without state surgery.

## Conventions

- Core's public API imports no Apple frameworks. `SwiftData` is referenced
  only inside `SwiftDataStorage/`, gated behind `#if canImport(SwiftData)`.
- Core never imports AppKit / UIKit anywhere. Period.
- One provider per file in `ContentTypes/Providers/` (when added).
- All writes go through `Repository`. Views never touch `ModelContext` or
  any `@Model` directly.
- All app state is `@Observable`. No `ObservableObject`, no `@Published`.
- Dependencies are injected. No singletons, no `.shared`.
- IDs are UUIDs, generated client-side, always.
- Soft-delete by default; hard-delete only for the Done folder's "empty
  trash" action.
- New persistence backend = new `ItemStorage` conformer + new `Platform`
  switch arm in `StorageFactory`. Nothing else changes.
