# HANDOFF — PenguinSlide

_Last updated: 2026-06-19_

You're picking up **PenguinSlide** (tilt-controlled iOS game, SpriteKit + SwiftUI).

- The live `main` worktree: `/Users/minasaleeb/workspaces/PenguinSlide`.
- Snow-monster review worktree (temporary): `/Users/minasaleeb/workspaces/penguin-snow-review` (branch `feat/snow-monster`). Safe to `git worktree remove` once the merge is confirmed.

## Standing rules (from the user's CLAUDE.md — obey exactly)

- **Never do something other than what we committed to.** If the planned approach doesn't work, **STOP and ASK** how to fix it — don't silently switch strategy.
- **"See something, say something":** surface any failure/oddity you spot, even if you didn't cause it. Don't paper over failing tests or close beads that fail.
- **DON'T ASSUME — ASK QUESTIONS** when unsure.

## Where things stand (2026-06-19) — `feat/snow-monster` review

- Reviewed the **Snow Monster pseudo-3D boss encounter** branch (`feat/snow-monster`, ~12.8k insertions, 113 files: new `Encounter/` subsystem, shared `TiltSlideMotion`, new `PenguinSlideTests` unit target, 18 unit-test files + 1 XCUITest file, new art/audio).
- **Architecture review: strong.** Four parallel reviews confirmed the `CLAUDE.md` invariants hold — single `transition(to:)` phase mutator resets the `dt==0` sentinel on every transition; death-frame ordering mirrors the `didBegin` contract; shared `Penguin` HP pool + i-frames (hits route through `tryTakeHit`); manual snowball collision (no `SKPhysicsBody`); `[weak self]` throughout; no retain cycles.
- **8/204 unit tests were failing → now fixed (commit `36e01f9`).** Diagnosed per-failure (test-stale vs code-bug):
  - **CODE (1 change):** removed a stray `puff.setScale(0.7)` in `EncounterFX.playHitBurst` — it corrupted the documented base footprint (`.size` read 67.2 not 96) and fought the impl's own "swells to ~1.25×" docstring. ⚠️ This is a small **visual** change (impact puff now starts at base scale, ~43% larger at onset) — **validate on a physical device** before shipping (sim has no gyro / this is feel).
  - **TEST (re-baselines):** 3 SnowballCollision tests had literals/reconstruction math that drifted from the now-derived, grown `lateralHitRadius` (~79.8) and ignored `zAccel`; 1 EncounterFX test discarded the weakly-held `parent`. Re-baselined to current tuning, preserving each test's asserted intent (no tautologies).
- **Suite is green** (`Executed 204 tests, with 0 failures`) and `feat/snow-monster` is **merged into `main`**.

## ⚠️ Hygiene matters to take care of (deferred — NOT done in the merge, per the user's "leave hygiene alone" call)

These were surfaced during review and intentionally left for a follow-up pass. None block runtime; all are repo-cleanliness / convention debt.

1. **[HIGH] `.beads/.br_recovery/*.bak` committed** — a 630 KB binary SQLite db backup + a wal backup were force-added (commit `733dd1a`). `.beads/.gitignore` already ignores `*.db`/`*.db-wal`, so these per-machine recovery backups don't belong in VCS. **Fix:** `git rm --cached .beads/.br_recovery/*.bak` and add `.br_recovery/` to `.beads/.gitignore`.
2. **[MEDIUM] `assets-staging/` (~23 raw .mp3/.png, ~600 KB)** — source masters staged before import into `Assets.xcassets`/`PenguinSlide/Sounds/`; unreferenced by `project.yml` or any build path. **Decide:** keep deliberately (add `assets-staging/README.md` stating it's source-of-truth masters) **or** gitignore it. Don't leave ambiguous.
3. **[MEDIUM] `Tuning.Encounter` knobs scattered across encounter files** — defined in `extension` blocks in `Snowball.swift`, `EncounterWorld.swift`, `PapiAvatar.swift` (each notes "fold into Tuning.swift whenever convenient") instead of the `Tuning.swift` difficulty hub. Consolidate per the documented "Tuning.swift is the difficulty hub" convention.
4. **[LOW] `test-unit.sh` uses `-scheme`** while every other script uses target-mode (`-target`+`-sdk`) per the Xcode-26 quirk in `CLAUDE.md`. It ran green, but add a one-line comment explaining why `xcodebuild test` runs use scheme mode.
5. **[LOW] Terse branch history** — `feat/snow-monster` commits are `wip`/`config`/`papi pengu`/`encounter`. Merged with `--no-ff` so the merge commit documents intent; if you prefer a clean linear history, consider squashing before any future similar merge.
6. **[LOW] Version bump** — `Info.plist` `CFBundleShortVersionString` 1.3.0 → 1.4.0 but `CFBundleVersion` stayed `1`. Confirm the build-number handling (`scripts/bump-version.sh build`) before a release archive.
7. **[NIT] Magic numbers** — `SnowMonsterEncounterSystem` hard-codes `zPosition = 69` (dodge-exit node) in the reserved HUD/FX z-band, and `EncounterWorld` uses `zDeep = zMonster * 6` inline. Promote to named constants in the documented z-stack.

## Resolved since the last handoff
- The dangling `Info.plist` display-name rebrand ("Penguin Slide" → "Icy Penguin Slide") is committed on `main` (`7427e23`, plus `f752358` fix hardcoded paths). No longer outstanding.

## Build / test (scripts at repo root — target-mode except `test-unit.sh`; Xcode 26 quirk)

- `./run-sim.sh` / `./run-device.sh` — device needs a physical iPhone; **the simulator has no gyro** (real gameplay/feel validation is device-only).
- `./test-unit.sh` — `PenguinSlideTests` unit bundle on an iPhone 17 Pro sim (`TEST=…/<method> ./test-unit.sh` for one). `./test-xcui.sh` — XCUITest. `./test-smoke.sh` — agent-device UI loop.
- `project.yml` is the source of truth (xcodegen) — run `xcodegen generate` or `REGEN=1 ./test-unit.sh` after editing it. `Info.plist` is checked-in & authoritative (`GENERATE_INFOPLIST_FILE = NO`).
- **SourceKit "No such module 'UIKit'/'XCTest'" warnings are KNOWN FALSE POSITIVES** (standalone indexer lacks the iOS SDK) — trust `xcodebuild`, not SourceKit.

## First moves
1. Read `CLAUDE.md`.
2. `git -C /Users/minasaleeb/workspaces/PenguinSlide status` and `br ready`.
3. Work the hygiene list above (ask before the keep-vs-ignore calls in items 1–2).
