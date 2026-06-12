//
//  Tuning.swift
//  PenguinSlide
//
//  Gameplay-tuning constants and physics category bitmasks. Knobs are
//  grouped by subsystem to mirror README's "Where to tweak difficulty"
//  table: Penguin (input/feel), Icicle (physics), Chase (aim), Feel
//  (impact polish), Encounter (snow-monster dodge sequence), Run
//  (round-level pacing).
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

    /// Skill-based scoring (penguinslide-y7f). A "close-call" is a *survived*
    /// icicle landing — reaching the landing code already means the penguin
    /// dodged it — whose `Feel.shakeRadius`-derived `severity` clears
    /// `closeCallSeverity`. Severity is the single source of truth for "how
    /// close"; there is intentionally no separate close-call radius.
    enum Score {
        /// Passive survival points per second. Unchanged value; relocated
        /// from the literal `10` in GameScene's score line.
        static let survivalRate: CGFloat = 10
        /// A survived landing with `severity >= this` counts as a scored
        /// close-call. 0.5 ≈ within 70pt (half of `Feel.shakeRadius`).
        static let closeCallSeverity: CGFloat = 0.5
        /// Base points for a close-call, before severity and combo scaling.
        static let closeCallBase: Int = 50
        /// Max seconds between close-calls to keep a combo streak alive.
        static let comboWindow: TimeInterval = 2.5
        /// Combo multiplier ceiling so a long streak can't run away.
        static let comboMaxMultiplier: CGFloat = 5.0
    }

    /// Visual feedback on impact: shatter shards + camera shake.
    enum Feel {
        /// Shard count interpolates from min (distant landings) to max
        /// (direct hits), keyed off the same falloff used by camera shake.
        static let shardCountMin: Int = 2
        static let shardCountMax: Int = 5
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
        static let crackBurstShards: Int = 8
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

        // Animated shatter burst (SpriteCook spritesheet).
        static let shatterAnimFps: CGFloat = 14      // N frames ≈ N/14 s
        static let shatterBaseSize: CGFloat = 110    // pt, full-severity burst footprint
        static let shatterMinScale: CGFloat = 0.55   // severity floor for burst size

        /// Landings play their shatter clip at every distance, with linear
        /// volume falloff from `landingAudioMaxVolume` at the penguin's x
        /// down to `landingAudioMinVolume` at `landingAudioFalloffRadius`
        /// and beyond. Falloff radius is intentionally much larger than
        /// `shakeRadius` — you can hear an icicle hit across the strip even
        /// though it can't shake the camera from that far. Min volume is a
        /// nonzero floor so very distant landings still produce a faint
        /// tick rather than going silent.
        static let landingAudioFalloffRadius: CGFloat = 600
        static let landingAudioMinVolume: Float = 0.025
        static let landingAudioMaxVolume: Float = 0.22
    }

    /// Snow Monster encounter (penguinslide-gyu): random pseudo-3D dodge
    /// sequence. Grouped TRIGGER → VOLLEY → GEOMETRY → FEEL. Values are
    /// starting points — the device-tuning bead owns final numbers. Plain
    /// `static let` constants by design: only `Tuning.Penguin` gets the
    /// mutable-runtime-struct treatment, and encounter knobs are not
    /// settings-exposed. Note there is intentionally NO `Category` bitmask
    /// for snowballs — encounter collision is fully manual (snowballs carry
    /// no physics bodies; depth-aware hit tests live in the update loop).
    enum Encounter {

        // MARK: Trigger

        /// Run time (s) before the first encounter can roll. Raise for a
        /// longer guaranteed-icicles-only opening; lower to let the monster
        /// show up sooner.
        static let minRunTime: TimeInterval = 20.0
        /// Minimum seconds between the end of one encounter and the next
        /// becoming eligible. Raise to space encounters out; lower for
        /// back-to-back pressure.
        static let minSpacing: TimeInterval = 45.0
        /// Probability rolled once per eligible second that an encounter
        /// fires. Raise to make encounters more frequent (0.04 ≈ expected
        /// fire within ~25 eligible seconds); lower to make them rarer.
        static let perSecondChance: Double = 0.04
        /// Hard cap on encounters per run. Raise for more monster time in
        /// long runs; lower (to 1) for a once-per-run set piece.
        static let maxPerRun: Int = 2
        /// Score-bracket rate limit (gyu.17 amendment): the random cadence
        /// may fire AT MOST ONCE per this many score points — bracket =
        /// floor(score / triggerScoreBracket), and a fire consumes the
        /// bracket until restart. Raise to space random encounters further
        /// apart on the score axis; the manual settings-button entry and
        /// the debugForceEncounter hook bypass this gate entirely.
        static let triggerScoreBracket: Int = 1000
        /// Lateral danger window (pt) around the penguin: while any FALLING
        /// icicle's x is within this distance, the random trigger is
        /// ineligible — the intro sweep clears all icicles, so firing with
        /// one bearing down would erase a deserved hit (fairness rule).
        /// Raise for a more conservative trigger; lower to allow encounters
        /// to interrupt closer shaves.
        static let triggerDangerWindow: CGFloat = 160

        // MARK: Pace (penguinslide-fr7)

        /// MASTER encounter-pace multiplier — the ONE number to iterate on
        /// for overall intensity (penguinslide-fr7, Mina device feedback:
        /// "pace too slow"). Scales the speed knobs UP (`zSpeedStart/End`,
        /// `groundScrollSpeed`) and the time knobs DOWN
        /// (`throwIntervalStart/End`, `telegraphDuration`) together, so
        /// ball flight, volley cadence, wind-up reads, and the forward-
        /// slide ground rush all speed up coherently. 1.0 reproduces the
        /// original 2026-06-11 device build; 1.3 ≈ 30% faster (first-pass
        /// answer to the feedback). Tune HERE, not on the base values
        /// below — `EncounterPaceTests` enforces the one-knob contract
        /// and proves dodgeability at whatever pace ships.
        static let paceScale: CGFloat = 1.3

        /// Pace-1.0 BASE values the derived knobs below scale from. Edit
        /// these only to change the encounter's relative *shape* (e.g.
        /// cadence vs. ball speed); edit `paceScale` to change how fast
        /// the whole thing plays.
        static let baseThrowIntervalStart: TimeInterval = 1.6
        static let baseThrowIntervalEnd:   TimeInterval = 0.9
        static let baseZSpeedStart: CGFloat = 260
        static let baseZSpeedEnd:   CGFloat = 420
        static let baseTelegraphDuration: TimeInterval = 0.75

        // MARK: Volley

        /// Snowballs per encounter, lerped start → end by the *run's*
        /// difficulty progress at trigger time (mirrors
        /// `IcicleSystem.progress`). Raise for longer volleys.
        static let volleyCountStart: Int = 6
        static let volleyCountEnd:   Int = 12
        /// Seconds between throws, lerped by run progress at trigger time.
        /// Lower = denser volley, less recovery time between balls.
        /// Derived: base / `paceScale` (≈ 1.23 / 0.69 s at pace 1.3).
        static let throwIntervalStart: TimeInterval = baseThrowIntervalStart / TimeInterval(paceScale)
        static let throwIntervalEnd:   TimeInterval = baseThrowIntervalEnd / TimeInterval(paceScale)
        /// Snowball depth speed (virtual depth units/s toward the camera),
        /// lerped by run progress at trigger time. Raise for faster balls
        /// and shorter reaction windows. Derived: base × `paceScale`
        /// (= 338 / 546 at pace 1.3, so a ball covers `zMonster` in
        /// ~2.7 s at start speed, ~1.6 s at end speed).
        static let zSpeedStart: CGFloat = baseZSpeedStart * paceScale
        static let zSpeedEnd:   CGFloat = baseZSpeedEnd * paceScale

        // MARK: Geometry

        /// Monster's depth station (virtual pt from the camera plane).
        /// Raise to push the monster further away (smaller on screen,
        /// longer ball flight at a given z-speed); lower to loom closer.
        static let zMonster: CGFloat = 900
        /// Perspective projection constant: screenScale = focal / (focal + z).
        /// Raise for a flatter, telephoto look (less size change over depth);
        /// lower for a more aggressive wide-angle depth exaggeration.
        static let focal: CGFloat = 300
        /// Horizon line height as a fraction of scene height. Raise to see
        /// more ground plane; lower for a flatter, closer-to-edge-on view.
        /// The mountain backdrop pins its in-art horizon row onto this line
        /// (`backdropHorizonInArtFraction`, EncounterWorld.swift), so the
        /// painted vista tracks the projected geometry automatically.
        static let horizonYFraction: CGFloat = 0.62
        /// Papi's screen-y plane (z = 0 station) as a fraction of scene
        /// height. Raise to lift the avatar toward the horizon; lower to
        /// keep him near the bottom edge.
        static let papiPlaneYFraction: CGFloat = 0.22
        /// Depth band (virtual pt) around Papi's plane inside which a
        /// snowball can connect. Raise for a thicker hit slab (harder to
        /// thread between frames, more forgiving for the monster); lower
        /// for a stricter "exactly at the camera plane" hit.
        static let depthWindow: CGFloat = 40
        /// Fraction of `papiBaseSize` occupied by Papi's actual body in
        /// the rear-view sheet (the sprite frame carries transparent
        /// margins around the silhouette). Used to derive the hit radius.
        static let papiBodyWidthFraction: CGFloat = 0.62
        /// Fraction of `snowballBaseSize` that is solid ball (vs. the
        /// fringe pixels around it) — the part that should count on
        /// contact.
        static let snowballCoreFraction: CGFloat = 0.75
        /// Lateral distance (world units = screen points at z = 0) inside
        /// which an in-window ball hits Papi. DERIVED from the visual
        /// geometry — Papi's body half-width plus the ball's core radius —
        /// so a ball that visibly overlaps the penguin always registers
        /// as a hit (penguinslide-bo8: the old hand-tuned 38 pt covered
        /// only the middle ~40% of the 180 pt sprite, so balls smacking
        /// Papi's shoulders scored "+n" close-call dodges — which read as
        /// "catching" on device). SnowballCollisionTests pins this
        /// relation; tune difficulty via the fractions or `paceScale`,
        /// never by re-hardcoding the radius.
        static let lateralHitRadius: CGFloat =
            papiBaseSize * papiBodyWidthFraction / 2
            + snowballBaseSize * snowballCoreFraction / 2
        /// Lateral band for dodge *severity* scoring, distinct from
        /// `lateralHitRadius`: severity is measured at the miss boundary,
        /// so sharing the hit knob would score every dodge 0. A few
        /// multiples of the hit radius (precedent: `Score.closeCallSeverity`
        /// band vs `Feel.shakeRadius` being wider than the hit zone).
        /// Raise to count farther misses as "close"; lower so only
        /// hair's-breadth dodges score high severity.
        static let severityRadius: CGFloat = 150
        /// Half-width (world units) of Papi's dodge corridor at z = 0.
        /// Raise for more room to maneuver; lower for a tighter corridor
        /// where dodges demand earlier commitment.
        static let papiLateralRange: CGFloat = 280
        /// Monster sprite footprint (pt) at scale 1.0 — i.e. the size it
        /// WOULD render at the camera plane. On screen at `zMonster` it
        /// draws at baseSize × focal/(focal+zMonster) (≈ 90 pt with the
        /// shipped knobs). Raise to bulk the monster up; lower to shrink
        /// it without moving its depth station.
        static let monsterBaseSize: CGFloat = 360

        // MARK: Feel

        /// Monster wind-up (s) before each throw — the cue the player
        /// reacts to, same role as the icicle crack warning. Raise for
        /// easier reads; lower for snappier, harder volleys.
        /// Derived: base / `paceScale` (≈ 0.58 s at pace 1.3).
        static let telegraphDuration: TimeInterval = baseTelegraphDuration / TimeInterval(paceScale)
        /// Base points per dodged snowball, before severity scaling.
        /// Raise to make encounters more score-lucrative per ball.
        static let dodgeBonusBase: Int = 25
        /// Flat bonus for surviving the full volley (replaces the survival
        /// drip paused during the encounter). Raise to reward completion
        /// more heavily relative to per-dodge income.
        static let volleyCompletionBonus: Int = 250
        /// Intro transition length (s): camera/world swing into the
        /// rear-view scene. Raise for a more cinematic entrance; lower to
        /// get the player into the dodge faster. Trimmed 1.6 → 1.2
        /// (penguinslide-fr7) so the encounter gets to the action sooner;
        /// deliberately NOT on `paceScale` — it's a one-shot transition
        /// beat, not part of the dodge loop's intensity.
        static let introDuration: TimeInterval = 1.2
        /// Outro transition length (s) back to the side-view world.
        /// This is the CROSSFADE segment only — the win outro's total
        /// length is `meltDuration + outroDuration` (melt beat first,
        /// then the crossfade).
        static let outroDuration: TimeInterval = 1.2
        /// Win-outro melt beat (s): the defeated monster slumps slowly
        /// into a snow puddle for this long before the crossfade back to
        /// the side view begins (penguinslide-gyu.18 amendment — the exit
        /// waits for the melt). The SnowMonsterMelt sheet is stretched
        /// across this duration (timePerFrame = duration / frameCount).
        /// Raise for a slower, more savored melt; lower to get back to
        /// the run faster.
        static let meltDuration: TimeInterval = 2.0
        /// Quiet seconds after returning to normal mode before icicle
        /// spawns resume. Raise for a longer breather; lower to resume
        /// pressure immediately.
        static let postEncounterGrace: TimeInterval = 1.0
        /// Lateral lane shuffle between throws (monster slides to a new
        /// lane for variety). DEFAULT OFF for v1 fairness tuning — a
        /// stationary monster keeps every telegraph read identical.
        static let monsterShuffleEnabled = false
        /// Max |offset| (world units) from the home lane per shuffle.
        static let monsterShuffleRange: CGFloat = 120

        // MARK: Audio (penguinslide-gyu.28)

        /// bg_music bed volume while inside the encounter (ducked at
        /// intro start, restored at the outro / encounter death /
        /// restart). The normal-play baseline is 0.18 (GameScene); the
        /// duck clears sonic room for the encounter sting + ambience.
        /// Raise toward 0.18 for a subtler duck; 0 silences the bed
        /// entirely during encounters.
        static let bgDuckVolume: Float = 0.05
        /// Duck ramp (s) at intro start. Short, so the sting lands on an
        /// already-quiet bed; raise for a gentler dip.
        static let bgDuckRamp: TimeInterval = 0.3
        /// Restore ramp (s) back to the baseline — outro win, encounter
        /// death, and triggerGameOver all use it (restart snaps with 0).
        /// A touch longer than the duck so the bed swells back in
        /// instead of popping.
        static let bgRestoreRamp: TimeInterval = 0.5
        /// Encounter ambience loop volume (encounter_ambience.caf, the
        /// bed's stand-in while bg_music is ducked). Keep in the bed's
        /// neighborhood (bg 0.18, shatter ceiling 0.22) so SFX still
        /// cut through.
        static let ambienceVolume: Float = 0.14

        // MARK: Audio — encounter SFX (penguinslide-gyu.27)
        //
        // All five clips live in PenguinSlide/Sounds/ as .caf
        // (afconvert -f caff -d LEI16 from the delivered ElevenLabs
        // takes) and every node/action creation is guarded on
        // Bundle.main.url — a checkout without the staged audio runs
        // silent-but-safe, never crashes. Mix discipline: bg bed 0.18,
        // shatter ceiling 0.22 — these sit in that neighborhood so the
        // encounter never drowns the established mix.

        /// snowball_throw.caf — the monster's release whoosh
        /// (SKAudioNode stop/play restart, fired at the release signal
        /// in SnowMonsterEncounterSystem.releaseBall).
        static let throwWhooshVolume: Float = 0.25
        /// snowball_impact.caf at full force (accepted hit — HP lost).
        /// The punchiest clip in the encounter; a touch over the
        /// shatter ceiling reads right because it is the failure beat.
        static let impactVolume: Float = 0.30
        /// Multiplier on `impactVolume` when i-frames absorbed the hit
        /// (accepted == false) — the audio mirror of the soft-FX
        /// treatment (smaller burst, no shake, light haptic).
        static let impactAbsorbedScale: Float = 0.5
        /// dodge_whoosh.caf volume at severity 0 (a wide, easy dodge).
        static let dodgeWhooshVolumeMin: Float = 0.08
        /// dodge_whoosh.caf volume at severity 1 (a hair's-breadth
        /// shave). Close shaves are LOUDER — severity lerps min → max.
        static let dodgeWhooshVolumeMax: Float = 0.22
        /// snowball_flyby.caf — the past-the-ear layer that plays ON TOP
        /// of the dodge whoosh, but only for near-misses at/above this
        /// severity (∈ [0, 1]; 1 reserves it for perfect shaves, >1
        /// silences it). Deliberately its own knob, decoupled from
        /// `dodgeHapticSeverity`.
        static let flybySeverityMin: CGFloat = 0.5
        /// snowball_flyby.caf playback volume.
        static let flybyVolume: Float = 0.18

        /// Seconds for the shuffle slide between lanes.
        static let monsterShuffleDuration: TimeInterval = 0.5
        /// Trim factor on `Tuning.Penguin.leanMaxAngle` for the rear-view
        /// avatar's lean spring (gyu.26). The final PapiRearSlide sheet
        /// bakes subtle left/center/right lean frames into the loop, so
        /// applying the full side-view lean angle ON TOP of the baked
        /// lean over-rotates the silhouette. The spring recipe and the
        /// stiffness/damping knobs stay shared with the penguin (never
        /// fork the spring) — only the target amplitude is scaled.
        /// 1.0 = identical lean to the side view; lower if the combined
        /// (baked + zRotation) lean still reads broken on device.
        static let papiLeanScale: CGFloat = 0.6
    }

    /// Round-level pacing.
    enum Run {
        /// Seconds from start to peak difficulty.
        static let rampDuration: TimeInterval = 90.0
        /// Initial grace period with no spawns so the player can get oriented.
        static let gracePeriod: TimeInterval = 1.2
        /// Penguin is confined to this fraction of the screen width, centered.
        /// Sides show marginal gutters of open water so the shore edges read as
        /// a platform and the field plays tight; icicles only spawn within this
        /// strip. (v1 was 0.62; widened to 0.96; 0.82 restores a tighter field.)
        static let playWidthFraction: CGFloat = 0.82
    }
}

/// Physics category bitmasks for contact-detection wiring.
struct Category {
    static let penguin: UInt32 = 1 << 0
    static let icicle:  UInt32 = 1 << 1
    static let shard:   UInt32 = 1 << 2
}
