# Release Instructions

Steps to ship a build that uses **Production** CloudKit. Skip any step and
the first save fails with `serverRejectedRequest: Cannot create new type …
in production schema`, or the app just shows no data.

Development and Production are **separate CloudKit databases**. A build
talks to exactly one of them, chosen by the signed
`com.apple.developer.icloud-container-environment` entitlement. Debug
builds (and `scripts/build-dev-icloud.sh`) use Development; Release builds
use Production. Data does not cross between them on the server; the
one-time move happens from the local store (see
[Data migration](#data-migration-development--production)).

---

## Pre-flight checklist (every release)

### 0. Signing certificate

Signing needs a valid **Apple Development** certificate for team
`YOUR_TEAM_ID` in the login keychain. They expire after a year. Check:

```sh
security find-identity -p codesigning
```

`CSSMERR_TP_CERT_EXPIRED` or `0 valid identities found` means:

1. Xcode → **Settings → Accounts** → sign in to the Apple ID again if
   Xcode says the session expired.
2. Select the team → **Manage Certificates…** → **+** →
   **Apple Development**.
3. Re-run the check; the new identity must be listed as valid.

Command-line builds don't sign in for you (`-allowProvisioningUpdates`
fails if the Xcode account session is stale).

### 1. Deploy the schema from Development to Production

CloudKit refuses to auto-create record types or fields in Production. The
schema must be promoted explicitly, and only the CloudKit Console can do
that (`cktool` imports schemas into Development only).

1. Open [CloudKit Console](https://icloud.developer.apple.com/) →
   **CloudKit Database**.
2. Select container `iCloud.com.turtle.todragdo.sync.container`.
3. Make sure the environment switcher says **Development**.
4. Click **Deploy Schema Changes…** (bottom of the left sidebar).
5. Review the diff (record types, fields, indexes, security roles) and
   confirm.

Verify: switch to **Production** → **Schema → Record Types**. Record type
`ChangeRecord` must exist with fields `entityType`, `entityId`, `op`,
`ts`, `deviceId`, `snapshot` (Asset) and `snapshotData` (Bytes). The zone
`TDDChanges` is created by the app on first sync; it isn't part of the
schema.

Re-do the deploy any time a record type, field or index changes.
Production schema does **not** update on its own.

### 2. Entitlements — split per configuration

| Target / config | Entitlements file | `icloud-container-environment` | `aps-environment` |
|---|---|---|---|
| macOS Debug | `ToDragDo/ToDragDo.entitlements` | `Development` | `development` |
| macOS Release | `ToDragDo/ToDragDoRelease.entitlements` | `Production` | `production` |
| iOS Debug | `ToDragDo-iOS/ToDragDo-iOS.entitlements` | `Development` | `development` |
| iOS Release | `ToDragDo-iOS/ToDragDo-iOS-Release.entitlements` | `Production` | `production` |
| Widget Debug | `ToDragDoWidgets/ToDragDoWidgets.entitlements` | `Development` | `development` |
| Widget Release | `ToDragDoWidgets/ToDragDoWidgets-Release.entitlements` | `Production` | `production` |

A Release build embeds the Production values automatically. When you add
or rename a key (e.g. HealthKit), update the Debug and Release files of
that target together.

iOS can't read its own entitlements at runtime, so the iOS app and the
widget also carry `TDCloudKitEnvironment` in Info.plist, filled from the
per-configuration `TODRAGDO_CLOUDKIT_ENV` build setting
(Debug = `Development`, Release = `Production`). Keep it equal to the
entitlements file. If you ever override `CODE_SIGN_ENTITLEMENTS` on the
command line for iOS, override `TODRAGDO_CLOUDKIT_ENV` too.

### 3. Build and verify the signed binary

**macOS:**

```sh
./scripts/build-prod.sh
```

Builds the `ToDragDo` scheme in Release, checks the embedded
entitlements, and copies the app to
`Artifacts/ToDragDo <timestamp>-prod/`. It stops with an error if the
signed app doesn't say `Production`. (`scripts/build-dev-icloud.sh` is
the Development counterpart.)

**iOS:** build the `ToDragDo-iOS` scheme in the **Release** configuration
to the device (Xcode: Edit Scheme → Run → Build Configuration = Release),
or Archive for TestFlight.

For anything built another way, check by hand:

```sh
codesign -d --entitlements - /path/to/ToDragDo.app
```

Expect `icloud-container-environment → Production`. If it's wrong, the
app talks to the wrong environment regardless of the source.

`aps-environment` comes from the provisioning profile, not only from the
entitlements file: a build signed with an **Apple Development** identity
(what `build-prod.sh` produces) gets `development` even though the
Release file says `production`. CloudKit data still goes to Production,
but CloudKit's silent pushes are sent through production APNs and don't
reach that build, so it syncs on the ticker / wake / launch instead of
instantly. For instant push, export with Developer ID (Archive →
Distribute App → Developer ID) or ship through the App Store/TestFlight.

### 4. Smoke test

1. Open **Settings → Sync**. The **Environment:** line must say
   `Production` (macOS reads the signed entitlement; iOS shows
   `Production (from Info.plist)`).
2. Create an item. Within ~20 s `Pending` should reach 0 with no error.
3. On a second device with the same iCloud account and a Production
   build, the item should appear within ~20 s of launch.

If `Pending` stays > 0, copy the full error text (it has the verbose
CKError chain). Most likely causes:

- **`serverRejectedRequest` / "Cannot create new type"** → step 1 wasn't
  done, or the model changed since the last deploy.
- **`notAuthenticated`** → the iCloud account isn't signed in on the
  device.

---

## Data migration: Development → Production

### Automatic (default)

On the first launch of a Production build, `ProductionMigration` waits
for the first successful pull from Production. Before the pulled records
are applied, it:

1. writes a JSON backup of all local data (items including trashed ones,
   projects) to `Backups/pre-production-<timestamp>.json` next to the
   store:
   - macOS: next to the store in the data folder (`DataLocation`);
   - iOS: inside the App Group container;
2. queues every local item and project that Production doesn't have yet.

The first device finds Production empty and uploads everything; later
devices only add what they alone have, so they don't overwrite each
other. It runs once per device (`todragdo.migration.production.done`).
The result and the backup path are shown in **Settings → Sync** under the
Environment line. If it fails, it retries on the next pull.

Cutover order:

1. On the Development builds, let every device finish syncing
   (`Pending: 0`).
2. Deploy the schema (step 1).
3. Install the Production build on the device with the most complete
   data first. Check Settings → Sync: Environment `Production`,
   migration line "Uploaded N of M…", `Pending` reaches 0.
4. Then the other devices, one at a time. Their migration line should say
   "Production already had N records; uploaded K missing ones".
5. Don't launch the Production build for the first time on two devices
   at the same moment: both would upload their full copies.

The `CKSyncEngine` state is stored per environment
(`todragdo.cloudkit.state.icloud.<Environment>`), so a Production build
starts with a clean engine state instead of replaying Development tokens.
The old unsuffixed key is moved to `.Development` on the first launch of
a Development build.

The Development database is left untouched and serves as an archive. Do
**not** use "Reset Development Environment" in the Console unless you
mean to delete it.

### Manual fallback

- **Re-sync All…** in Settings → Sync appends a fresh outbox row for every
  local item and project, so the next sync pushes everything. Use it on
  **one** device only: remote records overwrite local ones without a
  newer-wins check, so re-uploading from several devices can clobber
  newer edits.
- **Restore from backup:** the JSON in `Backups/` decodes as
  `RepositoryBackup` (`RepositoryBackup.decode(from:)`). There is no
  restore UI yet.

---

## Operational notes

- **Don't mix Development and Production builds on one device.** They
  share the same local store and outbox (same bundle id and App Group),
  and the outbox isn't split by environment. Edits made in a Development
  build would later be pushed to Production too, and Development data
  would mix into the local store. After the cutover, run Development
  builds only on a separate machine, user account, or simulator.
- **The runtime environment is set at sign time, not at runtime.**
  Changing `icloud-container-environment` only takes effect on the next
  build + sign + reinstall. Verify with `codesign`.
- **APNs and CloudKit environments are independent but should match.**
  Mixing `aps-environment=production` with
  `icloud-container-environment=Development` (or vice versa) works but
  isn't worth the confusion.
- **Schema deploys are one-way and additive.** You can add fields and
  record types, but you can't remove them from Production. Treat
  Production schema changes as permanent.
- **Pushed changes never delete from the outbox.** The `PersistedChange`
  rows accumulate forever by design (they're the authoritative log). If
  they ever get large enough to matter, add a `pushedBefore` retention
  sweep in `Repository`.
