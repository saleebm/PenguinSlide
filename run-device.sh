#!/usr/bin/env bash
# Build, sign, install, and launch PenguinSlide on a physical iPhone via devicectl.
#
# Why target-mode build: same Xcode 26 quirk that affected the simulator path —
# scheme-based destination resolution can silently fail when platform support
# is in flux. Target-mode + -sdk iphoneos is reliable.
#
# Usage:
#   ./run-device.sh                       # auto-pick first connected device
#   DEVICE=Meowinas ./run-device.sh       # by name
#   DEVICE=9F616045-... ./run-device.sh   # by devicectl identifier
#   REGEN=1 ./run-device.sh               # re-run xcodegen first

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$PROJECT_DIR/PenguinSlide.xcodeproj"
TARGET=PenguinSlide
BUNDLE_ID=dev.copt.PenguinSlide
BUILD_DIR=/tmp/PenguinSlideBuild

if [[ "${REGEN:-0}" == "1" ]]; then
  command -v xcodegen >/dev/null || { echo "xcodegen not installed: brew install xcodegen"; exit 1; }
  (cd "$PROJECT_DIR" && xcodegen generate)
fi

# Pick device: $DEVICE → first connected from `devicectl list devices`.
DEVICE_REF="${DEVICE:-}"
if [[ -z "$DEVICE_REF" ]]; then
  DEVICE_REF=$(xcrun devicectl list devices 2>/dev/null | awk '/connected/{print $1; exit}')
fi
[[ -n "$DEVICE_REF" ]] || { echo "No connected iOS device. Plug in your iPhone and unlock it."; exit 1; }
echo "→ Device: $DEVICE_REF"

# Build + sign. -allowProvisioningUpdates lets Xcode fetch/regen the
# provisioning profile from the team set in project.yml.
xcodebuild \
  -project "$PROJECT" \
  -target "$TARGET" \
  -sdk iphoneos \
  -configuration Debug \
  -allowProvisioningUpdates \
  ARCHS=arm64 \
  SYMROOT="$BUILD_DIR" \
  build | tail -1

APP="$BUILD_DIR/Debug-iphoneos/$TARGET.app"
[[ -d "$APP" ]] || { echo "Build did not produce $APP"; exit 1; }

xcrun devicectl device install app --device "$DEVICE_REF" "$APP"
xcrun devicectl device process launch --device "$DEVICE_REF" "$BUNDLE_ID"

cat <<EOF

Launched on $DEVICE_REF.
First-run only: on the iPhone, open
  Settings → General → VPN & Device Management → trust your developer cert.
EOF
