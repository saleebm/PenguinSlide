#!/usr/bin/env bash
# Agent-device perf capture for PenguinSlide.
# Launches the app, starts a round, lets it run ~5s, dumps perf JSON.
#
# Limitations on iOS Simulator (confirmed against agent-device 0.14.6):
#   - startup: works (open-command-roundtrip)
#   - fps:     UNAVAILABLE (xctrace animation-hitches requires a physical device)
#   - memory:  flaky (simctl spawn ps may fail on some sim runtimes)
#   - cpu:     flaky (same reason as memory)
# Run against a physical device for full coverage.
#
# Usage:
#   ./test-perf.sh
#   SIM_DEVICE_ID=<udid> ./test-perf.sh
#   BUILD=1 ./test-perf.sh

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ID=dev.copt.PenguinSlide
SESSION=penguinslide-perf
EVIDENCE="$PROJECT_DIR/test-evidence"
mkdir -p "$EVIDENCE"

if [[ "${BUILD:-0}" == "1" ]]; then
  "$PROJECT_DIR/run-sim.sh"
fi

DEVICE_ID="${SIM_DEVICE_ID:-}"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID=$(xcrun simctl list devices booted | grep "iPhone 17 Pro" | grep -oE '[0-9A-F-]{36}' | head -n1 || true)
fi
[[ -n "$DEVICE_ID" ]] || { echo "No booted iPhone 17 Pro sim. Run ./run-sim.sh first or set SIM_DEVICE_ID."; exit 1; }
echo "→ Simulator: $DEVICE_ID"

ad() { agent-device "$@" --platform ios --udid "$DEVICE_ID" --session "$SESSION"; }

ad open "$BUNDLE_ID" --relaunch
ad press 'label="Tap to start"'
ad wait 5000
ad perf --json > "$EVIDENCE/perf.json"
ad close

echo "→ Perf JSON: $EVIDENCE/perf.json"
