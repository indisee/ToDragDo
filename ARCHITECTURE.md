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
├── REQUIREMENTS.md
├── ARCHITECTURE.md
└── ToDragDo/                             (Xcode project root)
    ├── ToDragDo.xcodeproj
    ├── ToDragDo/                         macOS app target
    │   ├── ToDragDoApp.swift             composes Repository at launch
    │   ├── ContentView.swift             smoke-test view (placeholder UI)
    │   ├── Assets.xcassets/
    │   ├── Windows/                      (later) FloatingPanel.swift, NSPanel
    │   ├── StatusBar/                    (later) StatusBarController.swift
    │   ├── Services/                     (later) macOS impls of Core protocols
    │   │   ├── MacScreenShareMonitor.swift
    │   │   ├── MacPasteboardService.swift
    │   │   └── MacAuthStore.swift        Keychain
    │   └── Views/                        (later) real UI
    │       ├── Area1DropView.swift
    │       ├── Area2ListView.swift
    │       ├── ItemRow.swift             matchedGeometryEffect fold/unfold
    │       └── FolderMenuView.swift
    │
    └── Core/ToDragDoCore/                Swift Package, no Apple frameworks in public API
        ├── Package.swift                 platforms: [.macOS(.v14), .iOS(.v17)]
        ├── Sources/ToDragDoCore/
        │   ├── Models/                   plain Codable structs
        │   │   ├── Folder.swift
        │   │   ├── Item.swift
        │   │   ├── ChangeRecord.swift
        │   │   └── DeviceID.swift
        │   ├── Platform/
        │   │   ├── Platform.swift        enum + .current
        │   │   └── StorageFactory.swift  dispatch on Platform
        │   ├── Persistence/
        │   │   ├── ItemStorage.swift     protocol + StorageError
        │   │   ├── Repository.swift      @MainActor @Observable, talks to ItemStorage
        │   │   └── SwiftDataStorage/     #if canImport(SwiftData)
        │   │       ├── SwiftDataStorage.swift
        │   │       ├── PersistedItem.swift   internal @Model
        │   │       ├── PersistedChange.swift internal @Model
        │   │       └── SchemaV1.swift
        │   ├── ContentTypes/             (later) registry + providers
        │   ├── Scheduling/               (later) DayRolloverService
        │   ├── Sync/
        │   │   ├── RemoteAdapter.swift   protocol
        │   │   ├── SyncCursor.swift
        │   │   └── NoopRemoteAdapter.swift
        │   └── Services/                 (later) protocol-only ScreenShare,
        │                                 Pasteboard, AuthStore
        └── Tests/ToDragDoCoreTests/
            ├── InMemoryItemStorage.swift  pure-Swift test fake
            ├── RepositoryTests.swift
            └── ChangeLogTests.swift
```

**Rule:** `Core` never imports `AppKit` or `UIKit`. The public API
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

    func push(_ changes: [ChangeRecord]) async throws
    func pull(since cursor: SyncCursor) async throws
        -> (changes: [ChangeRecord], next: SyncCursor)
}
```

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
}
```

Settings binds directly to `SyncCoordinator.statuses` to render the
per-provider status list. Toggling a provider on/off flips its
`enabled` flag and (if turning off) leaves its outbox state intact so
re-enabling resumes from where it stopped.

### iCloud adapter

`CloudKitRemoteAdapter` (lives in the macOS app target — Apple-only):
- Uses **`CKSyncEngine`** (the modern API) against the user's private
  CloudKit database.
- Encodes `ChangeRecord` to a `CKRecord` keyed by `id`; the JSON
  `snapshot` payload is a `CKAsset` for any non-trivial size.
- Pull cursor uses `CKSyncEngine`'s server-state token, persisted via
  `SyncCursor.token`.

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
