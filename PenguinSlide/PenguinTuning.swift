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

    /// Inclusive bounds for the derived top-speed value. Lower bound feels
    /// like a tutorial pace; upper bound is challenging without making
    /// the play-corridor clamp dominate the feel.
    static let speedRange: ClosedRange<CGFloat> = 850...1950
    /// Default top speed for fresh installs (kept as a fallback for
    /// migration math; new installs seed from `tiltIntensityDefault`).
    static let speedDefault: CGFloat = 1125

    /// Normalised "feel" knob the Settings slider exposes. 0 = calm,
    /// 1 = wild. Drives `maxSpeed`, `tiltResponseRate`, and `tiltCurve`
    /// in lockstep so the input always feels proportionate at any setting.
    static let tiltIntensityRange: ClosedRange<CGFloat> = 0...1
    /// Default tilt-intensity. Inverse of `derived(from:)` at speed≈1100
    /// to preserve the pre-refactor feel for fresh installs.
    static let tiltIntensityDefault: CGFloat = 0.25

    /// Persisted feel position. Source of truth for the derived trio
    /// below; mutate via `applyTiltIntensity(_:)` so the derived fields
    /// stay coherent.
    var tiltIntensity: CGFloat = PenguinTuning.tiltIntensityDefault
    /// How fast the penguin slides at full tilt (points/sec). Derived
    /// from `tiltIntensity`.
    var maxSpeed: CGFloat = PenguinTuning.speedDefault
    /// Tilt response curve exponent. >1 makes small tilts gentler and
    /// rewards bigger tilts with disproportionately more speed. Derived
    /// from `tiltIntensity` (more linear as intensity rises).
    var tiltCurve: CGFloat = 1.5
    /// How quickly the penguin's velocity approaches the tilt-target.
    /// Lower = slippier; higher = snappier. Derived from `tiltIntensity`
    /// (snappier as intensity rises) so the top end doesn't feel sluggish.
    var tiltResponseRate: CGFloat = 5.0
    /// Velocity decay rate when no tilt is held (asymmetric friction).
    /// Accel uses `tiltResponseRate` — this lets the penguin glide.
    var iceDecayRate: CGFloat = 0.7

    /// Pure mapping from a 0...1 intensity to the three derived fields.
    /// Bumping intensity raises top speed *and* keeps inputs responsive
    /// at that speed — neither dimension wins at the other's expense.
    static func derived(from t: CGFloat) -> (maxSpeed: CGFloat,
                                              tiltResponseRate: CGFloat,
                                              tiltCurve: CGFloat) {
        let c = max(0, min(1, t))
        return (maxSpeed:         850.0 + c * 1100.0,
                tiltResponseRate: 4.0   + c * 2.0,
                tiltCurve:        1.5   - c * 0.2)
    }

    /// Set intensity and recompute the derived trio together. Settings
    /// UI and the migration path both go through here, so the three
    /// fields can never drift out of sync with `tiltIntensity`.
    mutating func applyTiltIntensity(_ t: CGFloat) {
        let d = Self.derived(from: t)
        tiltIntensity = max(0, min(1, t))
        maxSpeed = d.maxSpeed
        tiltResponseRate = d.tiltResponseRate
        tiltCurve = d.tiltCurve
    }

    // MARK: - Body

    /// Collision circle radius as a fraction of visual penguin width.
    /// Sized so the hitbox reaches up into the icicle's fall path between
    /// the spawn line and `iceLandingY` (the penguin's foot plane the
    /// icicles now crash onto — see plan: the-ice-looks-like-ticklish-reddy).
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

    // MARK: - Codable migration

    // Default memberwise init re-declared so the custom `init(from:)`
    // below doesn't shadow it. Routes through `applyTiltIntensity` so the
    // derived trio (maxSpeed/rate/curve) stays coherent with the current
    // `derived(from:)` formula even when the var-level defaults drift.
    init() { applyTiltIntensity(Self.tiltIntensityDefault) }

    // Migration path: pre-feel-knob data has `maxSpeed` but no
    // `tiltIntensity`. We synthesise intensity from the stored speed
    // using the inverse of `derived(from:)`, then route through
    // `applyTiltIntensity` so the three derived fields end up coherent
    // (the on-disk `tiltResponseRate`/`tiltCurve`, if any, are
    // intentionally overwritten — they were never user-tunable).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        iceDecayRate     = (try? c.decode(CGFloat.self, forKey: .iceDecayRate))     ?? iceDecayRate
        collisionRadiusFraction = (try? c.decode(CGFloat.self, forKey: .collisionRadiusFraction)) ?? collisionRadiusFraction
        massKg           = (try? c.decode(CGFloat.self, forKey: .massKg))           ?? massKg
        leanMaxAngle     = (try? c.decode(CGFloat.self, forKey: .leanMaxAngle))     ?? leanMaxAngle
        leanStiffness    = (try? c.decode(CGFloat.self, forKey: .leanStiffness))    ?? leanStiffness
        leanDampingRatio = (try? c.decode(CGFloat.self, forKey: .leanDampingRatio)) ?? leanDampingRatio
        maxHealth        = (try? c.decode(Int.self,     forKey: .maxHealth))        ?? maxHealth
        iFrameDuration   = (try? c.decode(TimeInterval.self, forKey: .iFrameDuration)) ?? iFrameDuration
        iFrameFlashHz    = (try? c.decode(CGFloat.self, forKey: .iFrameFlashHz))    ?? iFrameFlashHz
        iFrameDimAlpha   = (try? c.decode(CGFloat.self, forKey: .iFrameDimAlpha))   ?? iFrameDimAlpha
        shieldRingLineWidth   = (try? c.decode(CGFloat.self, forKey: .shieldRingLineWidth))   ?? shieldRingLineWidth
        shieldRingPulsePeriod = (try? c.decode(TimeInterval.self, forKey: .shieldRingPulsePeriod)) ?? shieldRingPulsePeriod
        idleSlideThresholdPtPerSec = (try? c.decode(CGFloat.self, forKey: .idleSlideThresholdPtPerSec)) ?? idleSlideThresholdPtPerSec
        animationFps          = (try? c.decode(Double.self,  forKey: .animationFps))          ?? animationFps
        knockbackImpulseScale = (try? c.decode(CGFloat.self, forKey: .knockbackImpulseScale)) ?? knockbackImpulseScale

        if let t = try? c.decode(CGFloat.self, forKey: .tiltIntensity) {
            applyTiltIntensity(t)
        } else if let oldMax = try? c.decode(CGFloat.self, forKey: .maxSpeed) {
            // Frozen against the v1 anchors (speed range 800..2000) so a
            // user who set maxSpeed under the original formula lands on
            // the same slider position after `derived(from:)` is retuned.
            applyTiltIntensity((oldMax - 800.0) / 1200.0)
        } else {
            applyTiltIntensity(Self.tiltIntensityDefault)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case tiltIntensity, maxSpeed, tiltCurve, tiltResponseRate, iceDecayRate
        case collisionRadiusFraction, massKg
        case leanMaxAngle, leanStiffness, leanDampingRatio
        case maxHealth, iFrameDuration, iFrameFlashHz, iFrameDimAlpha
        case shieldRingLineWidth, shieldRingPulsePeriod
        case idleSlideThresholdPtPerSec, animationFps
        case knockbackImpulseScale
    }

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
