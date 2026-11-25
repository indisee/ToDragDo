# ToDragDo

A todo list that floats above everything else on your Mac.
Type it, drop it, get it done today, or push it to tomorrow.

## What it does

- **Always on top.** A small borderless panel that floats above other
  apps, including full-screen ones. Drag it anywhere. It grows and
  shrinks with its content, and remembers which edge to keep in place
  when you park it near the bottom of the screen.
- **Type or drag in anything.** Text, links, files, and images all
  become items. Links get a preview, and each content type renders its
  own row and expanded view.
- **Today → Tomorrow → Limbo → Done.** Every item lives in one folder.
  Unfinished Today items roll over to Tomorrow at the end of the day,
  and Tomorrow becomes the new Today. Limbo holds everything that's
  "not now" and makes items blink once they've sat there too long.
- **Fast row actions.** Move to Tomorrow or Limbo, mark done, delete,
  or set a date that routes the item to the right folder. On iPhone,
  swipe the row.
- **Projects.** Colour-coded projects you can tag items with and filter by.
- **Done summary.** See what you closed, or what's still open, for any
  day or week.
- **Private by default while sharing.** The panel can be hidden from
  screen sharing, recordings, and screenshots.
- **iCloud sync** between Mac, iPhone, and iPad with no separate
  account, built on `CKSyncEngine`.
- **iPhone and iPad app** with the same folders and a bottom tab bar.
- **Widgets and shortcuts.** "Add to Today" quick-add and project list
  widgets, Lock Screen widgets, and an App Shortcut you can put on the
  Action Button.
- **Light, dark, or follow the system.**

## Screenshots

<table>
  <tr>
    <th>macOS</th>
    <td align="center"><img src="docs/screenshots/macos-panel.png" width="180" alt="Panel with row actions"><br><sub>Panel with row actions</sub></td>
    <td align="center"><img src="docs/screenshots/macos-project-filter.png" width="190" alt="Project filter"><br><sub>Project filter</sub></td>
    <td align="center"><img src="docs/screenshots/macos-done-summary.png" width="200" alt="Done summary"><br><sub>Done summary</sub></td>
    <td align="center"><img src="docs/screenshots/macos-settings-projects.png" width="240" alt="Projects settings"><br><sub>Projects settings</sub></td>
  </tr>
  <tr>
    <th>iPhone</th>
    <td align="center"><img src="docs/screenshots/ios-today.png" width="170" alt="Today"><br><sub>Today</sub></td>
    <td align="center"><img src="docs/screenshots/ios-tomorrow-dark.png" width="170" alt="Tomorrow, dark mode"><br><sub>Tomorrow, dark mode</sub></td>
  </tr>
</table>

<sub>All screenshots use made-up demo data (see <a href="#demo-mode">Demo mode</a>).</sub>

## Requirements

- macOS 26.1+ / iOS 26+
- Xcode 26
- An Apple Developer team with iCloud (CloudKit) and App Groups enabled,
  to run with sync

## Project layout

```
ToDragDo/
├── ToDragDo/            macOS app (floating NSPanel, menu-bar item, Settings)
├── ToDragDo-iOS/        iPhone / iPad app
├── ToDragDoWidgets/     WidgetKit extension
└── Core/ToDragDoCore/   Swift package shared by all targets
    ├── ToDragDoCore          models, Repository, SwiftData storage, sync core
    ├── ToDragDoSync          CloudKit adapter, environments, migration
    ├── ToDragDoContentTypes  text / URL / file / image providers
    └── ToDragDoIntents       App Intents, App Group, deep links
```

## Building

Open `ToDragDo/ToDragDo.xcodeproj` and run the `ToDragDo` (macOS) or
`ToDragDo-iOS` scheme.

- **Debug** builds talk to the **Development** CloudKit environment.
- **Release** builds talk to **Production**.

```bash
./scripts/build-prod.sh
```

builds a signed macOS Release app into `Artifacts/` and checks that it
targets Production. Run the core tests with:

```bash
cd ToDragDo/Core/ToDragDoCore && swift test
```

### Demo mode

Launch either app with `-DemoMode` to get an in-memory store filled with
fake projects and items and no sync. It never touches your real data, so
it's safe for screenshots on a device that also runs the real app.

```bash
open -n ToDragDo.app --args -DemoMode
```

## Docs

- [ARCHITECTURE.md](ARCHITECTURE.md): how the app is put together
  (storage, outbox-based sync, CloudKit environments, the floating panel).
- [ReleaseInstructions.md](ReleaseInstructions.md): shipping a Production
  build, schema deploys, and the Development → Production migration.
- [REQUIREMENTS.md](REQUIREMENTS.md) and
  [REQUIREMENTS-iOS.md](REQUIREMENTS-iOS.md): product requirements.
