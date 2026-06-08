#!/usr/bin/env bash
# Convert the iOS .caf sound assets into .ogg for libGDX (which cannot read CAF).
# Source of truth is the Xcode app's Sounds/ dir; output lands in the shared assets root.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$REPO_ROOT/PenguinSlide/Sounds"
DST="$REPO_ROOT/android-libgdx/assets/audio"

mkdir -p "$DST"

for caf in "$SRC"/*.caf; do
    name="$(basename "${caf%.caf}")"
    echo "convert $name.caf -> $name.ogg"
    # This ffmpeg build ships only the native (experimental) Vorbis encoder, not libvorbis.
    ffmpeg -y -loglevel error -i "$caf" -c:a vorbis -strict experimental -q:a 6 "$DST/$name.ogg"
done

echo "Audio converted to $DST"
ls -la "$DST"
