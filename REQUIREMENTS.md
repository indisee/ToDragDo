# ToDragDo — Requirements

A todo app with a twist. **Native** app (not a web page).

## Platforms

- **First:** macOS
- Potentially: Windows
- Potentially: mobile (iOS / Android)

A common core shared between platforms is desirable for the future.

## Workflow

An **always-on-top** rectangular window made of two areas. The window
has **no native title bar / chrome**; the user drags it around by
clicking and dragging the window body.

### Area 1 — Input

- Tap / click to start typing a todo note.
- Drag-n-drop anything into the area (text, files, images, links, …).
- An inline **folder tab strip** sits between Area 1 and Area 2:
  `Today (count) · Tomorrow · Limbo · Done · Cal · <date>`. Selecting a
  tab switches Area 2 to that folder's contents.

### Area 2 — List

- Items in the selected folder, shown as a list of short descriptions
  with type-specific leading icon (`=` text, `+` Jira, `0` URL, …) and
  trailing context (timestamp / Jira key / domain / …).
- Clicking an item shows the full item **in place** (animated fold /
  unfold). Each content type renders its own full view.
- Per-row hover actions: **Move to Limbo**, **Move to Tomorrow**,
  **Mark Done**, **Delete**.
- List is paginated at **10 items per page**; footer shows range and
  page indicator.
- Area 2 is **hidden while screen sharing is on** — only Area 1 + a
  small "list hidden — sharing" indicator remain visible.
- The user can manually **collapse Area 2** via a chevron in the title
  bar; collapsed state shows a count and an expand affordance.

## Item lifecycle

- When a new item is added (via text or drag-n-drop), append it to the
  current folder's list (default: Today).
- Each item supports the following fast actions:
  - Move to **Limbo** — temporary "folder" for everything non-today.
  - Move to **Tomorrow**.
  - Mark as **Done** — moves to the Done folder.
  - **Delete** — removes the item from any folder.
- **End of day:** everything left in Today moves to Tomorrow.
- **Next day** starts from everything that was in the Tomorrow list.

## Appearance

- **Dark and light themes**, plus an **auto** mode that follows the
  system appearance.
- The user changes appearance in **Settings**.

## macOS menu-bar icon

A small system menu-bar icon (NSStatusItem) for **app-level controls only**:

- **Settings…** (appearance toggle for now; more later)
- **Quit**

The menu-bar icon does **not** expose folder access — folders live in
the always-on-top window's tab strip.

## Core requirements

- **Extensible drag-n-drop content types.**
  Easy way to add new item types with their own preview / full-view rendering.
  Examples:
  - Jira ticket link → custom preview, action buttons, auth flow.
  - Image → image preview / full view.
  - Zillow link → real-estate-specific preview.
  - Plain text, generic URLs, files, …
- **Platform-specific code is isolated** in its own class / module, separate from the shared core.

## Sync

- **iCloud sync is part of v1.** Items sync across the user's Apple
  devices through their iCloud account, with no separate sign-in.
- The sync layer supports **multiple providers running concurrently**.
  Additional backends (Supabase, custom server, …) can be added later
  and enabled alongside iCloud.
- **Settings shows per-provider sync status:** display name, last
  successful sync time, last attempt time, error (if any), and a count
  of pending changes. Each provider can be toggled on/off independently.
- Conflict strategy: last-write-wins per field (driven by `updatedAt`).
  Sufficient for a personal todo app on a small number of devices.

## Good to have

- Contextual menu (system / app) to add items (files, text, …) to **Today** or **Tomorrow**.

## Future

- Additional sync backends beyond iCloud (Supabase, custom server, …).
