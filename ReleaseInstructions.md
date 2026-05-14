# Release Instructions

Steps to ship a build that uses **Production** CloudKit. Skip any step and
the first save on a customer's device fails with `serverRejectedRequest:
Cannot create new type … in production schema` (or just silently shows no
data, depending on which step you skipped).

The current development setup forces the **Development** CloudKit
environment — see `ToDragDo/ToDragDo.entitlements`
(`com.apple.developer.icloud-container-environment = Development`). All
local testing data lives in Development and **does not migrate** to
Production automatically.

---

## Pre-flight checklist (every release)

### 1. Deploy the schema from Development to Production

CloudKit refuses to auto-create record types or fields in Production. The
schema must be promoted explicitly.

1. Open [CloudKit Console](https://icloud.developer.apple.com/dashboard/)
2. Select container `iCloud.com.turtle.todragdo.sync.container`
3. **Schema → Deploy Schema Changes…**
4. Review the diff (record types, fields, indexes, security roles) and
   confirm the deploy

Re-do this any time you change a `@Model` field, add a record type, or
change indexes — Production schema does **not** update on its own.

### 2. Entitlements — already split per configuration

The project already maps each configuration to its own entitlements file:

| Configuration | Entitlements file | `icloud-container-environment` | `aps-environment` |
|---|---|---|---|
| Debug | `ToDragDo/ToDragDo.entitlements` | `Development` | `development` |
| Release | `ToDragDo/ToDragDoRelease.entitlements` | `Production` | `production` |

A standard `Product → Archive` (Release config) automatically embeds the
Production values. Nothing to flip by hand. If you ever add or rename
keys (e.g. adding HealthKit), update **both** files in lockstep.

### 3. Archive and verify the signed binary

After `Product → Archive`, before uploading, confirm the embedded
entitlements:

```sh
codesign -d --entitlements - /path/to/exported/ToDragDo.app
```

Look for:

```
com.apple.developer.icloud-container-environment → Production
com.apple.developer.aps-environment              → production
```

If either is wrong, the archive talks to the wrong environment regardless
of what you put in source. Re-export.

### 4. Smoke test on a clean device / account

1. Install the signed Release build on a Mac with an iCloud account
   that has **never** run any prior build of this app.
2. Open **Settings → Sync**. The "iCloud environment:" line (read live
   from the signed binary by `CloudKitEnvironmentProbe`) must say
   `Production`.
3. Create an item. Within ~20 s `Pending` should reach 0 with no error
   in the red box.
4. Install the same build on a second device with the same iCloud
   account. The item should appear within ~20 s of launch.

If `Pending` stays > 0 with a CKError shown, copy the full red-box text
— it has the verbose CKError chain (code, server message, partial
errors). The two most likely failures at this stage:

- **`serverRejectedRequest` / "Cannot create new type"** → step 1 wasn't
  done, or the model changed since the last deploy.
- **`notAuthenticated`** → the test iCloud account isn't signed in on
  the device.

---

## Data migration: Development → Production

There is no automatic path — the outbox marks rows pushed under provider
id `"icloud"` without distinguishing environments, so existing rows
won't re-emit on their own when the build switches Dev → Prod.

Options, in order of effort:

- **Accept the cold start.** Easiest. Your testing data was always
  disposable; release-day customers start empty anyway.
- **Re-sync via the Settings UI.** Install the Production-signed build,
  open **Settings → Sync**, and click **Re-sync All…** on the iCloud
  row. This calls `Repository.resyncAllItems()`, which appends a fresh
  current-state outbox row for every local item (including soft-deleted
  ones) so the next sync cycle pushes everything to the new
  environment. Items themselves are not modified; only the outbox grows.
  Run this on each Mac after the cutover.
- **Manual replay via CK Console.** Possible but tedious — the snapshot
  payload is a JSON `CKAsset`, not a flat field. Not recommended.

---

## Operational notes

- **The runtime environment is set at sign time, not at runtime.**
  Changing `com.apple.developer.icloud-container-environment` only takes
  effect on the next build + sign + reinstall. Verify with `codesign`.
- **APNs and CloudKit environments are independent but should match.**
  Mixing `aps-environment=production` with
  `icloud-container-environment=Development` (or vice versa) is a
  supported but confusing state and not worth the cognitive load.
- **Schema deploys are one-way and additive for record types.** You can
  add fields and record types via deploy, but you cannot remove them
  from Production via the console — they stay in the schema forever
  (with limited rename support). Treat Production schema changes as
  permanent.
- **Pushed changes never delete from the outbox.** The
  `PersistedChange` rows accumulate forever (by design — they're the
  authoritative log). If they ever get large enough to matter,
  introduce a `pushedBefore` retention sweep in `Repository`.
