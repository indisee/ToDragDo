---
description: Build ToDragDo (Release config, Production iCloud env) into Artifacts/
---

Run `./scripts/build-prod.sh` from the repo root.

The script builds the `ToDragDo` scheme in Release configuration with the project's own entitlements (`ToDragDo/ToDragDoRelease.entitlements`), so the resulting `.app` talks to the **Production** CloudKit environment. It verifies the embedded entitlements and only then copies the app to `Artifacts/ToDragDo {timestamp}-prod/ToDragDo.app`.

Signing needs the user's keychain: if the sandboxed shell reports `0 valid identities` or a missing "Mac Development" certificate, run the script in the user's Terminal panel instead. If the certificate is expired (`CSSMERR_TP_CERT_EXPIRED`), tell the user to renew it in Xcode → Settings → Accounts → Manage Certificates (see ReleaseInstructions.md step 0); don't try to fix signing yourself.

After the script exits:

1. Report the final `.app` path.
2. Show the `icloud-container-environment` and `aps-environment` lines (must say `Production` / `production`).
3. If the build fails, surface the first xcodebuild error, not the trailing summary.

Before the first Production launch on a device, remind the user of the cutover order in ReleaseInstructions.md (schema deployed, most complete device first, one device at a time).
