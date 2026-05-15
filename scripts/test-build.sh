#!/usr/bin/env bash
# Compile-only verification: build ToDragDo with the same flags as
# build-dev-icloud.sh but skip the Artifacts copy + entitlements probe.
# Use when iterating on code and you just need to know "does it still build".
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/ToDragDo"
PROJECT="$PROJECT_DIR/ToDragDo.xcodeproj"
SCHEME="ToDragDo"
CONFIG="Release"
ENTITLEMENTS_REL="ToDragDo/ToDragDo.entitlements"
DERIVED="$REPO_ROOT/.build-dev-icloud"

cd "$PROJECT_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS_REL" \
  build
