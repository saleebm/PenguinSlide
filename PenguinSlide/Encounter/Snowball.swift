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

// MARK: - Flight knobs
//
// Encounter-local aim/feel knobs. They belong in Tuning.Encounter's
// Volley/Feel groups; they live here as an extension following the
// EncounterWorld / PapiAvatar precedent (fold into Tuning.swift whenever
// convenient). Call sites read `Tuning.Encounter.*` either way.
extension Tuning.Encounter {
    /// Snowball footprint (pt) at the camera plane, where the projector
    /// scale is exactly 1.0 — so this IS the full on-screen size a ball
    /// reaches as it arrives. Sized against `lateralHitRadius` (38) so
    /// the visual ball roughly matches the hit disc.
    static let snowballBaseSize: CGFloat = 64
    /// Fraction of full lead applied when aiming at the avatar — the
    /// `Chase.leadFactor` PATTERN with an encounter-local value
    /// (predicted = worldX + vx × flightTime × this). 1.0 = perfect
    /// intercept; < 1 leaves dodge room. Raise for meaner aim.
    static let snowballLeadFactor: CGFloat = 0.35
    /// Max |aim jitter| (world pt) around the predicted intercept, the
    /// `Chase.jitter*` role. Raise for a looser, more random volley.
    static let snowballAimJitter: CGFloat = 60
    /// Probability a throw carries lateral drift (a curving ball).
    static let snowballDriftChance: Double = 0.35
    /// Max |lateral drift| (world pt/s) for curving balls. Keep small
    /// relative to Papi's dodge speed so curves read as flavor, not aim.
    static let snowballDriftVxMax: CGFloat = 45
    /// Spin range (rad/s): each ball rolls in flight at a random rate in
    /// [min, max] with a random sign. Integrated MANUALLY (zRotation +=
    /// spin × dt) — no SKAction — so the spin freezes/resumes/pauses in
    /// exact lockstep with the flight integration.
    static let snowballSpinSpeedMin: CGFloat = 1.0
    static let snowballSpinSpeedMax: CGFloat = 4.0
    /// Height (world pt above the projected ground line) at which a ball
    /// ARRIVES at the camera plane — Papi's body, not his feet, so an
    /// on-target ball visually flies into the avatar.
    static let snowballArrivalHeight: CGFloat = 70
    /// Height (world pt) at which a ball SPAWNS: the monster's throwing
    /// hand. Derived from the SnowMonster hand calibration so the ball's
    /// projected spawn position coincides EXACTLY with
    /// `SnowMonster.snowballSpawnPoint()` (asserted by tests) — the
    /// projection of (worldX + handX·size, ground + handY·size) at
    /// zMonster is the hand point by linearity.
    static var snowballSpawnHeight: CGFloat {
        SnowMonster.handOffsetFraction.y * monsterBaseSize
    }
    /// zPosition band inside encounterRoot reserved for snowballs by the
    /// EncounterWorld z-stack doc (10..49, above the monster's slot at
    /// 10, below Papi's 50..59). Near = camera plane, far = zMonster.
    static let snowballZPositionNear: CGFloat = 48
    static let snowballZPositionFar: CGFloat = 12
}

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
    /// volley ramps zSpeed across an encounter.
    let zSpeed: CGFloat
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

/// Normalized flight progress: 0 at spawn, 1 at the camera plane.
/// Clamped on both ends so a ball integrated past z = 0 (or a degenerate
/// spawnZ) can never fold the height/shadow lerps back over — the
/// "no pop or fold-over at any z" acceptance guarantee.
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
