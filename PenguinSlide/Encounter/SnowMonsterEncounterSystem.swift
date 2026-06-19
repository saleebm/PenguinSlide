//
//  SnowMonsterEncounterSystem.swift
//  PenguinSlide
//
//  Orchestrator for the Snow Monster encounter (penguinslide-gyu.13:
//  skeleton + snowball projectile loop). Mirrors IcicleSystem's anatomy:
//  array-tracked live projectiles, per-frame MANUAL integration (no
//  physics bodies — KTD3), cached FX textures, callbacks out. This file
//  replaces the no-op stub that previously lived at the bottom of
//  GameScene.swift; GameScene's call sites (`update(dt:tilt:)` during
//  `.encounter`, `reset()` from `restart()`) bind unchanged.
//
//  ## What lives here NOW (gyu.13) vs. the dependent beads
//
//  - Snowball flight + presentation: spawn/aim at the monster's release
//    signal, depth integration, perspective scaling through the shared
//    DepthProjector, ground shadows, depth-sorted draw order, manual
//    spin. gyu.13.
//  - Depth-window collision + dodge severity (gyu.14, THIS file): fully
//    manual, evaluated inside the flight sweep (KTD3 — there are no
//    physics bodies on snowballs, so `didBegin` can never see them).
//    The math is in the pure static `resolve` / `dodgeSeverity` helpers
//    below; `Snowball.resolved` is the exactly-once flag; hits/dodges
//    route OUT via `onSnowballHit` / `onDodge` so the system stays
//    score- and HP-agnostic (IcicleSystem.onCloseCall's precedent).
//  - Volley orchestration (gyu.15, THIS file): one encounter is one
//    VOLLEY — N balls thrown at a cadence, count/interval/zSpeed all
//    lerped from the run's difficulty progress at trigger time
//    (`volleyPlan`). The per-frame cycle drives the monster
//    telegraph → throw → release-spawns-the-ball → recover loop on the
//    system's OWN dt clock (manual integration doctrine — SKAction
//    completions are visuals-only seams with dt-clock watchdogs, so a
//    volley terminates deterministically even if an action stalls).
//    Completion (`onVolleyComplete`) fires only when the LAST ball
//    RESOLVES (hit or dodge) — never at the last throw; the
//    outstanding-ball accounting (`outstandingBalls`: +1 per spawn,
//    −1 per ball retired) is the detector. Outcome INTERPRETATION
//    stays in GameScene (win → outro, HP exhausted → game over):
//    subsystems detect, the orchestrating scene decides.
//  - Impact/dodge FX + haptics → gyu.16 (EncounterFX). Encounter SFX
//    (throw whoosh, impact, dodge whoosh, flyby) → gyu.27, the Audio
//    section below; the intro roar one-shot lives in GameScene.
//
//  ## Allocation discipline (acceptance)
//
//  Nodes are created PER THROW only (a volley is small); the per-frame
//  flight loop creates zero nodes and zero textures — the shadow texture
//  is rendered once and shared (IcicleSystem.shadowTexture's approach),
//  ball sprites reuse the SpriteCatalog cached texture. The sweep is the
//  same compactMap pattern as IcicleSystem's falling arrays.
//

import SpriteKit
import UIKit

// MARK: - Collision/dodge resolution (gyu.14)

/// Outcome of one frame's manual depth-window test for one snowball.
/// Produced by the pure `SnowMonsterEncounterSystem.resolve` helper; a
/// ball resolves EXACTLY ONCE — the system stops calling `resolve` for a
/// ball the moment it returns non-`.none` (`Snowball.resolved`).
enum SnowballResolution: Equatable {
    /// Still in flight: outside the hit slab, or inside it but laterally
    /// clear, and the camera plane not yet crossed.
    case none
    /// Connected with Papi: inside the depth window AND laterally within
    /// `lateralHitRadius`. The ball is consumed this frame.
    case hit
    /// Crossed the camera plane (z ≤ 0) without ever connecting — a
    /// scored dodge. `severity` ∈ [0, 1]: 1 ≈ hair's-breadth shave at the
    /// hit boundary, 0 = missed by `severityRadius` or more. Measured AT
    /// the crossing frame.
    case dodged(severity: CGFloat)
}

final class SnowMonsterEncounterSystem {

    /// Gap between a ball's zPosition and its ground shadow's: the
    /// shadow rides JUST below its own ball in the draw order, so the
    /// pair stays depth-sorted as a unit (a nearer ball + shadow draw
    /// over a farther pair, never interleaved).
    static let shadowZPositionOffset: CGFloat = 0.5

    // MARK: - Configuration (wired by GameScene's encounter beads)

    /// Visual parent for everything this system spawns — GameScene's
    /// `encounterRoot`, so the encounter world shows/hides as one
    /// toggle. Weak: the scene owns the node tree (IcicleSystem's
    /// convention).
    private weak var parent: SKNode?
    /// Shared geometry authority. All snowball placement goes through
    /// `project` so balls, monster, ground bands, and Papi agree.
    private var projector: DepthProjector?

    /// Live projectiles. `private(set)` so tests and the volley bead
    /// (gyu.15) can read flight state; all mutation stays in this file's
    /// spawn/sweep/reset.
    private(set) var snowballs: [Snowball] = []

    // MARK: - Collision/dodge seams (gyu.14)

    /// Live lateral position of the dodge target (Papi) in encounter
    /// world units — wired by GameScene's intro bead (gyu.17,
    /// `ensureEncounterContent`) to `{ avatar.worldX }`. While nil (only
    /// before the first intro's midpoint swap builds the avatar, or in
    /// pure-logic tests) the collision pass is skipped entirely and
    /// balls simply fly through the camera plane and cull, exactly the
    /// pre-gyu.14 behavior. The volley cycle also aims throws at this
    /// (falling back to the corridor center when nil).
    var papiWorldXProvider: (() -> CGFloat)?

    /// Live lateral velocity of the dodge target (pt/s) — the partial
    /// aim lead's input (`snowballAimWorldX`). nil reads as a
    /// stationary target (lead contributes nothing).
    var papiVxProvider: (() -> CGFloat)?

    /// The boss actor this system drives through the telegraph → throw
    /// cycle (the gyu.12 cycle contract: the monster owns no timing
    /// policy; this orchestrator calls the guarded transitions). Wired
    /// by GameScene's intro bead (gyu.17, `ensureEncounterContent`).
    /// nil — pre-first-encounter / pure-logic tests — runs the identical
    /// cycle on the dt clock alone, releasing balls at the same
    /// `SnowMonster.throwReleaseTime` offset, so volley pacing and
    /// accounting are monster-independent.
    var monster: SnowMonster?

