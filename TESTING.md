# Testing

Automated test scripts for PenguinSlide. All scripts live at the repo root and share the same conventions as `run-sim.sh` / `run-device.sh`: `set -euo pipefail`, environment-variable overrides, sensible defaults.

## Prereqs

- Xcode 26+ with an iPhone 17 Pro simulator available
- `xcodegen` (`brew install xcodegen`) — same as the build scripts
- `agent-device >= 0.14.0` on `PATH` — only needed for `test-smoke.sh` and `test-perf.sh`

Verify agent-device:

```sh
agent-device --version
```

If the version is below 0.14.0, upgrade via your trusted install path. Don't autopilot `npm install -g agent-device@latest`.

## Scripts at a glance

| Script | Layer | Needs agent-device? | Builds the app? |
|---|---|---|---|
| `run-sim.sh` | Build + launch on Simulator | no | yes |
| `run-device.sh` | Build + launch on physical iPhone | no | yes |
| `test-smoke.sh` | agent-device UI smoke loop | yes | optional (`BUILD=1`) |
| `test-perf.sh` | agent-device perf capture | yes | optional (`BUILD=1`) |
| `test-xcui.sh` | XCUITest target via `xcodebuild test` | no | yes (xcodebuild handles it) |

All outputs land in `./test-evidence/` and are gitignored.

## `test-smoke.sh`

Drives the full UI loop with agent-device: launch → title screen → tap start → mid-run screenshot → force game-over via the debug hook → tap to play again → screenshot. Saves four PNGs to `test-evidence/`.

Why it terminates deterministically: it taps the `debugForceGameOver` accessibility node installed by `GameScene` under `#if DEBUG`. Decouples the test from physics timing.

```
./test-smoke.sh                       # uses booted iPhone 17 Pro
SIM_DEVICE_ID=<udid> ./test-smoke.sh  # explicit sim
BUILD=1 ./test-smoke.sh               # rebuild+install first via run-sim.sh
```

| Env | Default | Effect |
|---|---|---|
| `SIM_DEVICE_ID` | first booted iPhone 17 Pro | Target a specific simulator UDID. |
| `BUILD` | `0` | Set to `1` to chain `run-sim.sh` first. |

Outputs:
- `test-evidence/01-title.png`
- `test-evidence/02-playing.png`
- `test-evidence/03-gameover.png`
- `test-evidence/04-restarted.png`

## `test-perf.sh`

Launches the app, starts a round, lets it run ~5 s, dumps `agent-device perf --json` to `test-evidence/perf.json`.

```
./test-perf.sh
SIM_DEVICE_ID=<udid> ./test-perf.sh
BUILD=1 ./test-perf.sh
```

| Env | Default | Effect |
|---|---|---|
| `SIM_DEVICE_ID` | first booted iPhone 17 Pro | Target a specific simulator UDID. |
| `BUILD` | `0` | Set to `1` to chain `run-sim.sh` first. |

Simulator coverage (agent-device 0.14.6):

| Metric | iOS Simulator | Physical device |
|---|---|---|
| `startup` | available | available |
| `fps` | unavailable (xctrace animation-hitches needs a real device) | available |
| `memory` | flaky (simctl spawn ps fails on some runtimes) | available |
| `cpu` | flaky (same reason) | available |

Run against a physical device for full perf coverage.

## `test-xcui.sh` and the XCUITest target

Runs the `PenguinSlideUITests` target via `xcodebuild test`. xcodebuild builds the app, installs to the sim, runs the suite — no `run-sim.sh` chaining needed.

```
./test-xcui.sh
SIM_DEVICE_ID=<udid> ./test-xcui.sh
TEST=PenguinSlideUITests/PenguinSlideUITests/testTitleScreenAppears ./test-xcui.sh
REGEN=1 ./test-xcui.sh                # re-run xcodegen first
```

| Env | Default | Effect |
|---|---|---|
| `SIM_DEVICE_ID` | first booted iPhone 17 Pro (or first available) | Target a specific simulator UDID. |
| `TEST` | run full suite | `-only-testing:<identifier>` filter, e.g. `PenguinSlideUITests/PenguinSlideUITests/testTitleScreenAppears`. |
| `REGEN` | `0` | Set to `1` to re-run `xcodegen generate` (after editing `project.yml`). |

Test methods in `PenguinSlideUITests/PenguinSlideUITests.swift`:

| Test | Assertion |
|---|---|
| `testTitleScreenAppears` | `Tap to start`, `PENGUIN SLIDE`, `Tilt your phone to slide` are visible. |
| `testStartTriggersGameAndShowsGameOver` | After tapping start, tapping the `debugForceGameOver` hook surfaces `Tap to play again` within 2 s. |
| `testRestartReturnsToPlayableState` | After forcing game-over and tapping `Tap to play again`, the overlay clears. |

The target and scheme are wired in `project.yml`. Re-run `xcodegen generate` after editing it.

## Known gotchas

- **Two iPhone 17 Pro UDIDs.** iOS 26.4 and 26.5 each provide an `iPhone 17 Pro` simulator. The test scripts pick the booted one via `xcrun simctl list devices booted | grep "iPhone 17 Pro"` and pass `--udid` so agent-device doesn't match the wrong one by name when both are booted.
- **No gyro on simulator.** The Simulator's keyboard fallback (← / → / A / D) needs `I/O → Input → Send Keyboard Input to Device` (⌘⇧K) enabled. agent-device can't synthesize that reliably, so real gameplay validation requires a physical device.
- **Simulator perf gaps.** See the `test-perf.sh` table above.
- **The `Tap to start` accessibility label drives everything.** Both `test-smoke.sh` and the XCUITests target SpriteKit nodes by their `label="..."`. If those labels change (e.g. localization, copy edits), update the tests at the same time.

## Forcing game-over from tests

`GameScene` installs a hidden 44x44 accessibility node labelled `debugForceGameOver` under `#if DEBUG` (penguinslide-ei0). Tapping it routes through the existing `triggerGameOver()` path regardless of game state, so tests don't depend on physics timing.

- agent-device: `agent-device press 'label="debugForceGameOver"'`
- XCUITest: `app.otherElements["debugForceGameOver"].tap()`

If a test starts failing with "element not found", first check that the build is Debug (the node is excluded from Release). Then verify the accessibility tree with `agent-device snapshot -i` — the node sits at the top-left and surfaces alongside the score and start prompt.

## Output directory

`test-evidence/` holds the screenshots and `perf.json`. It's gitignored — clear it any time with `rm -rf test-evidence/`.
