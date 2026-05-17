#!/usr/bin/env bash
# Capture App Store-mandatory screenshots across required simulator sizes.
#
# Workflow: for each device, the script boots the sim, builds+installs+launches
# the app, then pauses. Drive the game to the screen you want, press <enter>,
# and the script saves a PNG to build/screenshots/<device-name>/<timestamp>.png.
# Repeat for additional captures on the same device, or type 'n' to move on.
#
# Required sizes for landscape iOS games (as of 2026-05):
#   - 6.9" iPhone   (iPhone 16 Pro Max)        — 1320 x 2868 portrait / 2868 x 1320 landscape
#   - 6.5" iPhone   (iPhone 11 Pro Max / 15+)  — 1242 x 2688 / 2688 x 1242   (legacy slot)
#   - 13"  iPad     (iPad Pro 13-inch M4)      — 2064 x 2752 / 2752 x 2064
#   - 12.9" iPad    (iPad Pro 12.9" 6th gen)   — 2048 x 2732 / 2732 x 2048   (legacy slot)

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$PROJECT_DIR/build/screenshots"
mkdir -p "$OUT_DIR"

DEVICES=(
  "iPhone 16 Pro Max"
  "iPhone 15 Plus"
  "iPad Pro 13-inch (M4)"
  "iPad Pro (12.9-inch) (6th generation)"
)

resolve_udid() {
  xcrun simctl list devices available \
    | grep -F "$1 (" \
    | grep -oE '[0-9A-F-]{36}' \
    | head -n1
}

for device in "${DEVICES[@]}"; do
  echo
  echo "═══ $device ═══"
  udid="$(resolve_udid "$device" || true)"
  if [[ -z "$udid" ]]; then
    echo "  skip — simulator not installed (Xcode → Settings → Platforms to add)"
    continue
  fi

  slug="$(echo "$device" | tr ' ()/' '----')"
  device_dir="$OUT_DIR/$slug"
  mkdir -p "$device_dir"

  SIM_DEVICE_ID="$udid" "$PROJECT_DIR/run-sim.sh" >/dev/null
  echo "  app launched on $device. Drive to the screen you want."

  while true; do
    read -r -p "  [enter] capture, [n] next device, [q] quit: " action
    case "$action" in
      "")
        ts="$(date +%Y%m%d-%H%M%S)"
        out="$device_dir/$ts.png"
        xcrun simctl io "$udid" screenshot "$out"
        echo "  saved $out"
        ;;
      n|N)
        break
        ;;
      q|Q)
        echo "  done."
        exit 0
        ;;
      *)
        echo "  unknown — enter|n|q"
        ;;
    esac
  done
done

echo
echo "All captures in $OUT_DIR"