    /// A snowball connected. Payload: the ball's lateral position in
    /// ENCOUNTER WORLD UNITS (≡ scene x at z = 0 — satisfies
    /// `tryTakeHit(from:)`'s impactX contract directly, polish note 1)
    /// plus the projected screen point for impact FX placement (gyu.16).
    /// GameScene's volley bead translates it to (a)
    /// `PapiAvatar.takeHit(fromWorldX:)` → `penguin.tryTakeHit` for
    /// hp / i-frames plus the avatar-side knockback impulse and (b) FX.
    ///
    /// I-FRAME CONTRACT (acceptance): this fires for EVERY connecting
    /// ball, i-frames or not — a hit during active i-frames still
    /// consumes the ball. That mirrors `onIcicleHitPenguin`'s
    /// `accepted == false` handling: `tryTakeHit` returns false (no HP
    /// change, no knockback) and the FX bead dials the impact treatment
    /// soft by that flag. The system itself never reads hp — a hit is a
    /// hit (score/HP-agnostic, like IcicleSystem).
    var onSnowballHit: ((_ ballWorldX: CGFloat, _ screenPoint: CGPoint) -> Void)?

    /// A snowball was dodged (crossed the camera plane unresolved).
    /// `severity` ∈ [0, 1] (see `SnowballResolution.dodged`);
    /// `screenPoint` is the ball's projected position at the crossing,
    /// for the `floatBonus` display. GameScene feeds this into the
    /// existing close-call bonus pipeline (`bonusPoints`), keeping the
    /// system score-agnostic exactly like `IcicleSystem.onCloseCall`.
    var onDodge: ((_ severity: CGFloat, _ screenPoint: CGPoint) -> Void)?

    /// The volley survived: every planned throw was made AND the last
    /// ball resolved (hit or dodge — in-flight balls must finish; this
    /// never fires at the last THROW). Fires exactly once per `begin`.
    /// GameScene routes it to the outro transition. Note the system
    /// stays outcome-agnostic: a volley "completes" even if every ball
    /// connected — GameScene's hit routing has already ended the run
    /// via `triggerGameOver()` in that case, and its handler ignores
    /// completion outside the `.encounter` phase.
    var onVolleyComplete: (() -> Void)?

    /// Balls spawned but not yet retired — the volley-completion
    /// accounting (gyu.15): a volley is complete when every throw has
    /// been made AND this returns to 0. +1 per spawn; −1 exactly once
    /// per ball when it leaves the live array (hit, dodge, unresolved
    /// cull with no provider, or external node death). `reset()` zeroes.
    private(set) var outstandingBalls = 0

    // MARK: - Volley plan (gyu.15 — pure lerp math, VolleyOrchestrationTests)

    /// One encounter's worth of throws, computed ONCE at `begin` from
    /// the run's difficulty progress at trigger time (mirrors
    /// `IcicleSystem.progress` feeding the icicle cadence knobs).
    struct VolleyPlan: Equatable {
        /// Snowballs in the volley.
        let count: Int
        /// Recovery gap (s) between a release and the next telegraph.
        let throwInterval: TimeInterval
        /// LAUNCH depth speed (pt/s toward the camera) for every ball
        /// thrown; balls then accelerate by `zAccel` in flight.
        let zSpeed: CGFloat
        /// Constant in-flight depth acceleration (pt/s², penguinslide-sct).
        let zAccel: CGFloat
    }

    /// Lerp the `Tuning.Encounter` volley knobs by difficulty progress:
    /// progress 0 yields the Start values, 1 the End values, mid lerps
    /// (count rounds to nearest). Progress is clamped to [0, 1] so a
    /// bad caller (negative elapsed, overlong run) degrades to the
    /// nearest knob instead of extrapolating. Knobs are parameterized
    /// with the Tuning defaults so tests can sweep them.
    static func volleyPlan(difficultyProgress: Double,
                           countStart: Int = Tuning.Encounter.volleyCountStart,
                           countEnd: Int = Tuning.Encounter.volleyCountEnd,
                           intervalStart: TimeInterval = Tuning.Encounter.throwIntervalStart,
                           intervalEnd: TimeInterval = Tuning.Encounter.throwIntervalEnd,
                           zSpeedStart: CGFloat = Tuning.Encounter.zSpeedStart,
                           zSpeedEnd: CGFloat = Tuning.Encounter.zSpeedEnd,
                           zAccel: CGFloat = Tuning.Encounter.zAccel) -> VolleyPlan {
        let p = min(1.0, max(0.0, difficultyProgress))
        let count = Int((Double(countStart)
            + (Double(countEnd) - Double(countStart)) * p).rounded())
        let interval = intervalStart + (intervalEnd - intervalStart) * p
        let zSpeed = zSpeedStart + (zSpeedEnd - zSpeedStart) * CGFloat(p)
        return VolleyPlan(count: count, throwInterval: interval,
                          zSpeed: zSpeed, zAccel: zAccel)
    }

    #if DEBUG
    // MARK: - Hermetic test-volley overrides (gyu.22)

    /// Launch-argument volley configuration for EncounterUITests
    /// (penguinslide-gyu.22). The simulator has no gyro, so the WIN and
    /// exact-HP paths can't be steered by input; instead the test launches
    /// the app with
    ///
    ///   -encounterTestVolley "count=3 interval=0.8 zSpeed=1200 hitRadius=0"
    ///
    /// and GameScene parses it at didMove time (more hermetic than
    /// orchestrating MotionInjector from XCUITest — that's shell-script
    /// territory, test-smoke.sh). Grammar: the value is whitespace- or
    /// comma-separated `key=value` tokens; recognized keys are `count`
    /// (Int, balls per volley), `interval` (s between throws), `zSpeed`
    /// (depth pt/s), and `hitRadius` (pt; 0 = nothing can connect →
    /// guaranteed win, large e.g. 400 = everything connects → guaranteed
    /// loss). Unrecognized/garbage tokens are skipped; every key is
    /// optional and un-overridden knobs keep their Tuning-lerped values.
    /// `accel` (depth pt/s², penguinslide-sct) overrides the in-flight
    /// acceleration — 0 gives constant-speed balls for timing-exact
    /// tests. DEBUG-only: Release builds compile none of this.
    struct TestVolleyOverrides: Equatable {
        // `= nil` defaults keep the memberwise init source-compatible
        // as override keys are added (call sites name only what they set).
        var count: Int? = nil
        var throwInterval: TimeInterval? = nil
        var zSpeed: CGFloat? = nil
        var zAccel: CGFloat? = nil
        var lateralHitRadius: CGFloat? = nil

