# Haptic budget: medium for damage, light for saves, silent for near-misses

Haptic feedback on mobile is the cheapest UX upgrade you can ship. `UIImpactFeedbackGenerator(style: .medium)`, two lines of setup, and suddenly your game feels real instead of read. So you wire it up to every collision. The penguin gets hit — buzz. An icicle lands nearby — buzz. The penguin survives by an inch — buzz. The HUD updates — buzz. Now your game feels like a vibration toy and every event means the same thing, which is to say, nothing.

The fix isn't fewer haptics. It's a budget. PenguinSlide gives haptic feedback three jobs and explicitly refuses to do anything else with it.

## The three jobs

A comment near the top of `IcicleSystem.swift` lays out the policy:

```swift
// PenguinSlide/IcicleSystem.swift:38
// Pre-warmed haptic generators. Medium for accepted hits (HP loss);
// light for i-frame-blocked saves and for shake-radius ground landings.
// Near-miss (severity == 0) landings stay haptic-silent — deferred to
// penguinslide-y7f, where close-call becomes a scored mechanic.
// Game-over haptic stays in GameScene (UINotificationFeedbackGenerator.error).
private let hapticHit = UIImpactFeedbackGenerator(style: .medium)
private let hapticLight = UIImpactFeedbackGenerator(style: .light)
```

Two generators. Three events that fire them. One terminal event that lives somewhere else entirely.

**Job 1 — Damaging hit (HP loss).** An icicle landed on the penguin during a moment they weren't invulnerable. The penguin lost a heart. This is the loudest moment in the game; haptics get the full medium tap:

```swift
// PenguinSlide/IcicleSystem.swift:176 (excerpt)
if accepted {
    hapticHit.impactOccurred()
    scene?.run(shatterSound)
    cryAudioNode?.run(cryRestart)
    shatterIcicle(... severity: 1.0, ...)
    screenShake(near: contactPoint.x)
}
```

The medium haptic sits alongside the cry sound, full-severity shards, and a screen shake. The phone tells you, in four coordinated channels, *you just lost a heart*.

**Job 2 — Save (i-frame block).** The penguin got hit but it was during their invulnerability window (see [post #4](04-i-frames-game-feel.md) for how that window is made legible). The hit doesn't count, but the player needs to know that the contact *happened* — otherwise the icicle visually clipping the penguin reads as a bug, not as a mechanic. Light haptic. No cry sound. No screen shake.

```swift
// PenguinSlide/IcicleSystem.swift:184 (excerpt)
} else {
    // Blocked by i-frames: softer pop, no shake. The penguin's
    // alpha flicker is the feedback for "still invulnerable".
    hapticLight.impactOccurred()
    scene?.run(shatterSound)
    shatterIcicle(... severity: 0.6, ...)
}
```

The shatter sound still plays — that's the icicle doing its physics, not feedback about the player. But the haptic, the cry, and the shake all change. Same input, different state, different feel.

**Job 3 — Near landing that shakes the camera.** This one is the most interesting decision in the file. When an icicle hits the *ice* near the penguin (close enough that the camera shake fires), we fire a light haptic too:

```swift
// PenguinSlide/IcicleSystem.swift:387 (excerpt)
let dx = abs(landingPoint.x - penguin.node.position.x)
let severity = max(0, 1 - dx / Tuning.Feel.shakeRadius)
shatterIcicle(at: landingPoint, severity: severity)
if severity > 0 {
    hapticLight.impactOccurred()
    scene?.run(shatterSound)
    screenShake(near: landingPoint.x)
}
```

Severity falls off linearly with distance to the penguin. Inside the shake radius, the player feels the impact through the phone *and* the camera lurches. Outside the shake radius, severity is `0` — and the `if severity > 0` gate means **the haptic doesn't fire at all**. A distant landing is purely a visual event.

## What we explicitly don't do

The discipline is in the negative space. Things we do **not** fire haptics for:

- **The warning crack and telegraph shake** when an icicle is about to fall. Hundreds per round; would turn the phone into a vibrator.
- **Near-miss landings outside the shake radius.** Those become a scored mechanic later (penguinslide-y7f); deliberately silent for now.
- **HUD updates** — heart pulses, score changes. The HUD has its own visual feedback. Haptics would compete.
- **Game over.** That's a `UINotificationFeedbackGenerator.error` over in `GameScene`, not an impact-style at all. A different physical sensation for a different *kind* of event.

The rule we ended up with: **haptics fire when something happens to or around the penguin's physical position**. Everything else uses audio, visual, or nothing.

## Generators are pre-warmed

One implementation detail worth calling out. Both generators are kept as long-lived instance properties on `IcicleSystem`, and `prepare()` is called in `init`:

```swift
// PenguinSlide/IcicleSystem.swift:108
hapticHit.prepare()
hapticLight.prepare()
```

Without `prepare()`, the first `impactOccurred()` after a quiet period can latency-spike — the taptic engine warms up cold, and you feel the buzz milliseconds after the visual. With it, the engine stays armed and the impact is frame-aligned. Iceberg detail, but it's the difference between "satisfying" and "weirdly delayed."

## What it costs

- **Two generators per system, not one.** You can't dynamically choose intensity on a single generator — each style is its own instance. So every system that wants graduated haptics carries the multiplicity.
- **Policy is in comments, not in types.** The "medium for damage, light for saves" decision lives in a comment block and in the call sites. There's no `HapticEvent` enum forcing the categorization. Trade-off: less code, more discipline.
- **No accessibility opt-out yet.** Some players are haptic-sensitive. We don't have a toggle. Should add one.
- **Engine warm-up is implicit.** If we add a new haptic generator anywhere in the codebase, we need to remember `prepare()`. Easy to miss.
- **Game-over haptic lives in a different file.** That's the right call (it's a different kind of event, fired once) but discoverability suffers. The comment block in `IcicleSystem` flags it explicitly so future-us doesn't go looking for it in the wrong place.

## The general shape

Haptics are an axis of expression, not a notification mechanism. Treat them like sound effects: you wouldn't fire a `damage_taken.wav` every time the HUD redraws, so don't fire `.medium` either.

A workable mental model: **what's the smallest set of distinct events that the player's hand needs to feel?** Probably three or four. Once you have that list, every haptic call in your codebase should map to exactly one of them. Anything that doesn't map is either a bug or a missing entry on the list.

The negative space — the events you deliberately don't haptic-respond to — is where the meaning lives. A save feels different from a hit *because* the cry sound doesn't play and the camera doesn't shake, not just because the haptic is lighter. Coordinate every feedback channel against the same event taxonomy, and your game will feel like the designers actually thought about it.
