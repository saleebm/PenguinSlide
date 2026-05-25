# I-frames as game feel: making invulnerability legible

An icicle just hit the penguin. The red flash plays. The HUD's third heart fades. For the next second, every icicle that touches the penguin is supposed to bounce off harmlessly while the player gets a breath. This is the i-frame window: the standard "you can't be hit again for a moment" mechanic borrowed from every arcade game since 1986.

The problem with i-frames isn't writing them. The problem is making them *visible*. Without a strong signal, the player thinks they got lucky. They lean into the next icicle. It hits. They take damage they thought was free. They feel cheated by their own game.

PenguinSlide spends three separate feedback channels on that one second.

## What we're actually doing

The state is one `TimeInterval`:

```swift
// PenguinSlide/Penguin.swift:34
private var invulnerableUntil: TimeInterval = 0
```

`tryTakeHit(from:)` is the gate. It returns `false` (no damage) if `elapsed < invulnerableUntil`. On accepted hits it decrements HP, then *conditionally* arms the next i-frame window:

```swift
// PenguinSlide/Penguin.swift:199
func tryTakeHit(from impactX: CGFloat) -> Bool {
    if elapsed < invulnerableUntil { return false }
    hp = max(0, hp - 1)
    // Arm i-frames only if the penguin survives. Skipping this on the
    // killing blow means the shield-ring cloak never appears on the
    // fatal hit — death feedback gets to read uncontested.
    if hp > 0 {
        invulnerableUntil = elapsed + Tuning.Penguin.iFrameDuration
    }
    // ...knockback, animation, callback...
    return true
}
```

That `if hp > 0` is load-bearing. The killing blow deliberately doesn't arm i-frames, so the shield-ring cloak doesn't fire and obscure the death animation. Easy to write the wrong way; harder to debug.

## Three channels, no overlap

Once i-frames are armed, `Penguin.update(_:)` runs three feedback channels in parallel, each with a different job.

**Channel 1: alpha flicker, 8 Hz.** This is the soft, accessible cue. The body sprite's alpha oscillates between `1.0` and `iFrameDimAlpha` (`0.75`) on a sine wave:

```swift
// PenguinSlide/Penguin.swift:177
let isInvulnerable = elapsed < invulnerableUntil
if isInvulnerable {
    if !wasInvulnerable { showShieldRing() }
    let lit = sin(elapsed * 2 * .pi * TimeInterval(Tuning.Penguin.iFrameFlashHz)) > 0
    node.alpha = lit ? 1.0 : Tuning.Penguin.iFrameDimAlpha
} else {
    if wasInvulnerable { hideShieldRing() }
    if node.alpha != 1.0 && node.action(forKey: "death") == nil {
        node.alpha = 1.0
    }
}
wasInvulnerable = isInvulnerable
```

The `sin` is computed against the penguin's own elapsed clock, so the flicker is dt-independent and looks identical at 30, 60, or 120 fps. We use 0.75 instead of full transparency on the down-cycle because at peak difficulty the penguin needs to stay readable; a full alpha drop disappears them, and players can't dodge what they can't see.

**Channel 2: cyan shield ring.** This is the primary "you're protected" tell. A child `SKShapeNode` parented to the body sprite (so it inherits lean, bob, and position for free) fades in at the rising edge of i-frames, pulses scale + alpha for the duration, and fades out at the falling edge:

```swift
// PenguinSlide/Penguin.swift:283
private func showShieldRing() {
    shieldRing.removeAction(forKey: "cloak")
    shieldRing.setScale(1.0)
    shieldRing.alpha = 0.4
    let period = Tuning.Penguin.shieldRingPulsePeriod
    let up = SKAction.group([
        .scale(to: 1.15, duration: period),
        .fadeAlpha(to: 0.8, duration: period)
    ])
    let down = SKAction.group([
        .scale(to: 1.0, duration: period),
        .fadeAlpha(to: 0.4, duration: period)
    ])
    shieldRing.run(.repeatForever(.sequence([up, down])), withKey: "cloak")
}
```

Cyan is not a coincidence. The damage flash is red. Putting the shield ring on the cyan/red opposition means the two states read as fundamentally different events at a glance; peripheral vision is enough. If you've ever made the mistake of using two oranges and a yellow for distinct game states, you know what we were trying to avoid.

The ring is `blendMode = .add`, so it brightens whatever's underneath instead of overlaying flat color. Reads as energy, not paint.

**Channel 3: audio + haptic suppression.** When an icicle hits the penguin during i-frames, `IcicleSystem.onIcicleHitPenguin` knows because `tryTakeHit` returned `false`. The whole feedback profile changes:

```swift
// PenguinSlide/IcicleSystem.swift:176 (excerpt)
if accepted {
    hapticHit.impactOccurred()    // medium tap
    scene?.run(shatterSound)
    cryAudioNode?.run(cryRestart) // penguin yelps
    shatterIcicle(... severity: 1.0, ...)
    screenShake(near: contactPoint.x)
} else {
    // Blocked by i-frames: softer pop, no shake. The penguin's
    // alpha flicker is the feedback for "still invulnerable".
    hapticLight.impactOccurred()  // light tap
    scene?.run(shatterSound)
    shatterIcicle(... severity: 0.6, ...)
    // no cry, no screen shake
}
```

A damage hit gets a medium haptic, the penguin's cry sound, full-severity shards, and a screen shake. An i-frame-blocked hit gets a light haptic, the same shatter sound but at lower visual severity, and *no* cry and *no* shake. The negative space is the signal: the player feels and hears that something different happened. [Post #2](02-haptic-budget.md) goes deeper on the haptic budgeting decisions.

## What it costs

Three coordinated channels is more code to keep coherent than one. The honest trade-offs:

- **Edge transitions are tricky.** `wasInvulnerable` tracks whether the previous frame was inside the window, so we only fire `showShieldRing()` on the rising edge and `hideShieldRing()` on the falling edge. Forget that boolean and you'll re-run the cloak action every frame and the pulse will reset.
- **Z-order matters.** The shield ring is parented to the penguin body and has `zPosition = -0.1`. Get the sign wrong and the ring renders *over* the penguin instead of behind it. The penguin reads as inside a bubble; not what we wanted.
- **Color is load-bearing.** `shieldRingColor` lives outside the JSON-Codable surface in [`PenguinTuning.swift:107`](../../PenguinSlide/PenguinTuning.swift) precisely because we don't want a settings UI to make the ring red by accident.
- **The lethal-hit special case is easy to forget.** If you arm i-frames on every accepted hit, the cloak appears for one frame on death. Awful. The `if hp > 0` is the fix.
- **Three channels still isn't a guarantee.** Players with strobe-light sensitivity may need an option to dim the flicker further. We left `iFrameDimAlpha` tunable for that reason.

## The general shape

Invulnerability is a contract between game state and player perception. Every channel that touches the player (visual, audio, haptic) needs an opinion about that contract. If even one channel is silent or sends the wrong signal, the player's mental model breaks and they blame the game.

Two rules we'll keep:

1. **Use color opposition for state opposition.** Red flash, cyan cloak. The peripheral-vision reading should be unambiguous.
2. **Have a primary tell and a secondary tell.** Shield ring is loud and clear; alpha flicker is the accessibility fallback. Players see what they're tuned to see.

When you build a state that mutes one of the player's expected feedback channels (damage but no HP loss; collision but no shake), build *something else* in its place. The player will fill the silence with their own interpretation, and you usually won't like what they come up with.
