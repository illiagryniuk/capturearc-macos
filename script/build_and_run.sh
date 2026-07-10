#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CaptureArc"
PRODUCT_NAME="NotchShelf"
BUNDLE_ID="com.illiagryniuk.capturearc"
LEGACY_PROCESS_NAME="NotchShelf"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

cd "$ROOT_DIR"
if pgrep -x "$APP_NAME" >/dev/null 2>&1 || pgrep -x "$LEGACY_PROCESS_NAME" >/dev/null 2>&1; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -x "$LEGACY_PROCESS_NAME" >/dev/null 2>&1 || true
  for _ in {1..50}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1 && ! pgrep -x "$LEGACY_PROCESS_NAME" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
  if pgrep -x "$APP_NAME" >/dev/null 2>&1 || pgrep -x "$LEGACY_PROCESS_NAME" >/dev/null 2>&1; then
    echo "$APP_NAME did not stop before rebuild" >&2
    exit 1
  fi
fi

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/Resources/Info.local.plist" "$INFO_PLIST"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
cp "$ROOT_DIR/Resources/PrivacyInfo.xcprivacy" "$APP_RESOURCES/PrivacyInfo.xcprivacy"

# The SwiftPM executable carries its own ad-hoc signature. Re-sign the assembled
# bundle so the executable and generated Info.plist form one valid local app.
# A real Apple Development identity is required for SMAppService launch-at-login
# registration; CI and machines without one retain the portable ad-hoc fallback.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$CODESIGN_IDENTITY" ]]; then
  CODESIGN_IDENTITY="$({
    /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
      | /usr/bin/sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
      | /usr/bin/head -n 1
  } || true)"
fi
if [[ -z "$CODESIGN_IDENTITY" ]]; then
  CODESIGN_IDENTITY="-"
fi

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
  /usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
else
  /usr/bin/codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp=none \
    --sign "$CODESIGN_IDENTITY" \
    "$APP_BUNDLE"
fi
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
  /usr/bin/open "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
