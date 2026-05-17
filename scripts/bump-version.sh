#!/usr/bin/env bash
# Bump CFBundleShortVersionString (semver) or CFBundleVersion (build) in Info.plist.
# Usage: bump-version.sh patch|minor|major|build

set -euo pipefail

PLIST="$(cd "$(dirname "$0")/.." && pwd)/PenguinSlide/Info.plist"
PB=/usr/libexec/PlistBuddy

if [[ ! -f "$PLIST" ]]; then
  echo "Info.plist not found at $PLIST" >&2
  exit 1
fi

mode="${1:-}"
if [[ -z "$mode" ]]; then
  echo "Usage: $0 patch|minor|major|build" >&2
  exit 1
fi

current_short="$("$PB" -c "Print :CFBundleShortVersionString" "$PLIST")"
current_build="$("$PB" -c "Print :CFBundleVersion" "$PLIST")"

case "$mode" in
  patch|minor|major)
    IFS='.' read -r major minor patch <<<"$current_short"
    major="${major:-0}"; minor="${minor:-0}"; patch="${patch:-0}"
    case "$mode" in
      patch) patch=$((patch + 1));;
      minor) minor=$((minor + 1)); patch=0;;
      major) major=$((major + 1)); minor=0; patch=0;;
    esac
    new_short="${major}.${minor}.${patch}"
    "$PB" -c "Set :CFBundleShortVersionString $new_short" "$PLIST"
    echo "CFBundleShortVersionString: $current_short -> $new_short  (build $current_build unchanged)"
    ;;
  build)
    new_build=$((current_build + 1))
    "$PB" -c "Set :CFBundleVersion $new_build" "$PLIST"
    echo "CFBundleVersion: $current_build -> $new_build  (short $current_short unchanged)"
    ;;
  *)
    echo "Unknown mode: $mode (expected patch|minor|major|build)" >&2
    exit 1
    ;;
esac
