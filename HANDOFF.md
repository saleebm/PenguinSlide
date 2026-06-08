# HANDOFF — PenguinSlide

_Last updated: 2026-06-08_

You're picking up **PenguinSlide** (tilt-controlled iOS game, SpriteKit + SwiftUI).

- This session's working dir: `/Users/minasaleeb/.superset/worktrees/df2d3227-b2b8-4225-931a-60a7e1287488/review-bv-beads` (branch `review-bv-beads`).
- The live `main` worktree: `/Users/minasaleeb/workspaces/PenguinSlide`.

## Standing rules (from the user's CLAUDE.md — obey exactly)

- **Never do something other than what we committed to.** If the planned approach doesn't work, **STOP and ASK** how to fix it — don't silently switch strategy.
- **"See something, say something":** surface any failure/oddity you spot, even if you didn't cause it. Don't paper over failing tests or close beads that fail.
- **DON'T ASSUME — ASK QUESTIONS** when unsure.

## Where things stand (2026-06-08)

- `main` is at **`5a0e778`** and **PUSHED** to origin (`git@github.com:saleebm/PenguinSlide.git`). It fast-forwarded in the y7f close-call scoring work + the three test/doc beads below.
- **Beads backlog is EMPTY** (`br ready` → "All work complete"). Tracker is the `br` CLI, prefix `penguinslide`, store in `.beads/` (JSONL committed).
- Just closed & verified:
  - **penguinslide-yla** — XCUITest score read; was genuinely failing (lazy `allElementsBoundByIndex` went stale against the live HUD), rewrote to predicate `firstMatch`. **Passes 3/3.**
  - **penguinslide-ga8** — DEBUG `debugLastCloseCall` reflector node (mirrors `debugForceGameOver`) + `test-near-miss.sh`. **Fires 3/3** (sev 0.70/0.65/0.52). Rescope away from the never-shipped `nearMissRadius` was confirmed correct against the tree.
  - **penguinslide-9f8** — single dated "Last reviewed" note in `TESTING.md`.
- **Build gates green: Debug ✓ + Release ✓** (the `#if DEBUG` hooks are excluded from Release).
- **SourceKit "No such module 'UIKit'/'XCTest'" warnings are KNOWN FALSE POSITIVES** (standalone indexer lacks the iOS SDK) — trust `xcodebuild`, not SourceKit.

## ⚠️ Dangling item — resolve FIRST (ask the user)

`PenguinSlide/Info.plist` in the **main worktree** (`/Users/minasaleeb/workspaces/PenguinSlide`) has an **uncommitted, un-pushed** display-name rebrand:

```
CFBundleDisplayName  "Penguin Slide"  →  "Icy Penguin Slide"
```

Nobody committed it. Decide with the user: commit it (where — needs a bead?), revert it, or leave it. **Don't assume.**

## Build / test (scripts at repo root — all target-mode, not scheme-mode; Xcode 26 quirk)

- `./run-sim.sh` / `./run-device.sh` — device needs a physical iPhone; **the simulator has no gyro**.
- `./test-xcui.sh` — `TEST=PenguinSlideUITests/PenguinSlideUITests/<name> ./test-xcui.sh` for a single test.
- `./test-smoke.sh` / `./test-near-miss.sh` — agent-device UI loops; need a booted sim. `test-near-miss.sh` injects oscillating tilt so the penguin survives a close landing, then asserts the close-call scoring hook fired.
- `project.yml` is the source of truth (xcodegen) — run `xcodegen generate` or `REGEN=1 ./run-sim.sh` after editing it. `Info.plist` is checked-in & authoritative (`GENERATE_INFOPLIST_FILE = NO`).

## First moves

1. Read `CLAUDE.md`.
2. Run `br ready` and `git -C /Users/minasaleeb/workspaces/PenguinSlide status`.
3. **Confirm the `Info.plist` decision with the user before doing anything else.**
