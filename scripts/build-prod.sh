#!/usr/bin/env bash
# Build ToDragDo for the Production iCloud environment (Release config,
# ToDragDo/ToDragDoRelease.entitlements as configured in the project) and
# stash the .app under Artifacts/ToDragDo {YYYY-MM-DD HH-MM-SS}-prod/.
#
# Counterpart of build-dev-icloud.sh. Fails if the signed app doesn't
# embed the Production CloudKit environment.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/ToDragDo"
PROJECT="$PROJECT_DIR/ToDragDo.xcodeproj"
SCHEME="ToDragDo"
CONFIG="Release"

TIMESTAMP="$(date '+%Y-%m-%d %H-%M-%S')"
OUT_DIR="$REPO_ROOT/Artifacts/ToDragDo $TIMESTAMP-prod"
DERIVED="$REPO_ROOT/.build-prod"

cd "$PROJECT_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  build

APP_SRC="$DERIVED/Build/Products/$CONFIG/ToDragDo.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "Build reported success but $APP_SRC not found" >&2
  exit 1
fi

ENTS="$(codesign -d --entitlements - --xml "$APP_SRC" 2>/dev/null | plutil -p -)"
echo
echo "Embedded entitlements:"
echo "$ENTS" | grep -E 'icloud-container-environment|aps-environment' || true

if ! echo "$ENTS" | grep 'icloud-container-environment' | grep -q '"Production"'; then
  echo "ERROR: icloud-container-environment is not Production — not copying." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
cp -R "$APP_SRC" "$OUT_DIR/"
echo
echo "Done: $OUT_DIR/ToDragDo.app"
open "$OUT_DIR"
