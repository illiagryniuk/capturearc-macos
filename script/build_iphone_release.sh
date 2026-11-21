#!/usr/bin/env bash
set -euo pipefail
# Builds/exports locally. This script never uploads or submits to App Store Connect.
MODE="${1:---export}"
case "$MODE" in --archive|--export) ;; *) echo 'usage: build_iphone_release.sh [--archive|--export]' >&2; exit 2 ;; esac
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${CAPTUREARC_IPHONE_OUTPUT:-$ROOT_DIR/dist/iPhone}"
ARCHIVE_PATH="$OUTPUT_DIR/CaptureArcSender.xcarchive"
mkdir -p "$OUTPUT_DIR"
xcodebuild -project "$ROOT_DIR/iPhoneSender/CaptureArcSender.xcodeproj" \
  -scheme CaptureArcSender -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" -derivedDataPath "$OUTPUT_DIR/DerivedData" \
  -allowProvisioningUpdates \
  MARKETING_VERSION="${CAPTUREARC_IPHONE_VERSION:-1.0}" \
  CURRENT_PROJECT_VERSION="${CAPTUREARC_IPHONE_BUILD:-1}" archive
if [[ "$MODE" == --export ]]; then
  xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$ROOT_DIR/release/PhoneMac/iPhone-AppStore-Export.plist" \
    -exportPath "$OUTPUT_DIR/AppStore" -allowProvisioningUpdates
fi
