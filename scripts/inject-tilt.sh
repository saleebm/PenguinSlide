#!/usr/bin/env bash
# Inject a tilt value into a DEBUG simulator build of PenguinSlide.
#
# Usage:  ./scripts/inject-tilt.sh  0.7    # slide right
#         ./scripts/inject-tilt.sh -0.7    # slide left
#         ./scripts/inject-tilt.sh  0      # glide to stop
#
# The app's MotionInjector listens on 127.0.0.1:7654 only in DEBUG +
# simulator builds. Range is -1...1 (gravity.y units). Samples older
# than ~500 ms are ignored by GameScene, so re-send periodically if you
# want to hold a tilt.

set -euo pipefail
VALUE="${1:-0}"
PORT="${PORT:-7654}"
printf '{"gravity_y": %s}\n' "$VALUE" | nc -w1 127.0.0.1 "$PORT"
