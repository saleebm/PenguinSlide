# Layered arcade audio: cinematic loop, impact SFX, and attenuation rules

At peak difficulty, PenguinSlide spawns about three icicles a second. Each icicle warns with a crack sound for three quarters of a second, then falls, then either lands on the ice (shatter sound, volume attenuated by distance from the penguin) or lands on the penguin (shatter + cry). The background music loops underneath. Game-over plays its own sting on death. Naively wired, this is audio mud: half a dozen sources contending for the same speaker, sounds stomping on each other, the bed track drowning the SFX or vice versa.

We didn't fix it with a mixer abstraction. We fixed it by classifying each sound by lifetime and picking the right SpriteKit API for each one.

## Two APIs, three lifetimes

SpriteKit gives you two ways to play audio:

- `SKAction.playSoundFileNamed(_:waitForCompletion:)`: fire-and-forget, can overlap, can be cached.
- `SKAudioNode(fileNamed:)`: persistent node in the scene graph, volume-controllable, addressable for stop/play, loopable.

Each sound in PenguinSlide picks the one that matches what it needs to *do*.

**Lifetime 1: looping ambient bed.** The background music has to play continuously, idle quietly under the SFX, and pause when the app suspends. That's a long-lived node:

```swift
// PenguinSlide/GameScene.swift:87
let bg = SKAudioNode(fileNamed: "bg_music.caf")
bg.autoplayLooped = true
bg.isPositional = false
bg.run(SKAction.changeVolume(to: 0.18, duration: 0))
addChild(bg)
bgMusic = bg
```

Volume 0.18, much quieter than the SFX. It's a bed, not a foreground element. `isPositional = false` because we don't want SpriteKit's spatial mixing to attenuate it based on camera position (the camera shakes; the music shouldn't pan).

**Lifetime 2: one-shot SFX that fires and forgets.** The game-over sting plays once on death, doesn't need to be addressable, and shouldn't block. That's a cached `SKAction`:

```swift
// PenguinSlide/GameScene.swift:29
// Cached game-over sound. Paired with the existing .error haptic in
// gameOver(). Pre-built so the death dispatch is a cheap run() call.
private let gameOverSound = SKAction.playSoundFileNamed("game_over.caf",
                                                         waitForCompletion: false)
```

