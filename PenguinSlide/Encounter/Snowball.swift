//
//  Snowball.swift
//  PenguinSlide
//
//  Projectile model + pure flight math for the Snow Monster encounter
//  (penguinslide-gyu.13). A snowball is a COMMITTED trajectory: at the
//  monster's release it is aimed once (avatar position + partial lead +
//  jitter, clamped to the dodge corridor) and then only integrates
//  z toward the camera (plus an optional small lateral drift) — the
//  player dodges by moving OFF the line, goalkeeper-style, not by
//  outrunning a homing ball.
//
//  Snowballs carry NO SKPhysicsBody (KTD3): a ball at z = 800 can
//  overlap Papi at z = 0 in *screen* space, so 2D contact detection
//  would false-positive. Collision is a manual depth-window check owned
//  by the collision bead (gyu.14); this file is flight + presentation
//  math only. Everything here that isn't a node reference is pure
//  (CG types in, CG types out) so SnowballSystemTests can cover the
//  acceptance geometry without a running scene.
//

import CoreGraphics
import SpriteKit

// MARK: - Projectile model

/// One live snowball — mirrors IcicleSystem.FallingIcicle anatomy: weak
/// node references (SpriteKit owns node lifetime; a removed node drops
/// out of the per-frame compactMap sweep automatically) plus the value
/// state the manual integrator owns.
struct Snowball {
    weak var node: SKSpriteNode?
    weak var shadow: SKSpriteNode?
    /// Virtual depth (pt): spawnZ at the hand, 0 at the camera plane.
    var z: CGFloat
    /// Lateral world coordinate (camera-plane pt) — the committed line.
    var worldX: CGFloat
    /// Lateral drift (world pt/s); 0 for straight balls.
    let driftVx: CGFloat
    /// Depth speed (pt/s toward the camera) — per-ball because the
    /// volley ramps zSpeed across an encounter. `var`: the integrator
    /// accelerates it by `zAccel` every frame (penguinslide-sct).
    var zSpeed: CGFloat
    /// Constant depth acceleration (pt/s² toward the camera) — the ball
    /// launches at `zSpeed` and rushes as it approaches. Aim lead and
    /// the fairness tests use the exact accelerated flight time via
    /// `snowballFlightTime`, so the prediction math never goes stale.
    let zAccel: CGFloat
    /// Manual roll rate (rad/s, signed).
    let spinSpeed: CGFloat
    /// Depth this ball spawned at (flight-progress denominator).
    let spawnZ: CGFloat
    /// Set by the collision pass (gyu.14) when the ball is consumed
    /// (hit or scored dodge) — the flight sweep culls resolved balls
    /// without re-resolving them.
    var resolved = false
}

// MARK: - Pure flight math (unit-tested in SnowballSystemTests)

/// Committed aim line for a throw: the avatar's lateral position at
/// release plus a PARTIAL lead (`vx × flightTime × leadFactor` — the
/// `Tuning.Chase.leadFactor` pattern with encounter knobs) plus jitter,
/// clamped to the dodge corridor so every ball is dodgeable by
/// construction. `jitter` is passed in (not drawn here) so the math
/// stays deterministic for tests; the system draws it from its RNG.
func snowballAimWorldX(targetWorldX: CGFloat,
                       targetVx: CGFloat,
                       flightTime: TimeInterval,
                       leadFactor: CGFloat,
                       jitter: CGFloat,
                       corridorCenter: CGFloat,
                       corridorHalfWidth: CGFloat) -> CGFloat {
    let predicted = targetWorldX + targetVx * CGFloat(flightTime) * leadFactor + jitter
    return min(corridorCenter + corridorHalfWidth,
               max(corridorCenter - corridorHalfWidth, predicted))
}

/// Exact time for a ball to cover `spawnZ` from launch speed `zSpeed`
/// under constant `zAccel`: solves spawnZ = v₀·t + a·t²/2 for t (the
/// positive quadratic root). `zAccel ≈ 0` falls back to spawnZ / v₀.
/// THE single source of flight-time truth (penguinslide-sct): the aim
/// lead at spawn and the EncounterPaceTests dodgeability invariant both
/// call this, so acceleration can never silently break either.
func snowballFlightTime(spawnZ: CGFloat, zSpeed: CGFloat, zAccel: CGFloat) -> TimeInterval {
    let z = max(spawnZ, 0)
    let v0 = max(zSpeed, 1)
    guard abs(zAccel) > 0.001 else { return TimeInterval(z / v0) }
    // (-v0 + sqrt(v0² + 2·a·z)) / a — discriminant clamped so a (mis-
    // tuned) deceleration that would never arrive degrades to "arrives
    // when v reaches 0" instead of NaN.
    let disc = max(v0 * v0 + 2 * zAccel * z, 0)
    return TimeInterval((-v0 + sqrt(disc)) / zAccel)
}

/// Normalized flight progress: 0 at spawn, 1 at the camera plane.
/// Clamped on both ends so a ball integrated past z = 0 (or a degenerate
/// spawnZ) can never fold the height/shadow lerps back over — the
/// "no pop or fold-over at any z" acceptance guarantee.
/// POSITION-based on purpose: under acceleration (penguinslide-sct) the
/// height arc and shadow stay geometrically correct per-z, and in
/// wall-clock time they rush near arrival — the intended read.
func snowballFlightProgress(z: CGFloat, spawnZ: CGFloat) -> CGFloat {
    guard spawnZ > 0 else { return 1 }
    return min(1, max(0, 1 - z / spawnZ))
}

/// Height of the ball above the projector's ground line (world pt),
/// lerping hand-height at spawn down to body-height at arrival. The
/// caller scales it by the projection factor before adding to screen y.
func snowballFlightHeight(progress: CGFloat) -> CGFloat {
    let p = min(1, max(0, progress))
    return Tuning.Encounter.snowballSpawnHeight
        + (Tuning.Encounter.snowballArrivalHeight - Tuning.Encounter.snowballSpawnHeight) * p
}

/// Depth-keyed draw order: `near − z × epsilon` (the plan's formula)
/// with epsilon spanning the reserved snowball band over [0, zMonster],
/// clamped so an out-of-range z can never escape the band. Nearer balls
/// always draw over farther ones; the matching shadow rides just below
/// its ball's slot (see the system's layout pass).
func snowballZPosition(z: CGFloat) -> CGFloat {
    let near = Tuning.Encounter.snowballZPositionNear
    let far = Tuning.Encounter.snowballZPositionFar
    let epsilon = (near - far) / Tuning.Encounter.zMonster
    return min(near, max(far, near - z * epsilon))
}
