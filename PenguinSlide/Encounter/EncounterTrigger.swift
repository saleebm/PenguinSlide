//
//  EncounterTrigger.swift
//  PenguinSlide
//
//  Pure random-encounter scheduler for the Snow Monster encounter
//  (penguinslide-gyu.5). Decides WHEN an encounter fires; owns no nodes, no
//  phases, no side effects — the same separation IcicleSystem has from
//  GameScene, shrunk to pure math so the probability behavior is
//  unit-testable (EncounterTriggerTests, seeded RNG).
//
//  ## GameScene integration contract (wiring bead: penguinslide-gyu.17)
//
//  GameScene calls `update(dt:gameplayElapsed:eligible:)` once per frame
//  during the normal phase and transitions to `.encounterIntro` when it
//  returns true. The CALLER computes both clock inputs and `eligible`:
//
//  - `gameplayElapsed` is the run's *gameplay* clock — the same
//    encounter-time-debt-adjusted elapsed that drives the difficulty ramp
//    (penguinslide-gyu.2). It pauses during encounters, so arming
//    (`minRunTime`) and spacing (`minSpacing`) are measured in icicles-mode
//    seconds: "45 s spacing" means 45 s of normal play after an encounter
//    ends, however long the encounter itself lasted.
//  - `eligible` is true only when: phase == .normal AND isStarted AND
//    !isGameOver AND the penguin is not inside i-frames AND no icicle is
//    currently inside a danger window near the penguin. The last two are
//    the fairness rule from the plan: the intro sweep clears all icicles,
//    so triggering while one was about to legitimately hit would erase a
//    deserved hit (and triggering during i-frames hides the hurt feedback
//    beat). The trigger itself cannot see any of that state — it just
//    trusts the bit.
//
//  ## Clock semantics (asserted by tests — do not change casually)
//
//  - Arming advances with `gameplayElapsed` regardless of eligibility: a
//    run is "old enough" for monsters based on run time alone.
//  - The per-second roll accumulator advances ONLY on eligible frames, and
//    fractional progress is preserved across ineligible gaps (frozen, not
//    reset). Rolling once per accumulated whole second — never per frame —
//    keeps the effective probability framerate-independent.
//  - Spacing is measured in whole ELIGIBLE roll-seconds since the last fire
//    (the same quantum as the rolls themselves), not raw `gameplayElapsed`
//    deltas. Two reasons: (1) ineligible time — including the encounter the
//    last fire started — never counts toward spacing, matching the knob's
//    "seconds of normal play between encounters" intent; (2) comparing
//    float elapsed deltas against the spacing knob at a roll boundary is
//    framerate-sensitive (different dt quantization can flip the gate and
//    desync the RNG draw sequence), while integer roll-second counts make
//    the draw sequence framerate-exact.
//
//  ## Score-bracket gate (gyu.17 amendment)
//
//  On top of the time-domain gates, the random cadence may fire AT MOST
//  ONCE per `Tuning.Encounter.triggerScoreBracket` (250) score points:
//  bracket = floor(score / scoreBracket); a fire consumes its bracket
//  until `reset()`. GameScene passes the live score into `update`. The
//  manual settings-button entry (gyu.30) and the debugForceEncounter
//  hook bypass this gate by construction — they never route through
//  this scheduler at all.
//
//  RNG is injected so tests can seed it; production uses the system RNG.
//

import Foundation

struct EncounterTrigger {

    /// Scheduler knobs, split out from the type so tests can explore
    /// configurations (always-fire probability, uncapped runs) without
    /// touching `Tuning`. Production uses `.default`, which reads the
    /// `Tuning.Encounter` trigger group.
    struct Config {
        /// Gameplay seconds before the first roll may fire.
        var minRunTime: TimeInterval
        /// Minimum gameplay seconds between fires.
        var minSpacing: TimeInterval
        /// Probability rolled once per eligible whole second.
        var perSecondChance: Double
        /// Hard cap on fires until `reset()`.
        var maxPerRun: Int
        /// Score-bracket rate limit (gyu.17 amendment): at most one fire
        /// per `scoreBracket` score points — bracket = floor(score /
        /// scoreBracket); a fire consumes its bracket until `reset()`.
        /// The property default (0 = gate disabled) keeps the pure
        /// time-domain configurations the pre-amendment tests exercise
        /// expressible; production `.default` always enables the gate.
        var scoreBracket: Int = 0