`run(gameOverSound)` is now a cheap dispatch: no disk lookup, no node setup. We use this lifetime *only* for sounds that fire once per round (or rarely enough that overlap isn't a concern). Earlier, the icicle shatter lived here too, but it grew distance-based volume requirements that `SKAction.playSoundFileNamed` can't satisfy (no per-call volume hook). Moved it to Lifetime 3 (below).

**Lifetime 3: recurring trigger that needs rate-limiting.** The icicle crack (the warning sound when an icicle starts to fall) is the trickiest. It fires on every spawn, three times a second at peak. The raw clip is *loud*, and overlapping crack sounds turn into a wall of noise. We needed two things: attenuation, and natural rate-limiting.

`SKAudioNode` solves both:

```swift
// PenguinSlide/IcicleSystem.swift:63
// Crack uses SKAudioNode so we can attenuate it (the raw clip is loud
// enough to grate when icicles spawn 2-3×/s). stop+play on each spawn
// restarts the clip, which also naturally rate-limits the SFX so it
// doesn't pile up at peak.
private var crackAudioNode: SKAudioNode?
private let crackRestart = SKAction.sequence([.stop(), .play()])
```

The init wires it up at volume 0.25:

```swift
// PenguinSlide/IcicleSystem.swift:159
let crack = SKAudioNode(fileNamed: "icicle_crack.caf")
crack.autoplayLooped = false
crack.isPositional = false
crack.run(SKAction.changeVolume(to: 0.25, duration: 0))
scene.addChild(crack)
crackAudioNode = crack
```

Then every spawn does:

```swift
crackAudioNode?.run(crackRestart)
```

The `stop+play` sequence means a new crack restarts the clip from the top instead of overlapping with the previous one. The clip becomes a single-channel SFX that always plays from frame zero. At peak spawn rate, you hear crack-crack-crack-crack as discrete events, not as smeared overlapping noise. The audio is self-limiting because the node can only be in one place in its playback at a time.

The penguin cry follows the exact same pattern, except it fires only on damage (not on i-frame saves) and runs louder (volume 0.9) so the player feels it:

```swift
// PenguinSlide/IcicleSystem.swift:79
// Penguin yelp on damaging hit (HP loss). Skipped on i-frame saves so
// the cry stays meaningful as "ouch, that hurt". stop+play restarts so
// back-to-back hits don't queue up a chorus.
private var cryAudioNode: SKAudioNode?
private let cryRestart = SKAction.sequence([.stop(), .play()])
```

If we used `SKAction.playSoundFileNamed` for the cry, two back-to-back damaging hits would queue up two simultaneous cries and the penguin would sound like a flock. With `SKAudioNode` + restart, two hits make two crisp yelps, one after the other.

**Variant: per-call volume.** The icicle shatter sound is a third instance of the same pattern, but with one twist: its volume depends on *where* the icicle lands relative to the penguin. A landing right under the player should be punchy; a landing across the strip should be a faint tick. `SKAction.playSoundFileNamed` can't do this (no per-call volume), and a static init-time `changeVolume` doesn't either (one volume for all plays). So we leave the node at default volume and inject `changeVolume(to:duration:)` into the play sequence at the call site:

```swift
// PenguinSlide/IcicleSystem.swift:640
private func playLandingShatter(distance dx: CGFloat) {
    guard let audio = shatterAudioNode else { return }
    let t = max(0, 1 - dx / Tuning.Feel.landingAudioFalloffRadius)
    let vol = Tuning.Feel.landingAudioMinVolume
        + (Tuning.Feel.landingAudioMaxVolume - Tuning.Feel.landingAudioMinVolume) * Float(t)
    audio.run(.sequence([
        .changeVolume(to: vol, duration: 0),
        .stop(),
        .play()
    ]))
}
```

Linear falloff from `landingAudioMaxVolume` (0.22) at the penguin's x down to `landingAudioMinVolume` (0.025) at `landingAudioFalloffRadius` (600 pts) and beyond. The floor is nonzero on purpose; far landings still produce a faint tick rather than going silent, so the player always hears the strip is active. Penguin-collision hits route through the same function with `distance: 0`, landing at the calibrated max volume instead of stacking at full system volume the way they used to.

## AVAudioSession: playback + mixWithOthers

One piece outside SpriteKit. At app init we configure the audio session:

```swift
// PenguinSlide/PenguinSlideApp.swift:15
init() {
    // .playback + .mixWithOthers: game audio plays regardless of the
    // silent switch (standard game behaviour) while music apps and
    // podcasts keep playing underneath.
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, options: [.mixWithOthers])
    try? session.setActive(true)
}
```

`.playback` is the standard for games and overrides the silent switch, which is what players expect. `.mixWithOthers` is the kind move: a player listening to a podcast or their own music shouldn't have their audio killed when they open our game. Both keep playing, ours under theirs. Players who want full silence have the volume slider.

## Pause: SKAudioNode plays through scene pause

A gotcha that took a debugging session to find. When the app suspends, we `view?.isPaused = true` to freeze the game. `SKAction.playSoundFileNamed`-fired sounds stop because their owning actions stop. But `SKAudioNode` runs on the audio engine, not the scene clock; it keeps playing.

The fix is explicit pause/resume on the audio node:

```swift
// PenguinSlide/GameScene.swift:122
@objc private func handleWillResignActive() {
    view?.isPaused = true
    // SKAudioNode runs on the audio engine, not the scene clock, so it
    // keeps playing through view.isPaused. Explicit pause here.
    bgMusic?.run(SKAction.pause())
}

@objc private func handleDidBecomeActive() {
    lastUpdateTime = 0
    view?.isPaused = false
    bgMusic?.run(SKAction.play())
}
```

Without this, locking the phone mid-game left the music playing in the background until the app actually got killed.

## What this costs

- **Two APIs in the same file is more to learn.** A new contributor needs to know that `SKAction.playSoundFileNamed` and `SKAudioNode(fileNamed:)` aren't interchangeable. Comments at the call sites help.
- **Volume calibration is manual.** `0.18` for music, `0.25` for crack, `0.9` for cry, `0.025–0.22` for shatter (distance-attenuated), full volume for game-over. There's no master mixer. We picked the numbers by ear, on a single device. Players on different hardware may want different mixes; we don't have a setting yet.
- **`SKAudioNode` independent pause behavior is a footgun.** The comment in `handleWillResignActive` exists because we hit this once. Future audio nodes will need the same pause hook.
- **`mixWithOthers` means we don't own the stage.** A loud podcast playing underneath can drown a soft icicle crack. The trade-off is that we don't kill people's music when they open our game; we judged that as the right call.
- **Five `.caf` files in `Sounds/`.** Small download cost; clear single source of truth.

## The general shape

Audio bugs feel mysterious because so many things share one output channel. The pattern that worked for us was a three-line decision tree:

1. **Does it need to be addressable, attenuated, or pause-aware?** → `SKAudioNode`. Owned, volume-set in init, controlled with `.stop()`/`.play()`.
2. **Should it fire freely and stack?** → `SKAction.playSoundFileNamed`, cached as a property, `waitForCompletion: false`.
3. **Should it rate-limit naturally?** → `SKAudioNode` + a `stop+play` restart sequence. The single-channel constraint *is* the rate limit.

Pick the API at the call site by what the sound needs to *do*, not by what the engine happens to make easiest. The mud-vs-music line is on the other side of that decision.
