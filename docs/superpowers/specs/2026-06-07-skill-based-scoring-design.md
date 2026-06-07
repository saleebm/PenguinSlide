# Skill-based scoring — close-call bonus & combo (penguinslide-y7f)

**Date:** 2026-06-07
**Bead:** penguinslide-y7f (feature, P2)
**Status:** Design approved, pending implementation plan

## Problem

Current scoring is `score = Int(elapsed * 10)` (`GameScene.swift:359`) — pure
survival time. A player who hugs a safe edge scores identically to one who
threads the needle past falling icicles. The README sells dodging as the core
loop, but the score is decoupled from skill.

## Goal

Reward close-call dodges and reward consecutive ones with a combo multiplier,
with visible HUD feedback — without adding a second notion of "near" to the
physics. The existing `severity` value is the single source of truth.

## Grounding: what already exists

- **`severity`** (`IcicleSystem.swift:502`): `max(0, 1 - dx / Tuning.Feel.shakeRadius)`,
  where `dx` is the landing's horizontal distance from the penguin and
  `shakeRadius = 140` (`Tuning.swift:83`). A `0…1` "how close was it" number
  that already drives camera shake, haptics, shard count, and audio volume.
- **A landing that reaches the ice is, by construction, a survived dodge.**
  Per the comment at `IcicleSystem.swift:496-500`, the penguin-contact path
  consumes any icicle that hits the penguin *before* it reaches the landing
  code. So no separate "was it a hit?" check is needed — reaching the landing
  site already means the penguin dodged it.
- **Score** is recomputed every frame from `elapsed` (`GameScene.swift:359`);
  `elapsed` resets in `restart()` (`:425`). `score`'s `didSet` pushes to
  `hud.setScore` (`:50-52`).
- **Hit path:** `penguin.tryTakeHit(...)` returns `accepted` (HP actually lost)
  at `GameScene.swift:374`. i-frame saves return `false`.
- **Architecture contract:** `IcicleSystem` is pure detection, `GameScene` is
  the orchestrator/state owner, `HUDController` is pure presentation
  (`setScore`/`setHealth`/… ). This design keeps those boundaries.

## Design decisions (locked)

1. **Source of truth:** reuse `severity` / `shakeRadius`. No new
   `closeCallRadius`, no `nearMissRadius`, no new physics.
2. **Bonus scales with severity** — closer dodges pay more.
3. **Survival rate stays 10/s** — close-calls are pure upside on top; existing
   `best_score` scale is preserved.
4. **HUD:** combo counter *and* a floating `+N` from the landing point.
5. **Scope:** close-call bonus + combo + both HUD cues, one feature. Combo is
   not split into a follow-up (owner chose full y7f).

## Architecture

```
IcicleSystem.update()  ──onCloseCall(severity, landingPoint)──▶  GameScene
   (detect: severity ≥ closeCallSeverity)                     (state: combo, bonusPoints)
                                                                     │
                                          setScore / showCombo / floatBonus ▼
                                                               HUDController (present)
```

One new outbound closure, mirroring the existing `Penguin.onHealthChanged`
callback pattern. Data flows detection → state → presentation, one direction.

### New tuning: `Tuning.Score`

A new sub-enum in `Tuning.swift`, grouped alongside `Feel`:

| Knob | Value | Meaning |
|------|-------|---------|
| `closeCallSeverity` | `0.5` | A survived landing with `severity ≥ this` counts as a scored close-call. 0.5 ≈ within 70pt (half of `shakeRadius`). |
| `closeCallBase` | `50` | Base points for a close-call, before severity and combo scaling. |
| `comboWindow` | `2.5` (s) | Max gap between close-calls to keep a streak alive. |
| `comboMaxMultiplier` | `5.0` | Combo multiplier ceiling so a long streak can't run away. |
| `survivalRate` | `10` | Passive survival points per second. Unchanged value; relocated from the literal `10` at `GameScene.swift:359`. |

### Detection — `IcicleSystem`

Add an outbound closure:

```swift
/// Fired when a *survived* landing clears the close-call severity threshold.
/// (severity 0…1, landingPoint in scene coords). GameScene turns this into a
/// scored dodge; IcicleSystem stays pure detection and knows nothing of score.
var onCloseCall: ((CGFloat, CGPoint) -> Void)?
```

At the landing site (`IcicleSystem.swift:~510`, beside the existing
`severity > 0` haptic/shake block), after `severity` is computed:

```swift
if severity >= Tuning.Score.closeCallSeverity {
    onCloseCall?(severity, landingPoint)
}
```

This is a stricter subset of the existing `severity > 0` shake condition, so it
never fires for distant landings.

### State — `GameScene`

New properties:

```swift
private var bonusPoints: Int = 0
private var combo: Int = 0
private var lastCloseCallTime: TimeInterval = 0
```

Wire the callback in setup (near the existing `penguin.onHealthChanged`
assignment, ~`:110`):

```swift
icicles.onCloseCall = { [weak self] severity, point in
    self?.registerCloseCall(severity: severity, at: point)
}
```

Change the score line (`:359`):