        var isEmpty: Bool {
            count == nil && throwInterval == nil
                && zSpeed == nil && zAccel == nil && lateralHitRadius == nil
        }

        /// The launch flag; its VALUE is the next argument.
        static let launchArgument = "-encounterTestVolley"

        /// Parse from a full ProcessInfo-style argument list. nil when the
        /// flag is absent, has no value, or the value yields no overrides.
        static func parse(arguments: [String]) -> TestVolleyOverrides? {
            guard let i = arguments.firstIndex(of: launchArgument),
                  arguments.indices.contains(i + 1) else { return nil }
            return parse(spec: arguments[i + 1])
        }

        /// Parse one spec string ("count=3 interval=0.8 ..."). nil when
        /// nothing recognizable is present, so a garbage spec degrades to
        /// "no overrides" rather than a half-configured volley.
        static func parse(spec: String) -> TestVolleyOverrides? {
            var overrides = TestVolleyOverrides()
            for token in spec.split(whereSeparator: { $0 == " " || $0 == "," }) {
                let pair = token.split(separator: "=", maxSplits: 1)
                guard pair.count == 2 else { continue }
                let value = String(pair[1])
                switch pair[0] {
                case "count":     overrides.count = Int(value)
                case "interval":  overrides.throwInterval = TimeInterval(value)
                case "zSpeed":    overrides.zSpeed = Double(value).map { CGFloat($0) }
                case "accel":     overrides.zAccel = Double(value).map { CGFloat($0) }
                case "hitRadius": overrides.lateralHitRadius = Double(value).map { CGFloat($0) }
                default:          break
                }
            }
            return overrides.isEmpty ? nil : overrides
        }

        /// Apply the plan-shaped overrides on top of a Tuning-lerped plan.
        /// (`lateralHitRadius` is not plan state — the sweep reads it.)
        func applied(to plan: VolleyPlan) -> VolleyPlan {
            VolleyPlan(count: count ?? plan.count,
                       throwInterval: throwInterval ?? plan.throwInterval,
                       zSpeed: zSpeed ?? plan.zSpeed,
                       zAccel: zAccel ?? plan.zAccel)
        }
    }

    /// Wired once by GameScene.didMove from the launch arguments; nil in
    /// every non-test run. Survives reset() deliberately — each begin()
    /// of the same app launch gets the same scripted volley.
    var testVolleyOverrides: TestVolleyOverrides?
    #endif

    // MARK: - Volley cycle state (gyu.15)

    /// Where the throw cycle is between balls. All timing is the
    /// system's own dt clock (`cycleTimer` counts DOWN) — never an
    /// SKAction completion — so the dt == 0 sentinel and pause
    /// semantics hold for scheduling exactly as they do for flight.
    private enum CyclePhase {
        /// No throw pending: pre-begin, post-last-throw (in-flight
        /// balls may still be resolving), or post-completion.
        case idle
        /// Counting down the inter-throw gap to the next telegraph.
        case recovering
        /// Counting down the wind-up; the monster (when attached) is
        /// pulsing its warning. Ends by committing the throw.
        case telegraphing
        /// Throw committed; waiting for the release moment. With a
        /// monster the release signal is its `onRelease` (frame-exact
        /// against the clip) and `cycleTimer` holds a WATCHDOG; without
        /// one the timer IS the release at `throwReleaseTime`.
        case winding
    }

    private var cyclePhase: CyclePhase = .idle
    /// Seconds remaining in the current cycle phase (counts down).
    private var cycleTimer: TimeInterval = 0
    /// True from `begin` until completion/reset — gates the cycle and
    /// makes `onVolleyComplete` exactly-once.
    private(set) var volleyActive = false
    /// Releases made so far this volley (`private(set)` so tests can
    /// assert "complete fires after the last RESOLUTION, not throw").
    private(set) var throwsMade = 0
    /// The plan computed at `begin`; nil when no volley has begun.
    private(set) var plan: VolleyPlan?
    /// Guards the release seam: armed at commit, disarmed by whichever
    /// of onRelease/watchdog fires first, so a late SKAction callback
    /// can never double-spawn a forced release.
    private var awaitingRelease = false

    /// RNG for cycle-driven spawns (aim jitter / drift / spin rolls).
    /// Injectable so tests can drive a fully deterministic volley.
    var volleyRNG: any RandomNumberGenerator = SystemRandomNumberGenerator()

    // MARK: - Audio (penguinslide-gyu.27 — IcicleSystem's anatomy)
    //
    // SKAudioNodes so each play can set its own volume (throw whoosh is
    // fixed-level, impact scales by accepted/absorbed, dodge whoosh by
    // severity) and rapid repeats restart cleanly via the stop+play
    // pattern (crackAudioNode's recipe). The nodes live on the SCENE,
    // never under encounterRoot — a hidden+paused container freezes
    // SKAudioNode actions mid-clip (IcicleSystem's documented rule), and
    // audio is not part of the visual world swap. Every node creation is
    // guarded on Bundle.main.url so a checkout without the staged
    // ElevenLabs audio runs silent-but-safe (SKAudioNode(fileNamed:)
    // with a missing resource is a crash risk).
    //
    // The intro roar (snowman_roar.caf) is NOT here: it is a
    // fire-and-forget guardedOneShot in GameScene at the
    // performEncounterWorldSwap roar slot, beside the visual roar().

    /// Throw whoosh — fired at the release signal (`releaseBall`), the
    /// same beat that spawns the ball at the monster's hand.
    private var throwAudioNode: SKAudioNode?
    /// Snowball impact — fired from GameScene's hit routing (the
    /// accepted flag only exists after PapiAvatar.takeHit consults the
    /// penguin's i-frame clock) via `playImpactAudio(accepted:)`.
    private var impactAudioNode: SKAudioNode?
    /// Dodge whoosh — fired inside the sweep at dodge resolution,
    /// volume lerped by severity (close shaves are louder).
    private var dodgeAudioNode: SKAudioNode?
    /// Flyby layer — the past-the-ear accent on top of the dodge whoosh
    /// for near-misses at/above `Tuning.Encounter.flybySeverityMin`.
    private var flybyAudioNode: SKAudioNode?