        static let `default` = Config(
            minRunTime: Tuning.Encounter.minRunTime,
            minSpacing: Tuning.Encounter.minSpacing,
            perSecondChance: Tuning.Encounter.perSecondChance,
            maxPerRun: Tuning.Encounter.maxPerRun,
            scoreBracket: Tuning.Encounter.triggerScoreBracket
        )
    }

    let config: Config

    /// Fires reported since init/reset. Read by callers that want to badge
    /// runs ("survived N encounters") without keeping their own count.
    private(set) var fireCount: Int = 0

    /// Whole eligible seconds consumed so far (the roll clock).
    private var rollSecond: Int = 0

    /// `rollSecond` at the most recent fire; nil until the first.
    private var lastFireRollSecond: Int?

    /// Eligible seconds accumulated toward the next whole-second roll.
    private var rollAccumulator: TimeInterval = 0

    /// Score brackets (floor(score / scoreBracket)) that have already
    /// hosted a fire this run — the gyu.17 amendment's rate limit. A Set
    /// (not a high-water mark) so the gate is correct even if a caller
    /// ever feeds a non-monotonic score. Cleared by `reset()`.
    private var consumedScoreBrackets: Set<Int> = []

    private var rng: any RandomNumberGenerator

    init(config: Config = .default,
         rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.config = config
        self.rng = rng
    }

    /// Per-frame tick. Returns true exactly on the frames where an
    /// encounter should begin. `score` is the run's live score, feeding
    /// the score-bracket gate (gyu.17 amendment): the random cadence may
    /// fire at most once per `config.scoreBracket` points. The default 0
    /// is for configs with the gate disabled (`scoreBracket == 0`) —
    /// production callers pass the real score.
    mutating func update(dt: TimeInterval, gameplayElapsed: TimeInterval,
                         score: Int = 0, eligible: Bool) -> Bool {
        guard eligible, dt > 0 else { return false }

        rollAccumulator += dt
        var fired = false
        // A long hitch can bank >1 s; consume every whole second so wall
        // clock and roll count stay in lockstep at any framerate.
        while rollAccumulator >= 1.0 {
            rollAccumulator -= 1.0
            rollSecond += 1
            if canFire(at: gameplayElapsed, score: score), roll() {
                fireCount += 1
                lastFireRollSecond = rollSecond
                if config.scoreBracket > 0 {
                    // Firing consumes the current bracket: no second
                    // random encounter until the score crosses into the
                    // next `scoreBracket`-point bracket.
                    consumedScoreBrackets.insert(score / config.scoreBracket)
                }
                fired = true
            }
        }
        return fired
    }

    /// Re-arms everything for `restart()`: count, spacing, fractional
    /// roll progress, and the score-bracket gate all return to a
    /// fresh-run state.
    mutating func reset() {
        fireCount = 0
        rollSecond = 0
        lastFireRollSecond = nil
        rollAccumulator = 0
        consumedScoreBrackets.removeAll()
    }

    private func canFire(at gameplayElapsed: TimeInterval, score: Int) -> Bool {
        guard gameplayElapsed >= config.minRunTime else { return false }
        guard fireCount < config.maxPerRun else { return false }
        if let last = lastFireRollSecond,
           rollSecond - last < Int(config.minSpacing.rounded(.up)) {
            return false
        }
        // Score-bracket gate (gyu.17 amendment). Like the spacing gate,
        // this blocks BEFORE the draw, so seeded-RNG sequences stay
        // aligned with genuine opportunities. The 0–(bracket−1) bracket
        // is an ordinary bracket: it gets its single encounter too.
        if config.scoreBracket > 0,
           consumedScoreBrackets.contains(score / config.scoreBracket) {
            return false
        }
        return true
    }

    /// One probability draw. Only called when a fire is actually possible,
    /// so seeded-RNG tests see a draw sequence aligned with opportunities.
    private mutating func roll() -> Bool {
        Double.random(in: 0..<1, using: &rng) < config.perSecondChance
    }
}
