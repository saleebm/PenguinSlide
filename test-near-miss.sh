#!/usr/bin/env bash
# Agent-device smoke assertion for the y7f close-call SCORING hook
# (penguinslide-ga8).
#
# What it proves: a *survived* icicle landing whose
#   severity = max(0, 1 - dx/Tuning.Feel.shakeRadius)
# clears Tuning.Score.closeCallSeverity fires IcicleSystem.onCloseCall ->
# GameScene.registerCloseCall, which adds a score bonus and drives the HUD.
# That feedback-only path is easy to silently regress.
#
# How: a DEBUG-only SKLabelNode (`closeCall:none` -> `closeCall:fired sev=.. bonus=..`)
# reflects the last close-call into the accessibility tree. We drive a short
# play session, weaving the penguin with injected tilt so it survives close
# landings instead of just standing still and dying, then poll the tree until
# the label flips to `fired` with a positive bonus.
#
# NOTE there is NO nearMissRadius and shake is NOT suppressed by any near-miss
# zone — this asserts the scoring hook fired, never shake amplitude.
#
# Prereqs:
#   - agent-device >= 0.14.0 on PATH
#   - A DEBUG build installed on the booted sim (use BUILD=1 to chain run-sim.sh).
#     The reflector node and the tilt injector are both #if DEBUG only.
#
# Usage:
#   ./test-near-miss.sh                       # uses booted iPhone 17 Pro
#   SIM_DEVICE_ID=<udid> ./test-near-miss.sh  # explicit sim
#   BUILD=1 ./test-near-miss.sh               # rebuild+install first via run-sim.sh
#   TIMEOUT=20 ./test-near-miss.sh            # seconds to wait for a close-call

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ID=dev.copt.PenguinSlide
SESSION=penguinslide-nearmiss
TIMEOUT="${TIMEOUT:-20}"

if [[ "${BUILD:-0}" == "1" ]]; then
  "$PROJECT_DIR/run-sim.sh"
fi

# Threshold is read from Tuning, never hardcoded (acceptance requirement). The
# source-side gate in IcicleSystem already uses this same constant, so a `fired`
# label means severity >= this by construction; we surface it for the log.
CLOSE_CALL_SEVERITY=$(grep -E 'closeCallSeverity' "$PROJECT_DIR/PenguinSlide/Tuning.swift" \
  | grep -oE '[0-9]+\.[0-9]+' | head -n1)
[[ -n "$CLOSE_CALL_SEVERITY" ]] || { echo "Could not read Tuning.Score.closeCallSeverity"; exit 1; }
echo "→ Tuning.Score.closeCallSeverity = $CLOSE_CALL_SEVERITY"

# Pick the booted iPhone 17 Pro by default (same logic as test-smoke.sh).
DEVICE_ID="${SIM_DEVICE_ID:-}"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID=$(xcrun simctl list devices booted | grep "iPhone 17 Pro" | grep -oE '[0-9A-F-]{36}' | head -n1 || true)
fi
[[ -n "$DEVICE_ID" ]] || { echo "No booted iPhone 17 Pro sim. Run ./run-sim.sh first or set SIM_DEVICE_ID."; exit 1; }
echo "→ Simulator: $DEVICE_ID"

ad() { agent-device "$@" --platform ios --udid "$DEVICE_ID" --session "$SESSION"; }

ad open "$BUNDLE_ID" --relaunch
ad press 'label="Tap to start"'

# Weave the penguin with oscillating tilt while polling the reflector. Samples
# older than ~500 ms are dropped by GameScene, so we re-send each iteration.
# Standing still just dies in three hits; weaving survives close landings.
echo "→ Driving play for up to ${TIMEOUT}s, watching for closeCall:fired ..."
deadline=$(( SECONDS + TIMEOUT ))
sign="0.6"
fired=""
while (( SECONDS < deadline )); do
  "$PROJECT_DIR/scripts/inject-tilt.sh" "$sign" >/dev/null 2>&1 || true
  [[ "$sign" == "0.6" ]] && sign="-0.6" || sign="0.6"
  tree=$(ad snapshot -c 2>/dev/null || true)
  line=$(printf '%s\n' "$tree" | grep -oE 'closeCall:fired[^"]*' | head -n1 || true)
  if [[ -n "$line" ]]; then fired="$line"; break; fi
  ad wait 400 >/dev/null 2>&1 || true
done
"$PROJECT_DIR/scripts/inject-tilt.sh" 0 >/dev/null 2>&1 || true

if [[ -z "$fired" ]]; then
  echo "✗ No close-call fired within ${TIMEOUT}s. The reflector stayed closeCall:none."
  echo "  Either the y7f hook regressed, or this run produced no survived landing"
  echo "  with severity >= ${CLOSE_CALL_SEVERITY}. Re-run or raise TIMEOUT."
  ad close >/dev/null 2>&1 || true
  exit 1
fi

echo "→ Reflector: $fired"
bonus=$(printf '%s' "$fired" | grep -oE 'bonus=[0-9]+' | grep -oE '[0-9]+' | head -n1 || true)
if [[ -z "$bonus" || "$bonus" -le 0 ]]; then
  echo "✗ Hook fired but no positive score bonus was produced (bonus='${bonus:-}')."
  ad close >/dev/null 2>&1 || true
  exit 1
fi

echo "✓ Close-call hook fired and produced a score bonus of $bonus."
ad close >/dev/null 2>&1 || true