    /// Build the guarded audio nodes once and attach them to `scene`
    /// (GameScene calls this from ensureEncounterContent, beside
    /// `configure`). Idempotent: repeat calls are no-ops so a scene
    /// rebuild can never stack duplicate nodes.
    func attachAudio(scene: SKNode) {
        guard !audioAttached else { return }
        audioAttached = true
        throwAudioNode = Self.makeAudioNode("snowball_throw.caf", on: scene)
        impactAudioNode = Self.makeAudioNode("snowball_impact.caf", on: scene)
        dodgeAudioNode = Self.makeAudioNode("dodge_whoosh.caf", on: scene)
        flybyAudioNode = Self.makeAudioNode("snowball_flyby.caf", on: scene)
    }
    private var audioAttached = false

    /// nil when `file` isn't bundled (silent-but-safe), else a
    /// non-looping, non-positional SKAudioNode added to `scene` — the
    /// IcicleSystem init recipe behind the gyu.27 missing-file guard.
    private static func makeAudioNode(_ file: String, on scene: SKNode) -> SKAudioNode? {
        guard Bundle.main.url(forResource: file, withExtension: nil) != nil else { return nil }
        let node = SKAudioNode(fileNamed: file)
        node.autoplayLooped = false
        node.isPositional = false
        scene.addChild(node)
        return node
    }

    /// Set volume + restart in one action pass — playLandingShatter's
    /// exact pattern, so rapid repeats rate-limit by restarting instead
    /// of overlapping.
    private static func play(_ node: SKAudioNode?, volume: Float) {
        node?.run(.sequence([.changeVolume(to: volume, duration: 0),
                             .stop(),
                             .play()]))
    }

    /// Snowball impact SFX, volume scaled by the hit verdict — the audio
    /// mirror of the accepted == false soft-FX treatment. Called by
    /// GameScene's onSnowballHit routing AFTER takeHit returns (the
    /// system itself never learns the verdict — it stays HP-agnostic).
    func playImpactAudio(accepted: Bool) {
        Self.play(impactAudioNode, volume: Self.impactVolume(accepted: accepted))
    }

    /// Dodge SFX at resolution: the whoosh always (severity-lerped
    /// volume), the flyby layered on for near-misses only.
    private func playDodgeAudio(severity: CGFloat) {
        Self.play(dodgeAudioNode, volume: Self.dodgeWhooshVolume(severity: severity))
        if Self.flybyFires(severity: severity) {
            Self.play(flybyAudioNode, volume: Tuning.Encounter.flybyVolume)
        }
    }

    /// Hard-stop every encounter SFX node. GameScene's pauseSceneAudio
    /// calls this on app-background / settings (acceptance: backgrounding
    /// mid-encounter silences everything). STOP rather than pause: the
    /// resume path must not re-`play()` a one-shot that wasn't sounding —
    /// that would fire a spurious whoosh — so these clips simply end and
    /// the resume path leaves them alone (the icicle SFX discipline,
    /// made explicit).
    func stopAudio() {
        for node in [throwAudioNode, impactAudioNode, dodgeAudioNode, flybyAudioNode] {
            node?.run(.stop())
        }
    }

    // MARK: Pure audio mapping (unit-tested — EncounterAudioTests)

    /// Severity-lerped dodge whoosh volume: min at a wide dodge, max at
    /// a hair's-breadth shave. Severity clamps to [0, 1] so a bad caller
    /// degrades to the nearest knob.
    static func dodgeWhooshVolume(severity: CGFloat,
                                  minVolume: Float = Tuning.Encounter.dodgeWhooshVolumeMin,
                                  maxVolume: Float = Tuning.Encounter.dodgeWhooshVolumeMax) -> Float {
        let s = Float(min(1, max(0, severity)))
        return minVolume + (maxVolume - minVolume) * s
    }

    /// Impact volume by hit verdict: full when HP was lost, scaled soft
    /// when i-frames absorbed it (mirrors EncounterFX.hitHaptic's
    /// accepted distinction).
    static func impactVolume(accepted: Bool,
                             base: Float = Tuning.Encounter.impactVolume,
                             absorbedScale: Float = Tuning.Encounter.impactAbsorbedScale) -> Float {
        accepted ? base : base * absorbedScale
    }

    /// Whether a dodge earns the flyby layer (inclusive threshold —
    /// severity AT the knob fires, matching dodgeHaptic's >=).
    static func flybyFires(severity: CGFloat,
                           threshold: CGFloat = Tuning.Encounter.flybySeverityMin) -> Bool {
        severity >= threshold
    }

    /// Watchdog (s) on the monster's release signal past the expected
    /// `throwReleaseTime`: if the throw clip stalls (action paused or
    /// scene not rendering), the ball releases on the dt clock anyway —
    /// the "full volley terminates deterministically, no hangs"
    /// acceptance can never depend on SKAction delivery.
    static let releaseWatchdogGrace: TimeInterval = 1.5
    /// Watchdog (s) on a telegraph the monster keeps rejecting (stuck
    /// outside .idle — e.g. a follow-through frozen by a pause): after
    /// this long past the due telegraph, the cycle proceeds without
    /// the actor's visuals rather than parking the phase machine.
    static let telegraphStallGrace: TimeInterval = 2.0

    /// Construction is no-arg (GameScene builds the system before the
    /// scene graph exists); `configure` attaches the world seams. Safe
    /// to call again on scene rebuilds — spawning guards on it.
    func configure(parent: SKNode, projector: DepthProjector) {
        self.parent = parent
        self.projector = projector
    }

    // MARK: - Pure resolution math (gyu.14 — SnowballCollisionTests)

