#!/usr/bin/env bash
# Agent-device smoke loop for PenguinSlide.
# Drives title -> start -> playing -> game-over -> restart and saves screenshots
# to ./test-evidence/. No tilt input on simulator, so the penguin can't dodge;
# we use that to deterministically reach the game-over overlay.
#
# Prereqs:
#   - agent-device >= 0.14.0 on PATH
#   - App already built+installed via ./run-sim.sh (use BUILD=1 to chain it)
#
# Usage:
#   ./test-smoke.sh                       # uses booted iPhone 17 Pro
#   SIM_DEVICE_ID=<udid> ./test-smoke.sh  # explicit sim
#   BUILD=1 ./test-smoke.sh               # rebuild+install first via run-sim.sh

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ID=dev.copt.PenguinSlide
SESSION=penguinslide-smoke
EVIDENCE="$PROJECT_DIR/test-evidence"
mkdir -p "$EVIDENCE"

if [[ "${BUILD:-0}" == "1" ]]; then
  "$PROJECT_DIR/run-sim.sh"
fi

# Pick the booted iPhone 17 Pro by default. Two sim UDIDs may exist (iOS 26.4
# and 26.5) — we use --udid below to avoid agent-device picking the wrong one
# by name when both are booted.
DEVICE_ID="${SIM_DEVICE_ID:-}"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID=$(xcrun simctl list devices booted | grep "iPhone 17 Pro" | grep -oE '[0-9A-F-]{36}' | head -n1 || true)
fi
[[ -n "$DEVICE_ID" ]] || { echo "No booted iPhone 17 Pro sim. Run ./run-sim.sh first or set SIM_DEVICE_ID."; exit 1; }
echo "→ Simulator: $DEVICE_ID"

ad() { agent-device "$@" --platform ios --udid "$DEVICE_ID" --session "$SESSION"; }

ad open "$BUNDLE_ID" --relaunch
ad screenshot "$EVIDENCE/01-title.png"

ad press 'label="Tap to start"'
ad wait 1500
ad screenshot "$EVIDENCE/02-playing.png"

# Force game-over via the #if DEBUG accessibility hook (penguinslide-ei0).
# Replaces the previous "wait up to 30 s for the penguin to die without
# tilt" — that path was physics-dependent and slow.
ad press 'label="debugForceGameOver"'
ad wait 'label="Tap to play again"' 2000
ad screenshot "$EVIDENCE/03-gameover.png"

ad press 'label="Tap to play again"'
ad wait 800
ad screenshot "$EVIDENCE/04-restarted.png"

ad close
echo "→ Screenshots: $EVIDENCE/{01-title,02-playing,03-gameover,04-restarted}.png"
