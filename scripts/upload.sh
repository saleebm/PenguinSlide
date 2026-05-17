#!/usr/bin/env bash
# Upload build/export/PenguinSlide.ipa to App Store Connect via altool.
#
# Required env vars:
#   ASC_APPLE_ID      — your Apple ID email (the one signed into Xcode)
#   ASC_APP_PASSWORD  — an APP-SPECIFIC password (not your Apple ID password).
#                       Generate at https://account.apple.com → Sign-In and
#                       Security → App-Specific Passwords → Generate.
#
# Optional:
#   ASC_TEAM_ID       — defaults to L7U86T3YRV
#
# Fallback if altool misbehaves: open Transporter.app (Mac App Store) and
# drag build/export/PenguinSlide.ipa into it. Transporter uses Xcode's
# signed-in account directly.

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IPA="$PROJECT_DIR/build/export/PenguinSlide.ipa"

if [[ ! -f "$IPA" ]]; then
  echo "IPA not found at $IPA. Run scripts/archive.sh first." >&2
  exit 1
fi

if [[ -z "${ASC_APPLE_ID:-}" ]] || [[ -z "${ASC_APP_PASSWORD:-}" ]]; then
  echo "Missing credentials." >&2
  echo "  export ASC_APPLE_ID='you@example.com'" >&2
  echo "  export ASC_APP_PASSWORD='xxxx-xxxx-xxxx-xxxx'   # app-specific password" >&2
  exit 1
fi

TEAM_ID="${ASC_TEAM_ID:-L7U86T3YRV}"

echo "Validating $IPA..."
xcrun altool --validate-app \
  --type ios \
  --file "$IPA" \
  --username "$ASC_APPLE_ID" \
  --password "@env:ASC_APP_PASSWORD" \
  --asc-provider "$TEAM_ID"

echo
echo "Uploading $IPA..."
xcrun altool --upload-app \
  --type ios \
  --file "$IPA" \
  --username "$ASC_APPLE_ID" \
  --password "@env:ASC_APP_PASSWORD" \
  --asc-provider "$TEAM_ID"

echo
echo "Uploaded. Apple processes the build in ~5-30 min."
echo "Watch:  https://appstoreconnect.apple.com/apps"
echo "Then:   ASC → app → TestFlight → wait for 'Ready to Submit'"
echo "Then:   ASC → app → App Store → select build → Submit for Review"