    /// One frame's hit-vs-dodge test for one ball, pure and node-free
    /// (KTD3: manual collision in the update loop, never `didBegin`).
    /// Call AFTER integrating the frame's z/worldX, with the
    /// pre-integration depth as `previousZ`; stop calling once it
    /// returns non-`.none` (the caller's `resolved` flag makes
    /// resolution exactly-once — this function is stateless).
    ///
    /// Rules (knobs parameterized with `Tuning.Encounter` defaults so
    /// tests can sweep them):
    /// - HIT iff the swept depth segment [z, previousZ] overlaps the hit
    ///   slab `z' < depthWindow` AND `|ballWorldX − papiWorldX| <
    ///   lateralHitRadius` (STRICT: exactly at the radius is a miss —
    ///   asserted by tests). The lateral test uses the post-step
    ///   position, so a drifting ball that curves into the radius while
    ///   mid-band still connects on that frame.
    /// - DODGE iff z ≤ 0 (the ball exits the near plane) without a hit;
    ///   severity is computed from the lateral miss AT this crossing
    ///   frame via `dodgeSeverity`.
    ///
    /// TUNNELING CONTRACT: the hit slab is ONE-SIDED — it extends from
    /// `depthWindow` down through z ≤ 0, and resolution runs before the
    /// near-plane cull. A camera-bound ball's swept segment therefore
    /// overlaps the slab on its crossing frame no matter how large the
    /// step (`min(z, previousZ) < depthWindow` is the segment-overlap
    /// test, not point-in-band), so no zSpeed/dt combination can step
    /// across the window undetected. Enforced by SnowballCollisionTests'
    /// giant-step case.
    static func resolve(previousZ: CGFloat,
                        z: CGFloat,
                        ballWorldX: CGFloat,
                        papiWorldX: CGFloat,
                        depthWindow: CGFloat = Tuning.Encounter.depthWindow,
                        lateralHitRadius: CGFloat = Tuning.Encounter.lateralHitRadius,
                        severityRadius: CGFloat = Tuning.Encounter.severityRadius)
        -> SnowballResolution {
        let lateralMiss = abs(ballWorldX - papiWorldX)
        if min(z, previousZ) < depthWindow && lateralMiss < lateralHitRadius {
            return .hit
        }
        if z <= 0 {
            return .dodged(severity: dodgeSeverity(lateralMiss: lateralMiss,
                                                   severityRadius: severityRadius))
        }
        return .none
    }

    /// Normalized near-miss closeness for a dodge: `1 − miss/radius`,
    /// clamped to [0, 1]. `severityRadius` is deliberately a SEPARATE
    /// knob from `lateralHitRadius` (see Tuning.Encounter.severityRadius:
    /// severity is measured at the miss boundary, so sharing the hit
    /// knob would score every dodge 0). A non-positive radius (bad knob
    /// edit) degrades to severity 0 instead of dividing by zero.
    static func dodgeSeverity(lateralMiss: CGFloat,
                              severityRadius: CGFloat = Tuning.Encounter.severityRadius)
        -> CGFloat {
        guard severityRadius > 0 else { return 0 }
        return min(1, max(0, 1 - abs(lateralMiss) / severityRadius))
    }

    // MARK: - Cached shadow texture
    //
    // Soft dark ellipse, rendered ONCE and shared by every snowball
    // shadow sprite — the exact `IcicleSystem.shadowTexture` recipe
    // (duplicated, not shared: that one is private to the icicle
    // system, and the two systems' lifetimes are independent).
    static let shadowTexture: SKTexture = {
        let w: CGFloat = 64
        let h: CGFloat = 18
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.saveGState()
            cg.setFillColor(UIColor(white: 0, alpha: 0.45).cgColor)
            cg.fillEllipse(in: CGRect(x: w * 0.10, y: h * 0.20,
                                      width: w * 0.80, height: h * 0.60))
            cg.setFillColor(UIColor(white: 0, alpha: 0.55).cgColor)
            cg.fillEllipse(in: CGRect(x: w * 0.25, y: h * 0.30,
                                      width: w * 0.50, height: h * 0.40))
            cg.restoreGState()
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        return tex
    }()

    // MARK: - Spawn (the monster's release signal — gyu.12's onRelease)

    /// Spawn one snowball at the monster's depth station, aimed at the
    /// avatar's position AT THROW TIME with a partial lead + jitter
    /// (`snowballAimWorldX`), clamped to the dodge corridor. The
    /// trajectory is committed from this moment — dodge by moving off
    /// the line. Volley orchestration (gyu.15) calls this from
    /// `SnowMonster.throwSnowball`'s `onRelease` with the avatar's
    /// live `worldX`/`vx` and the volley's current zSpeed.
    ///
    /// `driftVx` overrides the random curve roll (tests, scripted
    /// volley variants); nil rolls `snowballDriftChance`. `rng` is
    /// injected for deterministic tests; production uses the default.
    /// Returns the spawned model (nil before `configure`).
    @discardableResult
    func spawnSnowball(targetWorldX: CGFloat,
                       targetVx: CGFloat,
                       zSpeed: CGFloat,
                       zAccel: CGFloat = Tuning.Encounter.zAccel,
                       driftVx driftOverride: CGFloat? = nil,
                       using rng: inout any RandomNumberGenerator) -> Snowball? {
        guard let parent, let projector else { return nil }

        let spawnZ = Tuning.Encounter.zMonster
        let jitterMax = Tuning.Encounter.snowballAimJitter
        let jitter = CGFloat.random(in: -jitterMax...jitterMax, using: &rng)
        let worldX = snowballAimWorldX(
            targetWorldX: targetWorldX,
            targetVx: targetVx,
            // EXACT accelerated flight time (penguinslide-sct) — the lead
            // prediction must not assume constant speed or the aim goes
            // stale the moment the ball starts rushing.
            flightTime: snowballFlightTime(spawnZ: spawnZ,
                                           zSpeed: zSpeed,
                                           zAccel: zAccel),
            leadFactor: Tuning.Encounter.snowballLeadFactor,
            jitter: jitter,
            corridorCenter: projector.vanishingX,
            corridorHalfWidth: Tuning.Encounter.papiLateralRange
        )

        let driftVx: CGFloat
        if let driftOverride {
            driftVx = driftOverride
        } else if Double.random(in: 0...1, using: &rng) < Tuning.Encounter.snowballDriftChance {
            let driftMax = Tuning.Encounter.snowballDriftVxMax
            driftVx = CGFloat.random(in: -driftMax...driftMax, using: &rng)
        } else {
            driftVx = 0
        }

        let spinRange = Tuning.Encounter.snowballSpinSpeedMin...Tuning.Encounter.snowballSpinSpeedMax
        let spin = CGFloat.random(in: spinRange, using: &rng)
            * (Bool.random(using: &rng) ? 1 : -1)

        // Per-throw node creation (never per-frame): ball sprite off the
        // cached catalog texture + one shared-texture shadow sprite.
        let size = Tuning.Encounter.snowballBaseSize
        let node = SKSpriteNode(texture: SpriteCatalog.texture(for: .snowball),
                                size: CGSize(width: size, height: size))
        node.name = "snowball"
        parent.addChild(node)

        let shadow = SKSpriteNode(texture: Self.shadowTexture)
        shadow.name = "snowballShadow"
        parent.addChild(shadow)

        let ball = Snowball(node: node,
                            shadow: shadow,
                            z: spawnZ,
                            worldX: worldX,
                            driftVx: driftVx,
                            zSpeed: zSpeed,
                            zAccel: zAccel,
                            spinSpeed: spin,
                            spawnZ: spawnZ)
        // Seat the visuals immediately so the ball appears at the
        // monster's hand THIS frame (projection of spawn height at
        // spawnZ ≡ SnowMonster.snowballSpawnPoint()), not wherever the
        // sprite default lands until the next update.
        layout(ball: ball, node: node, projector: projector, spinDt: 0)
        snowballs.append(ball)
        outstandingBalls += 1
        return ball
    }

