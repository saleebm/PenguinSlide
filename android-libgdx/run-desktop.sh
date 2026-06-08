#!/usr/bin/env bash
# Launch the desktop (LWJGL3) build — the dev/test harness. Keyboard tilt: A/D or arrows.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
exec ./gradlew :lwjgl3:run "$@"
