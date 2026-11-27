#!/usr/bin/env bash
# Build a local-only ToDragDo for macOS that runs on any Mac without an
# Apple Developer certificate: Release config, universal (arm64 + x86_64),
# ad-hoc signed, no iCloud (the app detects the missing entitlement and
# keeps data on the device). Output: Artifacts/ToDragDo {timestamp}-local/
# with the .app, a .zip and a .dmg.
#
# Signed with ToDragDo/ToDragDoLocal.entitlements, which keeps the App
# Sandbox. Never ship this build unsandboxed: outside the sandbox the app
# shares ~/Library/Application Support with every other program.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/ToDragDo"
PROJECT="$PROJECT_DIR/ToDragDo.xcodeproj"
ENTITLEMENTS="ToDragDo/ToDragDoLocal.entitlements"
CONFIG="Release"

TIMESTAMP="$(date '+%Y-%m-%d %H-%M-%S')"
OUT_DIR="$REPO_ROOT/Artifacts/ToDragDo $TIMESTAMP-local"
DERIVED="$REPO_ROOT/.build-local"

cd "$PROJECT_DIR"
xcodebuild \
  -project "$PROJECT" \
  -scheme ToDragDo \
  -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER= \
  CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build

APP="$DERIVED/Build/Products/$CONFIG/ToDragDo.app"
[[ -d "$APP" ]] || { echo "Build reported success but $APP not found" >&2; exit 1; }

ENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p -)"
echo "Embedded entitlements:"; echo "$ENTS"
if ! echo "$ENTS" | grep -q '"com.apple.security.app-sandbox" => true'; then
  echo "ERROR: app is not sandboxed — not shipping it." >&2
  exit 1
fi
if echo "$ENTS" | grep -q 'icloud'; then
  echo "ERROR: ad-hoc build carries iCloud entitlements; macOS would refuse to launch it." >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"

VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
NAME="ToDragDo-$VERSION-macOS-universal-local"
mkdir -p "$OUT_DIR"
cp -R "$APP" "$OUT_DIR/"
ditto -c -k --keepParent "$OUT_DIR/ToDragDo.app" "$OUT_DIR/$NAME.zip"

STAGE="$(mktemp -d)"
cp -R "$OUT_DIR/ToDragDo.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname ToDragDo -srcfolder "$STAGE" -ov -format UDZO "$OUT_DIR/$NAME.dmg"
rm -rf "$STAGE"

echo
echo "Done: $OUT_DIR"
