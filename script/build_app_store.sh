#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---verify}"
APP_NAME="CaptureArc"
PRODUCT_NAME="NotchShelf"
BUNDLE_ID="com.illiagryniuk.capturearc"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/AppStore"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Resources/Entitlements/AppStore.entitlements"
EFFECTIVE_ENTITLEMENTS="$DIST_DIR/AppStore.effective.entitlements"
PROFILE_PATH="${APP_STORE_PROVISIONING_PROFILE:-}"
SIGNING_KEYCHAIN="${APP_STORE_SIGNING_KEYCHAIN:-}"
BUILD_NUMBER="${APP_STORE_BUILD_NUMBER:-1}"

find_identity() {
  local policy="$1"
  local pattern="$2"
  if [[ -n "$SIGNING_KEYCHAIN" ]]; then
    /usr/bin/security find-identity -v -p "$policy" "$SIGNING_KEYCHAIN" 2>/dev/null \
      | /usr/bin/sed -n "s/.*\"\($pattern[^\"]*\)\".*/\1/p" \
      | /usr/bin/head -n 1
  else
    /usr/bin/security find-identity -v -p "$policy" 2>/dev/null \
      | /usr/bin/sed -n "s/.*\"\($pattern[^\"]*\)\".*/\1/p" \
      | /usr/bin/head -n 1
  fi
}

cd "$ROOT_DIR"
ARM64_TRIPLE="arm64-apple-macosx13.0"
X86_64_TRIPLE="x86_64-apple-macosx13.0"

swift build -c release --product "$PRODUCT_NAME" --triple "$ARM64_TRIPLE"
swift build -c release --product "$PRODUCT_NAME" --triple "$X86_64_TRIPLE"

ARM64_BINARY="$(swift build -c release --show-bin-path --triple "$ARM64_TRIPLE")/$PRODUCT_NAME"
X86_64_BINARY="$(swift build -c release --show-bin-path --triple "$X86_64_TRIPLE")/$PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
/usr/bin/lipo -create \
  "$ARM64_BINARY" \
  "$X86_64_BINARY" \
  -output "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/Resources/Info.appstore.plist" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
cp "$ROOT_DIR/Resources/PrivacyInfo.xcprivacy" "$APP_RESOURCES/PrivacyInfo.xcprivacy"
cp "$ENTITLEMENTS" "$EFFECTIVE_ENTITLEMENTS"

if [[ -n "$PROFILE_PATH" ]]; then
  if [[ ! -f "$PROFILE_PATH" ]]; then
    echo "Provisioning profile not found: $PROFILE_PATH" >&2
    exit 1
  fi
  # Downloaded provisioning profiles commonly carry com.apple.quarantine.
  # macOS App Store processing rejects that attribute anywhere in the payload.
  cp -X "$PROFILE_PATH" "$APP_CONTENTS/embedded.provisionprofile"

  PROFILE_PLIST="$DIST_DIR/AppStore.provisioning-profile.plist"
  /usr/bin/security cms -D -i "$PROFILE_PATH" > "$PROFILE_PLIST"
  APPLICATION_IDENTIFIER="$(
    /usr/libexec/PlistBuddy -c \
      'Print :Entitlements:com.apple.application-identifier' \
      "$PROFILE_PLIST"
  )"
  TEAM_IDENTIFIER="$(
    /usr/libexec/PlistBuddy -c \
      'Print :Entitlements:com.apple.developer.team-identifier' \
      "$PROFILE_PLIST"
  )"

  if [[ "$APPLICATION_IDENTIFIER" != *."$BUNDLE_ID" ]]; then
    echo "Provisioning profile does not match $BUNDLE_ID." >&2
    exit 1
  fi

  /usr/libexec/PlistBuddy -c \
    "Add :com.apple.application-identifier string $APPLICATION_IDENTIFIER" \
    "$EFFECTIVE_ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c \
    "Add :com.apple.developer.team-identifier string $TEAM_IDENTIFIER" \
    "$EFFECTIVE_ENTITLEMENTS"
