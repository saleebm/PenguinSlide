#!/usr/bin/env bash
# Build the debug APK and (if a device/emulator is attached) install + launch it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

./gradlew :android:assembleDebug "$@"

APK="android/build/outputs/apk/debug/android-debug.apk"

# Locate adb portably: PATH first, then the standard SDK env vars, then a few common
# install roots as a last resort. Override by exporting ANDROID_HOME / ANDROID_SDK_ROOT
# or putting adb on PATH.
find_adb() {
    if command -v adb >/dev/null 2>&1; then command -v adb; return; fi
    for root in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" \
                "$HOME/Library/Android/sdk" "$HOME/Android/Sdk" \
                /opt/homebrew/share/android-commandlinetools \
                /usr/local/share/android-commandlinetools; do
        [ -n "$root" ] && [ -x "$root/platform-tools/adb" ] && { echo "$root/platform-tools/adb"; return; }
    done
}
ADB="$(find_adb)"

if [ -x "$ADB" ] && [ "$("$ADB" devices | grep -c 'device$')" -gt 0 ]; then
    echo "Installing $APK ..."
    "$ADB" install -r "$APK"
    "$ADB" shell am start -n dev.copt.PenguinSlide/dev.copt.penguinslide.android.AndroidLauncher
elif [ -z "$ADB" ]; then
    echo "Built $APK"
    echo "adb not found — install the Android SDK platform-tools (or put adb on PATH /"
    echo "export ANDROID_HOME), then: adb install -r $APK"
else
    echo "Built $APK"
    echo "No device/emulator attached — connect one and: $ADB install -r $APK"
fi
