#!/usr/bin/env bash
# Build the debug APK and (if a device/emulator is attached) install + launch it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

./gradlew :android:assembleDebug "$@"

APK="android/build/outputs/apk/debug/android-debug.apk"
ADB="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}/platform-tools/adb"

if [ -x "$ADB" ] && [ "$("$ADB" devices | grep -c 'device$')" -gt 0 ]; then
    echo "Installing $APK ..."
    "$ADB" install -r "$APK"
    "$ADB" shell am start -n dev.copt.PenguinSlide/dev.copt.penguinslide.android.AndroidLauncher
else
    echo "Built $APK"
    echo "No device/emulator attached — connect one and: $ADB install -r $APK"
fi
