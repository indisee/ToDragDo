---
description: Compile-only verify ToDragDo (Release config, Dev iCloud entitlements) — no Artifacts copy
---

Run `./scripts/test-build.sh` from the repo root.

The script invokes `xcodebuild` with the same scheme / configuration / entitlements override as `build-dev-icloud.sh`, but skips the Artifacts copy, the entitlements verification, and the `open` step. Use it during iteration when the goal is "does it still build" — not "give me a stamped Dev artifact."

After the script exits:

1. If it finishes with `** BUILD SUCCEEDED **`, report success in one line.
2. If it fails, surface the first xcodebuild error (`grep "error:"` style — not the trailing summary block) so the user can see the root cause without scrolling.

Do not run `build-dev-icloud` after this. When the user actually needs a stamped Artifact, they will invoke `build-dev-icloud` explicitly.