fi

# Strip any quarantine metadata inherited by copied bundle resources before
# signing and packaging. Extended quarantine attributes are not part of the
# app's contents but are rejected by App Store Connect when embedded in a pkg.
/usr/bin/xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true

APP_SIGNING_IDENTITY="${APP_STORE_APP_SIGNING_IDENTITY:-}"
if [[ -z "$APP_SIGNING_IDENTITY" ]]; then
  APP_SIGNING_IDENTITY="$(find_identity codesigning 'Apple Distribution:' || true)"
fi
if [[ -z "$APP_SIGNING_IDENTITY" ]]; then
  APP_SIGNING_IDENTITY="$(find_identity codesigning '3rd Party Mac Developer Application:' || true)"
fi
if [[ -z "$APP_SIGNING_IDENTITY" ]]; then
  APP_SIGNING_IDENTITY="$(find_identity codesigning 'Apple Development:' || true)"
fi
if [[ -z "$APP_SIGNING_IDENTITY" ]]; then
  echo "No Apple signing identity is available." >&2
  exit 1
fi

codesign_args=(
  --force
  --deep
  --options runtime
  --timestamp=none
  --entitlements "$EFFECTIVE_ENTITLEMENTS"
  --sign "$APP_SIGNING_IDENTITY"
)
if [[ -n "$SIGNING_KEYCHAIN" ]]; then
  codesign_args+=(--keychain "$SIGNING_KEYCHAIN")
fi
/usr/bin/codesign "${codesign_args[@]}" "$APP_BUNDLE"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
/usr/bin/plutil -lint "$INFO_PLIST" "$APP_RESOURCES/PrivacyInfo.xcprivacy" "$EFFECTIVE_ENTITLEMENTS"
/usr/bin/lipo -info "$APP_BINARY"

case "$MODE" in
  --verify|verify)
    /usr/bin/codesign -dvvv --entitlements :- "$APP_BUNDLE"
    ;;
  --run|run)
    /usr/bin/open "$APP_BUNDLE"
    ;;
  --package|package)
    if [[ -z "$PROFILE_PATH" ]]; then
      echo "Set APP_STORE_PROVISIONING_PROFILE before packaging for upload." >&2
      exit 1
    fi
    if [[ "$APP_SIGNING_IDENTITY" != Apple\ Distribution:* \
       && "$APP_SIGNING_IDENTITY" != 3rd\ Party\ Mac\ Developer\ Application:* ]]; then
      echo "A distribution application certificate is required for packaging." >&2
      exit 1
    fi

    INSTALLER_IDENTITY="${APP_STORE_INSTALLER_SIGNING_IDENTITY:-}"
    if [[ -z "$INSTALLER_IDENTITY" ]]; then
      INSTALLER_IDENTITY="$(find_identity basic '3rd Party Mac Developer Installer:' || true)"
    fi
    if [[ -z "$INSTALLER_IDENTITY" ]]; then
      INSTALLER_IDENTITY="$(find_identity basic 'Mac Installer Distribution:' || true)"
    fi
    if [[ -z "$INSTALLER_IDENTITY" ]]; then
      echo "A Mac App Store installer certificate is required for the upload package." >&2
      exit 1
    fi

    productbuild_args=(
      --component "$APP_BUNDLE" /Applications
      --sign "$INSTALLER_IDENTITY"
    )
    if [[ -n "$SIGNING_KEYCHAIN" ]]; then
      productbuild_args+=(--keychain "$SIGNING_KEYCHAIN")
    fi
    /usr/bin/productbuild \
      "${productbuild_args[@]}" \
      "$DIST_DIR/$APP_NAME-1.0.0.pkg"
    ;;
  *)
    echo "usage: $0 [--verify|--run|--package]" >&2
    exit 2
    ;;
esac

echo "App Store candidate: $APP_BUNDLE"
