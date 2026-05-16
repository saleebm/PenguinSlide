# The screen-lock bug: resetting the frame-time anchor on resume

The bug was reported as "score jumped by hundreds while my phone was locked." Reproduce path: start a game, lock the phone for thirty seconds, unlock, watch the score and the penguin go visibly sideways for one frame.

It's the kind of bug that happens once, gets shrugged off, then someone happens to lock their screen during playtesting and the whole UI lurches. We needed to fix it before it shipped. The fix is one variable, one assignment, and a `NotificationCenter` observer. Two lines of logic, twenty lines of plumbing. The lesson is much bigger than the code.

## What was going wrong

`GameScene.update(_:)` is SpriteKit's per-frame tick. It receives the current frame's timestamp and computes `dt` against the previous frame:

```swift
// PenguinSlide/GameScene.swift:301
override func update(_ currentTime: TimeInterval) {
    let dt: TimeInterval = lastUpdateTime == 0 ? 0 : (currentTime - lastUpdateTime)
    lastUpdateTime = currentTime
    // ...
    elapsed += dt
    penguin.update(dt: dt, tilt: currentTilt())
    icicles.update(dt: dt, elapsed: elapsed)
    score = Int(elapsed * 10)
}
```

That `lastUpdateTime == 0 ? 0 : ...` is a sentinel for "first frame, no previous to compare against." It works at game start. It works on restart. It does *not* work when the OS suspends the app.

When you lock your phone, iOS stops calling `update(_:)`. The game pauses, in the sense that nothing renders. But `lastUpdateTime` retains its last value — say, `T = 1234.567`. Thirty seconds later, you unlock. The next `update(_:)` arrives with `currentTime = 1264.567`. The sentinel doesn't fire because `lastUpdateTime != 0`. So:

```
dt = 1264.567 - 1234.567 = 30.0
```

Thirty *seconds* of `dt` in a single frame. Everything downstream integrates that thirty-second step in one go:

- `elapsed += 30.0` — the round clock jumps ahead by 30 seconds
- `score = Int(elapsed * 10)` — score balloons by 300
- `penguin.update(dt: 30.0, ...)` — the penguin's velocity decays, lean spring oscillates 30 seconds in one step, alpha flicker phase scrambles
- `icicles.update(dt: 30.0, ...)` — every falling icicle integrates `v += g * 30.0`, teleporting them at terminal velocity through the floor; spawn cadence advances; the difficulty ramp jumps

The frame after that, everything renders correctly again. But the round is now 30 seconds older than the player thinks, with score and difficulty to match. Sometimes the penguin is dead. Always the score is wrong.

## What we changed

The fix is to treat the *resume event* as a frame-time discontinuity — same as game start, same as restart — and reset the sentinel:

```swift
// PenguinSlide/GameScene.swift:114
private func observeAppLifecycle() {
    let nc = NotificationCenter.default
    nc.addObserver(self, selector: #selector(handleWillResignActive),
                   name: UIApplication.willResignActiveNotification, object: nil)
    nc.addObserver(self, selector: #selector(handleDidBecomeActive),
                   name: UIApplication.didBecomeActiveNotification, object: nil)
}

@objc private func handleWillResignActive() {
    view?.isPaused = true
    // SKAudioNode runs on the audio engine, not the scene clock, so it
    // keeps playing through view.isPaused. Explicit pause here.
    bgMusic?.run(SKAction.pause())
}

@objc private func handleDidBecomeActive() {
    // The dt-skip sentinel in update(_:) treats lastUpdateTime == 0 as
    // "first frame, dt = 0". Without this reset, the first post-resume
    // update sees a multi-second dt (the lock duration), `elapsed`
    // jumps, score balloons, and Penguin/IcicleSystem integrate one
    // giant step. Same sentinel pattern as restart()/start (penguinslide-jj2).
    lastUpdateTime = 0
    view?.isPaused = false
    bgMusic?.run(SKAction.play())
}
```

The first line of `handleDidBecomeActive` is the real fix: `lastUpdateTime = 0`. The next `update(_:)` hits the sentinel branch, computes `dt = 0`, and the round resumes exactly where it left off. Score, elapsed time, falling icicles — all preserved as of the moment the user locked their phone.

