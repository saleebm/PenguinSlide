//
//  Tuning.swift
//  PenguinSlide
//
//  Gameplay-tuning constants and physics category bitmasks. Knobs are
//  grouped by subsystem to mirror README's "Where to tweak difficulty"
//  table: Penguin (input/feel), Icicle (physics), Chase (aim), Feel
//  (impact polish), Run (round-level pacing).
//

import CoreGraphics
import Foundation
import SpriteKit

enum Tuning {

    /// Penguin input + feel. Now a mutable struct (see `PenguinTuning`)
    /// so a future settings UI or debug menu can override knobs at
    /// runtime. Call sites stay the same: `Tuning.Penguin.maxSpeed` etc.
    /// First access loads any persisted overrides from UserDefaults.
    static var Penguin: PenguinTuning = .loadFromUserDefaults()

    /// Icicle physics: telegraph + per-icicle gravity.
    enum Icicle {
        /// Time an icicle spends cracking in place before falling.
        static let warningDuration: TimeInterval = 0.75
        /// Spawn cadence eases from start → end over `Run.rampDuration`.
        static let spawnIntervalStart: TimeInterval = 1.10
        static let spawnIntervalEnd:   TimeInterval = 0.34
        /// Scene-base gravity magnitude (pt/s²). Per-icicle gravity scale
        /// multiplies this. Calibrated so start-of-game fall ≈ 2.2 s and
        /// peak-difficulty fall ≈ 1.0 s across a typical iPhone screen.
        static let sceneGravity: CGFloat = 700
        /// Mean per-icicle gravity scale; lerps with the difficulty ramp.
        /// Bumped ~18% from the original 0.45 / 1.10 to preserve wall-clock
        /// fall time after the landing plane moved from `iceTopY` down to
        /// `iceLandingY` (the penguin's foot plane) — the fall distance grew
        /// by the same ~18%, and gravity scales linearly with distance for
        /// fixed fall time.
        static let gravityScaleStart:    CGFloat = 0.53
        static let gravityScaleEnd:      CGFloat = 1.30
        /// Per-icicle randomness around the mean, ±this fraction.
        static let gravityScaleVariance: CGFloat = 0.20
        /// Small downward kick so even the lightest icicles start moving.
        static let initialDownVelocity: CGFloat = 50
        /// Mass (kg) on the icicle's physics body. Used for restitution math
        /// when the icicle contacts the penguin; the manual gravity loop
        /// ignores mass.
        static let massKg: CGFloat = 0.5
        /// 0–1 bounciness of an icicle as it recoils off the penguin. The
        /// recoil itself is applied manually in `onIcicleHitPenguin`; this
        /// just colors any incidental physics resolution.
        static let restitution: CGFloat = 0.15
    }

    /// "Chase" aim algorithm — how aggressively spawns target the penguin.
    enum Chase {
        /// Fraction of "full ballistic lead" applied when aiming icicles.
        /// 1.0 = perfect aim; values <1 give the player room to react.
        static let leadFactor: CGFloat = 0.2
        /// Random spread around the predicted point, as a fraction of the ice
        /// strip width. Lerps from start (loose, early) to end (tight, late).
        static let jitterStart: CGFloat = 0.35
        static let jitterEnd:   CGFloat = 0.10
        /// Probability that a spawn ignores the penguin and goes uniformly
        /// random — keeps the field unpredictable even at peak chase tightness.
        static let randomChance: Double = 0.20
    }

    /// Visual feedback on impact: shatter shards + camera shake.
    enum Feel {
        /// Shard count interpolates from min (distant landings) to max
        /// (direct hits), keyed off the same falloff used by camera shake.
        static let shardCountMin: Int = 3
        static let shardCountMax: Int = 8
        /// Base launch speed; severity adds up to +shardSeverityBoost.
        static let shardLaunchSpeed: CGFloat = 220
        static let shardSeverityBoost: CGFloat = 0.30   // +30% pop on direct hits
        static let shardLifetime: TimeInterval = 0.6
        /// Peak camera shake amplitude when an icicle lands right on the penguin.
        static let shakePeakAmplitude: CGFloat = 8
        /// X-distance at which a landing produces zero shake / minimum shards.
        static let shakeRadius: CGFloat = 140
        /// Shard count when an icicle hits the penguin directly (separate
        /// from the landing-on-ice burst, which uses `shardCountMin/Max`).
        static let crackBurstShards: Int = 14
        /// Pop-speed multiplier for the penguin-contact crack burst.
        static let crackBurstSpeedScale: CGFloat = 1.6

        /// Under-icicle shadow grows + darkens as the icicle approaches the
        /// landing plane. Sells "this icicle is getting closer to the same
        /// plane the penguin is sliding on" without faking perspective scale
        /// on the icicle itself.
        static let shadowMinScale: CGFloat = 0.35
        static let shadowMaxScale: CGFloat = 1.0
        static let shadowMinAlpha: CGFloat = 0.15
        static let shadowMaxAlpha: CGFloat = 0.55

        /// Quick expanding ring at impact — reads as "the ice cracked here."
        /// Only fires when severity > `shockwaveMinSeverity` so distant
        /// landings don't strobe a ring every frame at peak spawn rate.
        static let shockwaveMaxScale: CGFloat = 3.0
        static let shockwaveDuration: TimeInterval = 0.25
        static let shockwaveMinSeverity: CGFloat = 0.2
    }

    /// Round-level pacing.
    enum Run {
        /// Seconds from start to peak difficulty.
        static let rampDuration: TimeInterval = 90.0
        /// Initial grace period with no spawns so the player can get oriented.
        static let gracePeriod: TimeInterval = 1.2
        /// Penguin is confined to this fraction of the screen width, centered.
        /// Sides show open water — squeezes the dodge corridor without hidden
        /// "instant death" zones. Icicles only spawn within this strip.
        static let playWidthFraction: CGFloat = 0.62
    }
}

/// Physics category bitmasks for contact-detection wiring.
struct Category {
    static let penguin: UInt32 = 1 << 0
    static let icicle:  UInt32 = 1 << 1
    static let shard:   UInt32 = 1 << 2
}
