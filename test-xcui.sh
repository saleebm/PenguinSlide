#!/usr/bin/env bash
# Run the PenguinSlideUITests XCUITest target on an iPhone 17 Pro simulator.
# xcodebuild handles the build+install+test cycle itself; no run-sim.sh needed.
#
# Usage:
#   ./test-xcui.sh
#   SIM_DEVICE_ID=<udid> ./test-xcui.sh
#   TEST=PenguinSlideUITests/PenguinSlideUITests/testTitleScreenAppears ./test-xcui.sh
#   REGEN=1 ./test-xcui.sh                # re-run xcodegen first

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$PROJECT_DIR/PenguinSlide.xcodeproj"

if [[ "${REGEN:-0}" == "1" ]]; then
  command -v xcodegen >/dev/null || { echo "xcodegen not installed: brew install xcodegen"; exit 1; }
  (cd "$PROJECT_DIR" && xcodegen generate)
fi

DEVICE_ID="${SIM_DEVICE_ID:-}"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID=$(xcrun simctl list devices booted | grep "iPhone 17 Pro" | grep -oE '[0-9A-F-]{36}' | head -n1 || true)
fi
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID=$(xcrun simctl list devices available | grep -E 'iPhone 17 Pro \(' | grep -oE '[0-9A-F-]{36}' | head -n1 || true)
fi
[[ -n "$DEVICE_ID" ]] || { echo "No iPhone 17 Pro sim available. Create one in Xcode or set SIM_DEVICE_ID."; exit 1; }
echo "→ Simulator: $DEVICE_ID"

xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null 2>&1 || xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true

ONLY=()
[[ -n "${TEST:-}" ]] && ONLY=(-only-testing:"$TEST")

xcodebuild test \
  -project "$PROJECT" \
  -scheme PenguinSlide \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  "${ONLY[@]}"
