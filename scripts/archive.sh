#!/usr/bin/env bash
# Archive PenguinSlide for the App Store and export a signed .ipa.
#
# Output:
#   build/PenguinSlide.xcarchive  — the archive (also visible in Xcode → Organizer)
#   build/export/PenguinSlide.ipa — the signed binary ready for upload
#
# Next step: scripts/upload.sh

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

ARCHIVE_PATH="$PROJECT_DIR/build/PenguinSlide.xcarchive"
EXPORT_PATH="$PROJECT_DIR/build/export"
EXPORT_OPTIONS="$PROJECT_DIR/scripts/ExportOptions.plist"
PLIST="$PROJECT_DIR/PenguinSlide/Info.plist"
PB=/usr/libexec/PlistBuddy

SHORT_VER="$("$PB" -c "Print :CFBundleShortVersionString" "$PLIST")"
BUILD_VER="$("$PB" -c "Print :CFBundleVersion" "$PLIST")"
echo "Archiving PenguinSlide $SHORT_VER (build $BUILD_VER)"

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
mkdir -p "$PROJECT_DIR/build"

xcodebuild \
  -project PenguinSlide.xcodeproj \
  -scheme PenguinSlide \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

echo
echo "Archive: $ARCHIVE_PATH"
echo "IPA:     $EXPORT_PATH/PenguinSlide.ipa"
echo
echo "Next: scripts/upload.sh   (or drag the .ipa into Transporter.app)"
