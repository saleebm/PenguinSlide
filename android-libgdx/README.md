# Icy Penguin Slide — libGDX rebuild (Kotlin, Android + Desktop)

A faithful libGDX/Kotlin port of the SpriteKit + SwiftUI iOS game in the parent repo. The
penguin slides on ice dodging falling icicles; survive and rack up close-call combos.

- **`core/`** — all gameplay (Kotlin, platform-agnostic): `GameScreen` orchestrator,
  `Penguin`, `IcicleSystem`, `Hud`, `Overlays`, `Tuning`/`PenguinTuning`, `Scoring`,
  persistence. No physics engine — manual integration + circle/AABB overlap, mirroring the
  iOS design (zero scene gravity, contact-detection only).
- **`lwjgl3/`** — desktop launcher (dev/test harness). Keyboard tilt: **A / ← left,
  D / → right**. The desktop build is the whole point of the rebuild — the iOS simulator
  had no gyro, so feel could only be tested on a device; here it runs anywhere.
- **`android/`** — the ship target. Accelerometer tilt, landscape, fullscreen.

Tuning constants, asset names, and the architecture map are kept 1:1 with the iOS source
(see the parent `CLAUDE.md` / the plan in `~/.claude/plans/`).

## Run / build

```sh
./gradlew lwjgl3:run            # desktop (or ./run-desktop.sh)
./gradlew core:test             # unit tests (tuning, scoring, motion, high scores)
./gradlew android:assembleDebug # build the debug APK (or ./run-android.sh)
```

Install/run the APK on a connected device:

```sh
adb install -r android/build/outputs/apk/debug/android-debug.apk
```

> **On-device note:** the accelerometer tilt axis/sign can only be confirmed on real
> hardware. If left/right is inverted, flip `AXIS_SIGN` in
> `core/.../input/TiltProvider.kt` (`AccelerometerTiltProvider`).

## Toolchain

- JDK 17 (the Android Gradle Plugin does not support JDK 23). Every module declares a
  Java 17 **toolchain**, and the `foojay-resolver` plugin in `settings.gradle.kts` lets
  Gradle locate an installed JDK 17 — or download one — on any host. No machine-specific
  JDK path is committed, so the build is portable across macOS/Linux/Windows/CI.
- Android SDK (`platform-tools`, `platforms;android-34`, `build-tools;34.0.0`); path in
  `local.properties` (`sdk.dir`).
- Gradle wrapper 8.12, AGP 8.7.3, Kotlin 2.1.0, libGDX 1.13.1.

## Assets

`assets/` is the shared libGDX asset root (desktop reads it directly; Android bundles it).
Sprites are copied from the iOS `Assets.xcassets`; audio is converted from the iOS `.caf`
files via `scripts/convert-audio.sh` (→ OGG, since libGDX can't read CAF). The HUD font is
Roboto-Bold (Apache-2.0) — `AvenirNext` from iOS isn't redistributable.

## Dev screenshot hook

`-Dps.screenshot=<seconds> -Dps.screenshotFile=<path>` captures the framebuffer after N
seconds and exits. `-Dps.autostart=true`, `-Dps.forceGameOverAt=<s>`, and
`-Dps.openSettings=true` drive states for evidence capture. No effect in normal runs.
