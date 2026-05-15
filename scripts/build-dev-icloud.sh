#!/usr/bin/env bash
# Build ToDragDo with the Development iCloud environment and stash the .app
# under Artifacts/ToDragDo {YYYY-MM-DD HH-MM-SS}-dev/.
#
# Use this when the Production CloudKit schema hasn't caught up to local
# model changes (e.g. "Cannot create new type X in production schema") and
# you need a secondary Mac running against the Development environment.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/ToDragDo"
PROJECT="$PROJECT_DIR/ToDragDo.xcodeproj"
SCHEME="ToDragDo"
CONFIG="Release"
ENTITLEMENTS_REL="ToDragDo/ToDragDo.entitlements"

TIMESTAMP="$(date '+%Y-%m-%d %H-%M-%S')"
OUT_DIR="$REPO_ROOT/Artifacts/ToDragDo $TIMESTAMP-dev"
DERIVED="$REPO_ROOT/.build-dev-icloud"

mkdir -p "$OUT_DIR"

cd "$PROJECT_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS_REL" \
  build

APP_SRC="$DERIVED/Build/Products/$CONFIG/ToDragDo.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "Build reported success but $APP_SRC not found" >&2
  exit 1
fi

cp -R "$APP_SRC" "$OUT_DIR/"

echo
echo "Embedded entitlements:"
codesign -d --entitlements - "$OUT_DIR/ToDragDo.app" 2>&1 \
  | grep -A 2 -E 'icloud-container-environment|aps-environment' || true

echo
echo "Done: $OUT_DIR/ToDragDo.app"

open "$OUT_DIR"