```swift
score = Int(elapsed * Tuning.Score.survivalRate) + bonusPoints
```

This is the one structural change: score becomes *survival + accumulated
bonus* rather than a pure function of `elapsed`. Without it, the next frame's
recompute would erase every bonus.

Combo decay — at the top of `update()`, after `elapsed += dt` and **before**
`icicles.update(...)` (so a close-call fired this frame is never decayed in the
same frame it occurs):

```swift
if combo > 0 && elapsed - lastCloseCallTime > Tuning.Score.comboWindow {
    combo = 0
    hud.hideCombo()
}
```

The callback target:

```swift
private func registerCloseCall(severity: CGFloat, at point: CGPoint) {
    combo += 1                                   // decay already zeroed a lapsed streak
    lastCloseCallTime = elapsed
    let multiplier = min(CGFloat(combo), Tuning.Score.comboMaxMultiplier)
    let bonus = Int((CGFloat(Tuning.Score.closeCallBase) * severity * multiplier).rounded())
    bonusPoints += bonus
    hud.floatBonus(bonus, at: point)
    if combo >= 2 { hud.showCombo(combo) }
}
```

Reset on clip — after `tryTakeHit` (`:374-375`), only on an accepted (HP-losing)
hit; i-frame saves keep the streak:

```swift
let accepted = penguin.tryTakeHit(from: icicleNode.position.x)
icicles.onIcicleHitPenguin(icicle: icicleNode, at: contact.contactPoint, accepted: accepted)
if accepted {
    combo = 0
    hud.hideCombo()
}
```

Reset on restart (`:425`, alongside `elapsed = 0`):

```swift
bonusPoints = 0
combo = 0
lastCloseCallTime = 0
hud.hideCombo()
```

### Presentation — `HUDController`

New `comboLabel` (created hidden in `init`, below the score label, warm gold):

```swift
func showCombo(_ combo: Int) {
    comboLabel.text = "×\(combo)"
    comboLabel.removeAction(forKey: "comboFx")
    comboLabel.run(.sequence([
        .group([.fadeIn(withDuration: 0.1), .scale(to: 1.3, duration: 0.1)]),
        .scale(to: 1.0, duration: 0.12)
    ]), withKey: "comboFx")
}

func hideCombo() {
    comboLabel.removeAction(forKey: "comboFx")
    comboLabel.run(.fadeOut(withDuration: 0.2))
}

func floatBonus(_ amount: Int, at point: CGPoint) {
    guard let scene else { return }
    let label = SKLabelNode(fontNamed: Self.safeFont(named: "AvenirNext-Bold"))
    label.text = "+\(amount)"
    label.fontSize = 22
    label.fontColor = UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1)
    label.position = point
    label.zPosition = 60
    label.horizontalAlignmentMode = .center
    scene.addChild(label)
    label.run(.sequence([
        .group([
            .moveBy(x: 0, y: 60, duration: 0.7),
            .sequence([.wait(forDuration: 0.4), .fadeOut(withDuration: 0.3)])
        ]),
        .removeFromParent()
    ]))
}
```

`floatBonus` adds to the scene at scene coordinates — the same pattern shards
and bursts already use, so the landing point lands correctly.

## Error / edge handling

- **dt == 0 sentinel:** combo decay uses `elapsed`, which only advances when
  `dt > 0`, so the resume sentinel (`lastUpdateTime = 0`) cannot expire a combo
  across a screen-lock/settings pause. No new resume plumbing needed.
- **Death frame:** all combo/score work stays behind the existing
  `isStarted && !isGameOver` guard in `update()`. The reset-on-clip happens in
  `didBegin`, which already runs inside the physics step; setting `combo = 0`
  there is state-only (no node motion), so it respects the update-loop ordering
  contract.
- **Float-text leak:** each `+N` label ends its action sequence with
  `.removeFromParent()`, matching shard cleanup; no manual tracking array.

## Testing

- **Manual device verification (primary):** SpriteKit gameplay needs a physical
  device (no simulator gyro). Confirm: combo label appears at ×2 and increments;
  `+N` floats from landing points; combo clears after `comboWindow` of no
  dodges and on taking a hit; standing in a safe lane grows score slowly while
  active dodging clearly out-scores it.
- **Unblocks `penguinslide-ga8`:** a real severity-thresholded close-call now
  exists to assert against (its DEBUG severity-flag hook becomes implementable).
  Tracked separately — not built here.
- **README:** add `Score` rows to the "Where to tweak difficulty" table.

## Acceptance (from bead)

1. Standing-still survival no longer grows score as fast as active-dodging play. ✓ (dodging adds bonus on top)
2. Combo HUD appears and increments correctly. ✓
3. Combo resets when the player gets clipped (game over / accepted hit) or misses the window. ✓
4. Tuning constants are documented in the README. ✓

## Out of scope

- Combo split into a follow-up commit (owner chose full y7f).
- Any change to physics tuning, `shakeRadius`, or the severity formula itself.
- The `ga8` near-miss test harness and the `9f8` TESTING.md doc note (separate beads).
- Re-deriving the score economy / lowering survival rate.