    /// Production-RNG convenience for the orchestration call site.
    @discardableResult
    func spawnSnowball(targetWorldX: CGFloat,
                       targetVx: CGFloat,
                       zSpeed: CGFloat,
                       zAccel: CGFloat = Tuning.Encounter.zAccel) -> Snowball? {
        var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
        return spawnSnowball(targetWorldX: targetWorldX,
                             targetVx: targetVx,
                             zSpeed: zSpeed,
                             zAccel: zAccel,
                             using: &rng)
    }

    // MARK: - Volley orchestration (gyu.15)

    /// Start one encounter's volley: compute the plan from the run's
    /// difficulty progress AT TRIGGER TIME and arm the throw cycle (the
    /// first telegraph fires on the next dt > 0 frame). Begins from a
    /// cold state unconditionally — calling it tears down any previous
    /// volley first (idempotent re-entry: begin() after reset(), or
    /// even after a completed volley, always yields a clean encounter).
    func begin(difficultyProgress: Double) {
        reset()
        plan = Self.volleyPlan(difficultyProgress: difficultyProgress)
        #if DEBUG
        // Hermetic test-volley config (gyu.22): launch-argument overrides
        // replace individual plan knobs, leaving the rest Tuning-lerped.
        if let overrides = testVolleyOverrides, let base = plan {
            plan = overrides.applied(to: base)
        }
        #endif
        volleyActive = true
        // timer 0 in .recovering = "telegraph as soon as possible":
        // the first wind-up starts on the first real frame, so the
        // intro hand-off owns any extra breather, not hidden state here.
        cyclePhase = .recovering
        cycleTimer = 0
    }

    /// Drive the telegraph → throw → release → recover cycle one frame.
    /// dt == 0 (sentinel) injects no scheduling time, symmetric with
    /// the flight sweep.
    private func updateVolley(dt: TimeInterval) {
        guard volleyActive, let plan, dt > 0, throwsMade < plan.count else { return }
        cycleTimer -= dt
        switch cyclePhase {
        case .idle:
            break
        case .recovering:
            if cycleTimer <= 0 { startTelegraph() }
        case .telegraphing:
            if cycleTimer <= 0 { commitThrow(plan: plan) }
        case .winding:
            // Monster-less release moment, or the attached-monster
            // watchdog expiring — `releaseBall` is exactly-once either
            // way via `awaitingRelease`.
            if cycleTimer <= 0 { releaseBall() }
        }
    }

    /// Begin the wind-up cue. With a monster attached the guarded
    /// `telegraph()` transition must accept (it rejects outside .idle —
    /// e.g. the previous follow-through still playing); a rejection
    /// retries every frame until the actor settles, with the stall
    /// watchdog proceeding visual-less past `telegraphStallGrace` so
    /// the cycle can never park.
    private func startTelegraph() {
        if let monster, !monster.telegraph() {
            guard cycleTimer <= -Self.telegraphStallGrace else { return }
        }
        cyclePhase = .telegraphing
        cycleTimer = Tuning.Encounter.telegraphDuration
    }

    /// Commit the throw at the telegraph's end. With a monster the
    /// release signal is its frame-exact `onRelease` and the timer
    /// becomes a watchdog; without one (interim bridge, pure-logic
    /// tests, or a rejected transition) the dt clock releases at the
    /// same `throwReleaseTime` offset so pacing is identical.
    private func commitThrow(plan: VolleyPlan) {
        awaitingRelease = true
        cyclePhase = .winding
        if let monster,
           monster.throwSnowball(onRelease: { [weak self] in self?.releaseBall() }) {
            cycleTimer = SnowMonster.throwReleaseTime + Self.releaseWatchdogGrace
        } else {
            cycleTimer = SnowMonster.throwReleaseTime
        }
    }

    /// The release signal: spawn the ball aimed at the avatar's LIVE
    /// position/velocity (committed trajectory — dodge by moving off
    /// the line) at the plan's zSpeed, then enter the recovery gap.
    /// Exactly-once per throw: a watchdog-forced release disarms the
    /// seam so a late `onRelease` from the same clip is a no-op.
    private func releaseBall() {
        guard volleyActive, awaitingRelease, let plan else { return }
        awaitingRelease = false

        let targetX = papiWorldXProvider?() ?? projector?.vanishingX ?? 0
        let targetVx = papiVxProvider?() ?? 0
        // Spawn failure (configure never called) still counts the
        // throw: outstanding accounting stays exact and the volley
        // terminates instead of hanging on a ball that never existed.
        spawnSnowball(targetWorldX: targetX,
                      targetVx: targetVx,
                      zSpeed: plan.zSpeed,
                      zAccel: plan.zAccel,
                      using: &volleyRNG)
        // Throw whoosh ON the release signal (gyu.27) — the same beat
        // the ball leaves the monster's hand, watchdog-forced releases
        // included (the sound tracks the BALL, not the clip).
        Self.play(throwAudioNode, volume: Tuning.Encounter.throwWhooshVolume)

        throwsMade += 1
        if throwsMade < plan.count {
            cyclePhase = .recovering
            cycleTimer = plan.throwInterval
        } else {
            // All throws made — the cycle is done, but the VOLLEY is
            // not: completion waits on the last resolution (the
            // accounting check below).
            cyclePhase = .idle
            cycleTimer = 0
        }
    }

    /// Completion detector, run after every sweep: every planned throw
    /// made AND no ball outstanding ⇒ the last ball RESOLVED this
    /// frame (hit, dodge, or providerless cull). Disarms the volley
    /// before calling out so it can never double-fire.
    private func checkVolleyCompletion() {
        guard volleyActive, let plan,
              throwsMade >= plan.count, outstandingBalls == 0 else { return }
        volleyActive = false
        cyclePhase = .idle
        onVolleyComplete?()
    }

    // MARK: - Per-frame tick

