---
description: Build ToDragDo (Release config, Development iCloud env) into Artifacts/
---

Run `./scripts/build-dev-icloud.sh` from the repo root.

The script builds the `ToDragDo` scheme in Release configuration but overrides `CODE_SIGN_ENTITLEMENTS` to `ToDragDo/ToDragDo.entitlements` so the resulting `.app` talks to the **Development** CloudKit environment. The signed app is copied to `Artifacts/ToDragDo {timestamp}-dev/ToDragDo.app`.

After the script exits:

1. Report the final `.app` path.
2. Show the `icloud-container-environment` and `aps-environment` lines from the entitlements verification block (must say `Development` / `development`).
3. If the build fails, surface the first xcodebuild error, not the trailing summary.

Do not modify the entitlements files or project settings — the override is command-line only and must not leak into the next regular Release archive.
