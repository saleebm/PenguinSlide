//
//  PenguinTuning.swift
//  PenguinSlide
//
//  Mutable, persisted tuning for the penguin's input and feel. Replaces
//  what used to be `enum Tuning.Penguin` of `static let` constants with an
//  instance type so a future settings UI or debug menu can override any
//  knob at runtime. Call sites still read `Tuning.Penguin.maxSpeed` etc.
//  unchanged — `Tuning.Penguin` is now a `static var PenguinTuning`.
//
//  Persistence is opt-in: defaults live in this file (matching the
//  pre-refactor values). Overrides round-trip through UserDefaults as
//  JSON. `loadFromUserDefaults` is called at the static var's first
//  access; mutate `Tuning.Penguin` and call `saveToUserDefaults()` to
//  persist. `resetUserDefaults()` clears overrides.
//

import CoreGraphics
import Foundation
import SpriteKit

struct PenguinTuning: Codable {

    // MARK: - Speed & input feel

    /// How fast the penguin slides at full tilt (points/sec).
    var maxSpeed: CGFloat = 1000
    /// Tilt response curve exponent. >1 makes small tilts gentler and
    /// rewards bigger tilts with disproportionately more speed.
    var tiltCurve: CGFloat = 1.5
    /// How quickly the penguin's velocity approaches the tilt-target.
    /// Lower = slippier; higher = snappier. Per second; ~10 is near-instant.
    var tiltResponseRate: CGFloat = 5.0
    /// Velocity decay rate when no tilt is held (asymmetric friction).
    /// Accel uses `tiltResponseRate` — this lets the penguin glide.
    var iceDecayRate: CGFloat = 0.7

    // MARK: - Body

    /// Collision circle radius as a fraction of visual penguin width.
    /// Sized so the hitbox reaches *above* the kinematic landing line
    /// (iceTopY) and into the icicle's fall path.
    var collisionRadiusFraction: CGFloat = 0.42
    /// Mass (kg). Used for the restitution math when a falling icicle
    /// contacts the penguin. The manual gravity integration ignores mass.
    var massKg: CGFloat = 4.0

    // MARK: - Lean

    /// Max lean angle in radians (~17°). Spring controls how it gets there.
    var leanMaxAngle: CGFloat = 0.30
    /// Spring stiffness ω₀² (rad²/s²). Higher = lean snaps to target faster.
    /// Sqrt(stiffness) is the undamped angular frequency.
    var leanStiffness: CGFloat = 60
    /// Damping ratio: 0 = perpetual oscillation, 1 = critically damped
    /// (no overshoot), >1 = overdamped. ~0.55 gives a satisfying brief
    /// overshoot.
    var leanDampingRatio: CGFloat = 0.55

    // MARK: - Health & i-frames

    /// Hit points at round start.
    var maxHealth: Int = 3
    /// Seconds of invulnerability after each hit. Subsequent contacts
    /// inside this window are absorbed (no damage) but still visibly
    /// recoil the icicle.
    var iFrameDuration: TimeInterval = 1.0
    /// Sprite-alpha flicker frequency during i-frames.
    var iFrameFlashHz: CGFloat = 8
    /// Sprite-alpha low value during the i-frame pulse. Softer than a
    /// hard flicker so the penguin stays readable while still signalling
    /// i-frames; the shield-ring carries most of the "protected" tell.
    var iFrameDimAlpha: CGFloat = 0.75

    // MARK: - Shield ring

    var shieldRingLineWidth: CGFloat = 3
    /// Half-period of the shield-ring scale+alpha pulse (full cycle is 2x).
    var shieldRingPulsePeriod: TimeInterval = 0.3

    // MARK: - Animation

    /// |vx| below this (pt/s) is "idle" — anything faster swaps to the
    /// slide loop. ~8% of `maxSpeed`. Hysteresis isn't necessary because
    /// the animations layer over the same procedural lean/bob, so a brief
    /// state flicker around the threshold isn't visually loud.
    var idleSlideThresholdPtPerSec: CGFloat = 60
    /// Playback rate for all penguin sprite-sheet animations. Matches the
    /// 8 fps that SpriteCook produced, so the motion reads at the speed
    /// the source frames were paced for.
    var animationFps: Double = 8

    // MARK: - Knockback

    /// Knockback impulse on hit, multiplied by `maxSpeed`. Applied to
    /// `vx` with sign so the penguin is pushed *away* from the impact.
    /// At 0.5 + maxSpeed=720, an accepted hit adds ±360 pt/s which the
    /// `iceDecayRate` smooths back within ~1 s.
    var knockbackImpulseScale: CGFloat = 0.5

    // MARK: - Visual constants (non-tunable)

    /// Shield-ring stroke colour. Cyan was chosen to contrast cleanly
    /// with the red damage flash so the two states read as different
    /// events at a glance. Not part of the Codable surface — SKColor
    /// doesn't bridge to JSON cleanly and this isn't a difficulty knob.
    var shieldRingColor: SKColor { Self.defaultShieldRingColor }
    private static let defaultShieldRingColor =
        SKColor(red: 0.5, green: 0.9, blue: 1.0, alpha: 1.0)

    // MARK: - Persistence

    // Versioned so a future schema break (renamed/removed field) can be
    // handled by bumping the key — old data is then ignored and defaults
    // re-seed the active tuning.
    private static let userDefaultsKey = "PenguinTuning.v1"

    /// Reads any persisted overrides; returns a default-valued struct
    /// when no override exists or decoding fails. Called automatically
    /// by `Tuning.Penguin`'s static initialiser.
    static func loadFromUserDefaults(_ defaults: UserDefaults = .standard) -> PenguinTuning {
        guard let data = defaults.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode(PenguinTuning.self, from: data)
        else { return PenguinTuning() }
        return decoded
    }

    /// Persist the current values. Future settings/debug UI calls this
    /// after mutating fields on `Tuning.Penguin`.
    func saveToUserDefaults(_ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.userDefaultsKey)
    }

    /// Wipe overrides. `Tuning.Penguin` won't update until reassigned
    /// from `loadFromUserDefaults()` — callers that want a live revert
    /// should reassign explicitly: `Tuning.Penguin = PenguinTuning()`.
    static func resetUserDefaults(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
    }
}