    /// Per-frame encounter integration: drive the throw cycle, sweep
    /// the in-flight balls, then check volley completion (in that
    /// order, so a release and its ball's first layout share a frame
    /// and a final-resolution frame completes immediately).
    ///
    /// ORDERING CONTRACT (penguinslide-gyu.19, asserted by
    /// EncounterDeathAccountingTests): hit/dodge resolution callbacks
    /// fire INSIDE the sweep, strictly BEFORE `checkVolleyCompletion`
    /// runs — so when the FINAL ball connects lethally, the scene's
    /// `onSnowballHit` handler has already run `triggerGameOver()`
    /// (isGameOver = true) by the time `onVolleyComplete` fires in the
    /// same update call, and the scene's `!isGameOver` guard resolves
    /// that frame as game over, never outro. Do not reorder the three
    /// calls below.
    ///
    /// `tilt` is
    /// the same `currentTilt()` value `Penguin.update` receives in
    /// normal mode (KTD4: GameScene owns input; subsystems receive
    /// it). The avatar wiring bead routes it on to PapiAvatar; the
    /// flight loop itself doesn't read tilt — trajectories are
    /// committed at spawn.
    func update(dt: TimeInterval, tilt: CGFloat) {
        updateVolley(dt: dt)
        updateProjectiles(dt: dt)
        checkVolleyCompletion()
    }

    /// Flight sweep — IcicleSystem.integrateAndCheckLandings' shape:
    /// one linear compactMap pass that integrates, RESOLVES (gyu.14:
    /// manual depth-window hit/dodge, KTD3), lays out, and culls.
    /// dt == 0 (sentinel frame) is a free no-op, mirroring
    /// EncounterWorld.update: no time may be injected by resume frames.
    private func updateProjectiles(dt: TimeInterval) {
        guard dt > 0, let projector, !snowballs.isEmpty else { return }
        let dtF = CGFloat(dt)
        let corridorMin = projector.vanishingX - Tuning.Encounter.papiLateralRange
        let corridorMax = projector.vanishingX + Tuning.Encounter.papiLateralRange
        // Read Papi once per sweep: every ball in a frame is tested
        // against the same target position (the avatar can't move
        // mid-sweep). nil = no avatar wired yet → no collision pass.
        let papiWorldX = papiWorldXProvider?()
        // Hermetic test-volley config (gyu.22): the hitRadius override
        // widens (forced loss) or zeroes (forced win) the connect band.
        #if DEBUG
        let lateralHitRadius = testVolleyOverrides?.lateralHitRadius
            ?? Tuning.Encounter.lateralHitRadius
        #else
        let lateralHitRadius = Tuning.Encounter.lateralHitRadius
        #endif

        snowballs = snowballs.compactMap { entry in
            var ball = entry
            guard let node = ball.node else {
                // Node died externally (scene teardown) — drop the
                // orphaned shadow with it.
                ball.shadow?.removeFromParent()
                outstandingBalls -= 1
                return nil
            }
            if ball.resolved {
                // Resolved externally between sweeps (FX bead seam) —
                // flight just culls, never re-resolves.
                retire(ball: ball, node: node)
                return nil
            }

            // Manual depth + drift integration. Semi-implicit Euler for
            // the acceleration (penguinslide-sct): speed first, then
            // position from the NEW speed — matching the closed-form
            // snowballFlightTime within a frame (SnowballSystemTests
            // pins the agreement). The drift clamp matches the aim
            // clamp so a curving ball can never leave the dodgeable
            // corridor mid-flight; the hit sweep below is segment-based
            // (min(z, previousZ)), so the growing per-frame step can
            // never tunnel through the depth window.
            let previousZ = ball.z
            // Floored at the closed form's clamp (snowballFlightTime's
            // max(v0, 1)) so a mis-tuned deceleration or negative DEBUG
            // `accel=` override degrades to a forward crawl that still
            // arrives and resolves — never a backward flight that
            // strands `outstandingBalls` and soft-locks the volley
            // (penguinslide-gyu.34).
            ball.zSpeed = max(ball.zSpeed + ball.zAccel * dtF, 1)
            ball.z -= ball.zSpeed * dtF
            ball.worldX = min(corridorMax, max(corridorMin, ball.worldX + ball.driftVx * dtF))

            // Collision/dodge pass (gyu.14) — BEFORE the near-plane cull
            // so a plane-crossing frame always resolves first. Pure math
            // in `resolve`; exactly-once via the resolved flag (a hit
            // consumes the ball now; a dodge has z ≤ 0 by definition, so
            // it leaves the near plane on this same frame).
            if let papiWorldX {
                switch Self.resolve(previousZ: previousZ, z: ball.z,
                                    ballWorldX: ball.worldX, papiWorldX: papiWorldX,
                                    lateralHitRadius: lateralHitRadius) {
                case .none:
                    break
                case .hit:
                    ball.resolved = true
                    onSnowballHit?(ball.worldX,
                                   screenPoint(for: ball, projector: projector))
                    retire(ball: ball, node: node)
                    return nil
                case .dodged(let severity):
                    ball.resolved = true
                    // Dodge audio fires AT resolution, severity in hand
                    // (gyu.27): whoosh always, flyby layered for
                    // near-misses. In-system because severity is born
                    // here; the hit's accepted-scaled audio waits for
                    // GameScene's verdict (playImpactAudio).
                    playDodgeAudio(severity: severity)
                    onDodge?(severity,
                             screenPoint(for: ball, projector: projector))
                    // A dodged ball must not blink out at the camera
                    // plane — it slides under the window (exit beat)
                    // while the accounting retires it now.
                    retireWithExit(ball: ball, node: node, projector: projector)
                    return nil
                }
            }

            if ball.z <= 0 {
                // Camera-plane crossing with NO target wired (provider
                // nil — interim bridge): flight-only culling guarantees
                // unresolved balls never linger or fold over behind the
                // camera. With a target wired this is unreachable — the
                // resolver above turned the crossing into a dodge.
                retire(ball: ball, node: node)
                return nil
            }

            layout(ball: ball, node: node, projector: projector, spinDt: dtF)
            return ball
        }
    }

    /// Remove one ball (and its shadow) from the tree and decrement the
    /// outstanding accounting — the single retirement seam, so every
    /// ball decrements exactly once no matter which cull path takes it.
    private func retire(ball: Snowball, node: SKSpriteNode) {
        node.removeFromParent()
        ball.shadow?.removeFromParent()
        outstandingBalls -= 1
    }

    /// Nodes riding their exit one-shot after dodge retirement —
    /// accounting-wise these balls are GONE (retired above); the array
    /// exists only so `setActionsPaused` can freeze a mid-exit ball on
    /// game over and `reset()` can scrub it. Self-cleaning: detached
    /// nodes are swept whenever a new exit starts.
    private(set) var exitingBalls: [SKNode] = []