## The pattern is symmetric

That sentinel reset isn't just for resume. The same line shows up at every frame-time discontinuity in the file:

- Game start, the first touch that dismisses the start prompt:
  ```swift
  // PenguinSlide/GameScene.swift:267 (excerpt)
  if !isStarted {
      isStarted = true
      lastUpdateTime = 0
      hud.dismissStartPrompt()
      return
  }
  ```

- Restart after game-over:
  ```swift
  // PenguinSlide/GameScene.swift:382
  lastUpdateTime = 0
  ```

- Resume from a settings sheet (which pauses the scene while open):
  ```swift
  // PenguinSlide/GameScene.swift:150
  func resumeFromSettings() {
      lastUpdateTime = 0
      view?.isPaused = false
      bgMusic?.run(SKAction.play())
  }
  ```

Five reset sites. Same one-liner. Each marks a point where "wall-clock time advanced but game time did not." Forget any one of them and you have a one-frame teleport bug.

## The update-loop contract

The bigger lesson is in the `update(_:)` docstring. Game clocks are fragile, so the file documents the contract explicitly:

```swift
// PenguinSlide/GameScene.swift:288 (excerpt)
/// Per-frame tick.
///
/// IMPORTANT ordering contract: **all per-frame physics work — penguin
/// movement, spawning, gravity integration, landing checks — must stay
/// BEHIND the `isStarted/!isGameOver` guard.** `didBegin(_:)` is invoked
/// from inside SpriteKit's physics step, which runs AFTER `update(_:)`
/// in the same frame. So on the death frame, this method has already
/// executed; we rely on the NEXT frame's guard plus `physicsWorld.speed
/// = 0` (set in `triggerGameOver`) to halt motion. If you move any of
/// the integration calls outside the guard you'll get one frame of
/// post-death physics — visible as a teleporting shard.
```

The combined rule: **`dt` should always be either zero (sentinel frame) or a small fraction of a second (normal frame). Any code path that could deliver a large `dt` is a bug.** Suspension is one such path. A misplaced refactor that moves `lastUpdateTime = currentTime` outside the active guard is another (the docstring calls this out for a reason).

## What it costs

- **You have to know about `willResignActive`/`didBecomeActive`.** Newer scene-phase APIs are tempting, but `NotificationCenter` is what we already use, and it fires reliably in SpriteKit contexts. Don't fix what isn't broken.
- **Observer lifecycle is your problem.** `willMove(from:)` calls `NotificationCenter.default.removeObserver(self)` because forgetting that is a classic iOS leak.
- **`SKAudioNode` doesn't pause with the view.** Bonus footgun discovered by the same bug: pausing `view?.isPaused = true` doesn't stop audio nodes (they run on the audio engine), so background music kept playing through screen lock. The same handler pauses `bgMusic` explicitly. See [post #3](03-arcade-audio-layering.md).
- **Sentinel-based dt-skip is a convention, not a type.** The compiler doesn't enforce that `lastUpdateTime == 0` means "first frame." Anyone touching `update(_:)` needs to understand the sentinel. We pay the cost in a docstring.
- **You can't test the bug without locking the phone.** XCUITest can drive most of the game, but lock-screen simulation requires either real-device manual testing or `agent-device` automation. Bugs that only reproduce on hardware are slower to catch.

## The general shape

This bug isn't unique to SpriteKit, or to games, or to iOS. Any system that computes `delta = now - then` and integrates against `delta` is fragile to suspension. Web apps with `requestAnimationFrame`. Servers with cron-like timers. Anything where wall-clock seconds and *system-active* seconds drift apart.

Two rules worth keeping:

1. **Identify every frame-time discontinuity in your loop.** Start, restart, resume, settings, pause, debugger detach, anything that can make wall-clock time advance while your scheduler is silent. Each of those is a reset site for your `dt` accumulator.

2. **Add a sentinel branch in the update path.** A magic value that means "first frame, no previous." Treat it as part of the integration contract, document it, and pay the cognitive cost up front so the bug never has to teach the lesson.

The bug took an hour to reproduce reliably and ten minutes to fix. The hour was the part where someone unlocked their phone mid-playtest and we noticed.
