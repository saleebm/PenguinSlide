# Per-icicle gravity in SpriteKit without rewriting physics

PenguinSlide drops twenty or thirty icicles a minute at the player. They all start at the top of the screen, but they don't all fall at the same speed. Some plunge fast; some drift down lazily. The variance is intentional: when every icicle falls identically, the field reads as a metronome and dodging becomes a timing exercise. When falls jitter, you have to actually look at each one.

The trick is that SpriteKit doesn't want us to do this. `SKPhysicsWorld` has exactly one gravity vector. Every body in the world feels the same downward pull, period. There's no `physicsBody.gravityScale` like Unity has. There's no per-body acceleration override. You get one number, and everybody falls at the same rate.

So we don't use `SKPhysicsWorld`'s gravity at all.

## The decision

At scene setup, we zero out the world's gravity:

```swift
// PenguinSlide/GameScene.swift:53
// Scene-level gravity stays at zero. SKPhysicsBody has no per-body
// gravity scaling, so IcicleSystem integrates per-node gravity
// manually via its `FallingBody` entries.
physicsWorld.gravity = .zero
```

Then every falling thing (icicles, shatter shards) gets a small struct that bundles the node with its individual gravity value:

```swift
// PenguinSlide/IcicleSystem.swift:31
private struct FallingBody {
    weak var node: SKSpriteNode?
    let gravity: CGFloat
}
private var fallingIcicles: [FallingBody] = []
private var activeShards:   [FallingBody] = []
```

`IcicleSystem.update(dt:elapsed:)` calls `integrateAndCheckLandings(dt:)` every frame, which walks both arrays and does the integration by hand:

```swift
// PenguinSlide/IcicleSystem.swift:371 (excerpt)
let dtF = CGFloat(dt)
fallingIcicles = fallingIcicles.compactMap { entry in
    guard let icicle = entry.node, let body = icicle.physicsBody else { return nil }
    body.velocity.dy -= entry.gravity * dtF
    // ...landing checks omitted...
    return entry
}
```

One line (`body.velocity.dy -= entry.gravity * dtF`) replaces SpriteKit's gravity step for this body. The physics body still exists; it still participates in contact detection with the penguin; it still bounces sensibly if it hits something. We just took its `dy` acceleration into our own hands.

## Where the variance comes from

Each spawn picks a gravity value before the icicle is even instantiated. It's a difficulty-curve lerp with random jitter on top:

```swift
// PenguinSlide/IcicleSystem.swift:219
private func computedIcicleGravityScale(elapsed: TimeInterval) -> CGFloat {
    let p = progress(elapsed: elapsed)
    let mean = Tuning.Icicle.gravityScaleStart
        + (Tuning.Icicle.gravityScaleEnd - Tuning.Icicle.gravityScaleStart) * p
    let jitter = Tuning.Icicle.gravityScaleVariance
    let factor = CGFloat.random(in: (1 - jitter)...(1 + jitter))
    return mean * factor
}
```

`Tuning.Icicle.gravityScaleStart` is `0.45`, `gravityScaleEnd` is `1.10`, and `gravityScaleVariance` is `0.20`. So at the start of a round, an icicle falls at roughly `(0.45 ± 20%) × sceneGravity`: slow. At peak difficulty 90 seconds in, the same icicle would be falling at `(1.10 ± 20%) × sceneGravity`: twice as fast, and one in five spawns can be 32% slower or faster than the surrounding pack. The dodging tempo never settles.

The result is stored on the `FallingBody` entry the moment the icicle detaches:

```swift
// PenguinSlide/IcicleSystem.swift:338
self.fallingIcicles.append(FallingBody(node: icicle, gravity: perIcicleGravity))
```

That `perIcicleGravity` was computed earlier in the same function. The manual loop pays off twice: because we know each icicle's gravity at spawn time, we can solve the falling-distance kinematic equation and predict, *to the millisecond*, when each icicle will hit the ice. The chasing-aim algorithm uses that prediction to lead the penguin's movement:

```swift
// PenguinSlide/IcicleSystem.swift:266 (excerpt)
// h = v₀·t + ½·g·t²    for t (with t > 0):
//     t = (-v₀ + √(v₀² + 2·g·h)) / g
let perIcicleGravity = Tuning.Icicle.sceneGravity * computedIcicleGravityScale(elapsed: elapsed)
let h  = spawnY - (iceTopY + height / 2)
let v0 = Tuning.Icicle.initialDownVelocity
let g  = perIcicleGravity
let predictedFallTime: TimeInterval = h > 0 && g > 0
    ? TimeInterval((-v0 + sqrt(v0 * v0 + 2 * g * h)) / g)
    : 0
```

Slow icicles get a longer prediction window and a more confident lead on the penguin. Fast ones get a shorter window. With SpriteKit's built-in gravity that would have been impossible; every icicle would share the same global `g`, and the aim algorithm would have to assume one fall time for the whole field.

## What it costs

Trading SpriteKit's physics step for a manual one isn't free.

- **Pause is your problem now.** Setting `physicsWorld.speed = 0` halts SpriteKit's physics, but our `update(dt:elapsed:)` loop still gets called. We have to guard the gravity step ourselves when the game is paused, and we do (see the `isGameOver` checks elsewhere in the scene).
- **Variable timestep risks.** SpriteKit's built-in integrator uses a fixed step internally. Ours uses whatever `dt` the scene hands us. After an app suspension, `dt` can spike to several seconds, which would teleport every icicle past the floor. We solve this in [post #7](07-screen-lock-frame-time-bug.md); it's a real bug that bit us.
- **Reset logic doesn't come for free.** `IcicleSystem.reset()` has to clear `fallingIcicles` and `activeShards` explicitly. Trust nothing the physics world would have garbage-collected.
- **Two systems of truth.** The icicle's `physicsBody.velocity` is real, but only `dx` matters for physics; `dy` is something we own. Anyone reading the code has to know which axis is whose.
- **No free coupling.** If we ever want icicles to interact with each other under gravity (they don't), we'd have to wire that up by hand.

## When to reach for this

Reach for this whenever your game design needs per-entity variance on a parameter the engine treats as global. SpriteKit's gravity is the canonical example, but the same shape applies to drag, restitution, lateral wind, terminal velocity, anything where the engine gives you one global knob and your design wants twenty different settings on top of it.

When you hit that wall, take the per-entity loop back. Keep the physics body for contact detection; that part of SpriteKit is excellent. Just stop letting the engine integrate one axis of motion for you. The cost is a small struct, a `compactMap` over a weak-reference array, and a willingness to own the corner cases yourself.
