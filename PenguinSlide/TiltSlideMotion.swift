//
//  TiltSlideMotion.swift
//  PenguinSlide
//
//  The shared tilt→velocity "ice feel" integrator (penguinslide-gyu.3).
//  Extracted verbatim from Penguin.update so the Snow Monster encounter
//  avatar (PapiAvatar, penguinslide-gyu.11) dodges with EXACTLY the same
//  dynamics as the normal-mode penguin — one home for the velocity math,
//  zero drift between modes.
//
//  Reads `Tuning.Penguin` knobs LIVE on every call (not captured at
//  init): the settings tilt-intensity slider mutates the UserDefaults-
//  backed `PenguinTuning` at runtime and the very next frame must honor
//  it, in both modes, by construction.
//

import CoreGraphics
import Foundation

/// Pure value type: owns the lateral velocity and the slide bounds.
/// No SpriteKit dependencies — fully unit-testable. Position integration
/// + wall clamping live in `integrate(x:dt:halfWidth:)` so the caller
/// keeps ownership of its node's position (single source of truth).
struct TiltSlideMotion {

    /// Current lateral velocity (pt/s). Mutated only by `update`,
    /// `integrate` (wall clamp zeroes it), `applyImpulse`, and `reset`.
    private(set) var vx: CGFloat = 0

    /// Inside edges of the lateral corridor the actor slides within.
    let leftBound: CGFloat
    let rightBound: CGFloat

    init(leftBound: CGFloat, rightBound: CGFloat) {
        self.leftBound = leftBound
        self.rightBound = rightBound
    }

    /// Per-frame velocity step. `tilt` is the input value in [-1, 1]
    /// (0 = no input).
    ///
    /// Ice-feel: tilt sets a target velocity, actual velocity glides toward
    /// it. Exponential approach so dt-independent — same feel at any frame
    /// rate. Curve preserves sign but rewards aggressive tilts non-linearly.
    mutating func update(dt: TimeInterval, tilt: CGFloat) {
        let curvedTilt = (tilt < 0 ? -1 : 1) * pow(abs(tilt), Tuning.Penguin.tiltCurve)
        let targetVx = curvedTilt * Tuning.Penguin.maxSpeed
        // Asymmetric friction: snappy when pressing, glidey when released.
        let rate: CGFloat = (tilt == 0) ? Tuning.Penguin.iceDecayRate : Tuning.Penguin.tiltResponseRate
        let alpha = 1 - exp(-rate * CGFloat(dt))
        vx += (targetVx - vx) * alpha
    }

    /// Advance a position by the current velocity and clamp it to the
    /// corridor, zeroing `vx` at the wall so no push-through accumulates.
    /// `halfWidth` is the actor's half-width inset from the bounds (the
    /// penguin passes `node.size.width * 0.42`). Returns the new x; the
    /// caller writes it to its node.
    mutating func integrate(x: CGFloat, dt: TimeInterval, halfWidth: CGFloat) -> CGFloat {
        let minX = leftBound + halfWidth
        let maxX = rightBound - halfWidth
        var newX = x + vx * CGFloat(dt)
        if newX < minX { newX = minX; vx = 0 }
        if newX > maxX { newX = maxX; vx = 0 }
        return newX
    }

    /// Knockback-style impulse: `direction` is ±1 (away from the impact).
    /// Magnitude reads the live knobs, matching Penguin.tryTakeHit's
    /// `vx += dir * maxSpeed * knockbackImpulseScale`.
    mutating func applyImpulse(direction: CGFloat) {
        vx += direction * Tuning.Penguin.maxSpeed * Tuning.Penguin.knockbackImpulseScale
    }

    mutating func reset() {
        vx = 0
    }
}