    /// Dodge retirement with the under-the-window exit beat
    /// (penguinslide-sct follow-up): accounting retires NOW (the volley
    /// completion signal must not wait on FX), the shadow fades fast
    /// (the ball is leaving the ground plane's influence), and the node
    /// continues screen-space — outward from the vanishing point, down
    /// past the bottom edge, swelling like a passing object — sizzling
    /// out (fade) over the tail of the slide before removing itself.
    private func retireWithExit(ball: Snowball, node: SKSpriteNode,
                                projector: DepthProjector) {
        outstandingBalls -= 1
        if let shadow = ball.shadow {
            shadow.run(.sequence([.fadeOut(withDuration: 0.12),
                                  .removeFromParent()]))
            exitingBalls.append(shadow)
        }

        let dur = Tuning.Encounter.dodgeExitDuration
        let drop = node.position.y + node.size.height
            * Tuning.Encounter.dodgeExitScale / 2
            + Tuning.Encounter.dodgeExitDropExtra
        let lateral = (node.position.x - projector.vanishingX)
            * Tuning.Encounter.dodgeExitLateralFactor
        // Draw over every depth band on the way out: the ball is now
        // nearer than anything in the scene (EncounterWorld's reserved
        // z-stack tops out below this).
        node.zPosition = 69
        node.run(.group([
            .moveBy(x: lateral, y: -drop, duration: dur),
            .scale(by: Tuning.Encounter.dodgeExitScale, duration: dur),
            .rotate(byAngle: ball.spinSpeed * CGFloat(dur), duration: dur),
            // Sizzle: hold full presence for the first stretch, then
            // fade through the last — reads as passing under, not
            // dissolving in place.
            .sequence([.wait(forDuration: dur * 0.45),
                       .fadeOut(withDuration: dur * 0.55)]),
        ]))
        node.run(.sequence([.wait(forDuration: dur), .removeFromParent()]))
        exitingBalls.removeAll { $0.parent == nil }
        exitingBalls.append(node)
    }

    /// Projected screen position of a ball's CURRENT flight state — the
    /// same projection + height-lerp the layout pass writes to the node,
    /// recomputed fresh so resolution callbacks (which fire after
    /// integration but before any layout) report this frame's point, not
    /// last frame's. Negative z clamps inside the projector, so a
    /// crossing-frame dodge reports the camera-plane point.
    private func screenPoint(for ball: Snowball, projector: DepthProjector) -> CGPoint {
        let projected = projector.project(worldX: ball.worldX, z: ball.z)
        let height = snowballFlightHeight(
            progress: snowballFlightProgress(z: ball.z, spawnZ: ball.spawnZ))
        return CGPoint(x: projected.point.x,
                       y: projected.point.y + height * projected.scale)
    }

    /// Write one ball's presentation from its flight state: projected
    /// position + scale, height-above-ground lerp (hand → body), manual
    /// spin, depth-keyed zPosition, and the tracking ground shadow that
    /// grows/darkens as z drops (the icicle landing-shadow treatment,
    /// keyed on flight progress instead of fall progress).
    private func layout(ball: Snowball, node: SKSpriteNode,
                        projector: DepthProjector, spinDt: CGFloat) {
        let projected = projector.project(worldX: ball.worldX, z: ball.z)
        let progress = snowballFlightProgress(z: ball.z, spawnZ: ball.spawnZ)
        let height = snowballFlightHeight(progress: progress)

        node.position = CGPoint(x: projected.point.x,
                                y: projected.point.y + height * projected.scale)
        node.setScale(projected.scale)
        node.zPosition = snowballZPosition(z: ball.z)
        // Manual spin integration (no SKAction): freezes with the loop,
        // so game-over/pause never shows a ball spinning in place.
        node.zRotation += ball.spinSpeed * spinDt

        if let shadow = ball.shadow {
            shadow.position = projected.point
            shadow.setScale(projected.scale
                * (Tuning.Feel.shadowMinScale
                    + (Tuning.Feel.shadowMaxScale - Tuning.Feel.shadowMinScale) * progress))
            shadow.alpha = Tuning.Feel.shadowMinAlpha
                + (Tuning.Feel.shadowMaxAlpha - Tuning.Feel.shadowMinAlpha) * progress
            shadow.zPosition = node.zPosition - Self.shadowZPositionOffset
        }
    }

    // MARK: - Lifecycle

    /// One-way freeze for `triggerGameOver()` — the encounter mirror of
    /// `pauseShardActions()`, so a death mid-volley freezes the WHOLE
    /// encounter world (the monster's clips and pulses included), not
    /// just physics-driven motion.
    func pauseActions() {
        setActionsPaused(true)
    }

    /// Freeze/unfreeze any SKActions on encounter content this system
    /// owns — GameScene's game-over freeze seam, mirroring
    /// `pauseShardActions()`. The monster's telegraph pulse / throw
    /// clips are the live actions today; snowballs are fully manually
    /// integrated (motion AND spin), so pausing their nodes is
    /// future-proofing for the FX bead (gyu.16: pooled splat/whoosh
    /// actions register here).
    func setActionsPaused(_ paused: Bool) {
        monster?.setActionsPaused(paused)
        for ball in snowballs {
            ball.node?.isPaused = paused
            ball.shadow?.isPaused = paused
        }
        // Mid-exit dodged balls freeze too — a death the instant after
        // a dodge must not leave one ball sliding over the frozen frame.
        for node in exitingBalls { node.isPaused = paused }
    }

    /// Clears volley/world state so a restart after an encounter death
    /// (or the outro's teardown) starts the next encounter clean: every
    /// ball AND its shadow leaves the tree (zero leaks — asserted by
    /// node count in tests), the throw cycle disarms (no completion
    /// callback can fire from a torn-down volley, and any pending
    /// monster onRelease is cancelled with its actions), and the
    /// monster returns to its idle/home state.
    func reset() {
        volleyActive = false
        cyclePhase = .idle
        cycleTimer = 0
        throwsMade = 0
        awaitingRelease = false
        plan = nil
        monster?.reset()
        for ball in snowballs {
            ball.node?.removeFromParent()
            ball.shadow?.removeFromParent()
        }
        snowballs.removeAll(keepingCapacity: true)
        for node in exitingBalls { node.removeFromParent() }
        exitingBalls.removeAll(keepingCapacity: true)
        // A reset abandons the volley wholesale — outstanding accounting
        // re-arms at zero (not decremented per ball: these balls were
        // never resolved, and the completion check must not see ghosts
        // from a torn-down volley).
        outstandingBalls = 0
        // And its sounds: a restart mid-volley cuts any in-flight SFX
        // so the side view / next encounter starts sonically clean.
        stopAudio()
    }
}
