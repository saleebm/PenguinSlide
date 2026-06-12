//
//  EncounterTriggerTests.swift
//  PenguinSlideTests
//
//  penguinslide-gyu.5 acceptance suite: seeded-RNG determinism, arming,
//  spacing, per-run caps, eligibility clock semantics, framerate
//  independence, and statistical sanity for the encounter scheduler.
//

import XCTest
@testable import PenguinSlide

// MARK: - Deterministic RNGs

/// SplitMix64 — tiny, well-distributed, fully deterministic per seed.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Always returns 0 → `Double.random(in: 0..<1)` yields 0.0, so every roll
/// fires for any perSecondChance > 0. The "forced to always-fire" generator
/// the bead spec calls for.
private struct AlwaysFireRNG: RandomNumberGenerator {
    mutating func next() -> UInt64 { 0 }
}

final class EncounterTriggerTests: XCTestCase {

    /// Step a trigger through a simulated run, returning the
    /// `gameplayElapsed` values at which it fired. The gameplay clock
    /// advances every frame (eligibility does not stop it — matching
    /// i-frame/danger-window gaps in a live run); `eligible` is evaluated
    /// per frame from the closure.
    private func simulate(
        _ trigger: inout EncounterTrigger,
        duration: TimeInterval,
        dt: TimeInterval,
        startElapsed: TimeInterval = 0,
        eligible: (TimeInterval) -> Bool = { _ in true }
    ) -> [TimeInterval] {
        var fires: [TimeInterval] = []
        var elapsed = startElapsed
        let frames = Int((duration / dt).rounded())
        for _ in 0..<frames {
            elapsed += dt
            if trigger.update(dt: dt, gameplayElapsed: elapsed, eligible: eligible(elapsed)) {
                fires.append(elapsed)
            }
        }
        return fires
    }

    // MARK: - Arming (minRunTime)

    func testNeverFiresBeforeMinRunTimeEvenWithAlwaysFireRNG() {
        let config = EncounterTrigger.Config(
            minRunTime: 20, minSpacing: 0, perSecondChance: 1.0, maxPerRun: .max)
        var trigger = EncounterTrigger(config: config, rng: AlwaysFireRNG())

        let fires = simulate(&trigger, duration: 30, dt: 1.0 / 60.0)

        XCTAssertFalse(fires.isEmpty, "Sanity: an always-fire RNG with chance 1.0 must fire after arming")
        XCTAssertGreaterThanOrEqual(
            fires[0], config.minRunTime,
            "First fire at t=\(fires[0]) violates the minRunTime=\(config.minRunTime) arming gate even though every roll was forced to fire")
        XCTAssertLessThanOrEqual(
            fires[0], config.minRunTime + 1.1,
            "With always-fire rolls the first fire should land at the first whole-second roll after arming (≤ \(config.minRunTime + 1.1)), got \(fires[0]) — the arming clock is running slow")
    }

    // MARK: - Spacing (minSpacing)

    func testNoFireUntilMinSpacingElapsesAfterAFire() {
        let config = EncounterTrigger.Config(
            minRunTime: 0, minSpacing: 45, perSecondChance: 1.0, maxPerRun: .max)
        var trigger = EncounterTrigger(config: config, rng: AlwaysFireRNG())
        let dt = 1.0 / 60.0

        let fires = simulate(&trigger, duration: 200, dt: dt)

        XCTAssertGreaterThanOrEqual(fires.count, 4,
                                    "Sanity: a 200 s always-fire run with 45 s spacing should produce ≥ 4 fires, got \(fires.count)")
        for i in 1..<fires.count {
            let gap = fires[i] - fires[i - 1]
            XCTAssertGreaterThanOrEqual(
                gap, config.minSpacing - dt,
                "Fires #\(i - 1) (t=\(fires[i - 1])) and #\(i) (t=\(fires[i])) are only \(gap) s apart — minSpacing=\(config.minSpacing) violated")
        }
    }

    // MARK: - Per-run cap and reset()

    func testMaxPerRunCapHoldsOverLongRunAndResetRearms() {
        let config = EncounterTrigger.Config(
            minRunTime: 0, minSpacing: 0, perSecondChance: 1.0, maxPerRun: 2)
        var trigger = EncounterTrigger(config: config, rng: AlwaysFireRNG())

        let firstRun = simulate(&trigger, duration: 1000, dt: 1.0 / 30.0)
        XCTAssertEqual(firstRun.count, config.maxPerRun,
                       "maxPerRun=\(config.maxPerRun) must cap an arbitrarily long always-fire run; got \(firstRun.count) fires over 1000 s")
        XCTAssertEqual(trigger.fireCount, config.maxPerRun,
                       "fireCount must report the capped total")

        trigger.reset()
        XCTAssertEqual(trigger.fireCount, 0, "reset() must zero fireCount")

        let secondRun = simulate(&trigger, duration: 1000, dt: 1.0 / 30.0)
        XCTAssertEqual(secondRun.count, config.maxPerRun,
                       "After reset() the trigger must re-arm and allow another \(config.maxPerRun) fires; got \(secondRun.count)")
    }

    // MARK: - Framerate independence

    func testSameSeedAndWallClockFiresAtSameTimesAt30And120Fps() {
        // minRunTime sits OFF the whole-second roll grid (5.5): rolls land at
        // elapsed ≈ N.0, so an on-grid threshold would make the arming
        // comparison a float knife-edge where dt quantization could admit a
        // roll at one framerate and not the other. Production knobs (20/45 s)
        // are coarse enough that a one-roll difference is irrelevant there.
        let config = EncounterTrigger.Config(
            minRunTime: 5.5, minSpacing: 10, perSecondChance: 0.15, maxPerRun: .max)
        let seed: UInt64 = 0xDEADBEEF
        let duration: TimeInterval = 300.5 // off-second end avoids boundary-edge mismatch

        var trigger30 = EncounterTrigger(config: config, rng: SplitMix64(seed: seed))
        var trigger120 = EncounterTrigger(config: config, rng: SplitMix64(seed: seed))

        let fires30 = simulate(&trigger30, duration: duration, dt: 1.0 / 30.0)
        let fires120 = simulate(&trigger120, duration: duration, dt: 1.0 / 120.0)

        XCTAssertFalse(fires30.isEmpty, "Sanity: 300 s at chance 0.15 should fire at least once")
        XCTAssertEqual(fires30.count, fires120.count,
                       "Same seed + same wall clock must produce the same number of fires at 30 fps (\(fires30.count): \(fires30)) and 120 fps (\(fires120.count): \(fires120)) — the roll cadence is framerate-dependent")
        for (i, (t30, t120)) in zip(fires30, fires120).enumerated() {
            XCTAssertEqual(t30, t120, accuracy: 1.0 / 30.0 + 1e-6,
                           "Fire #\(i) differs across framerates beyond one coarse frame: 30 fps t=\(t30) vs 120 fps t=\(t120)")
        }
    }

    // MARK: - Eligibility clock semantics

    func testIneligibleFramesSuppressFiresButArmingClockAdvances() {
        // Documented contract: arming rides gameplayElapsed (advances while
        // ineligible); the roll accumulator is frozen (no banked rolls).
        let config = EncounterTrigger.Config(
            minRunTime: 20, minSpacing: 0, perSecondChance: 1.0, maxPerRun: .max)
        var trigger = EncounterTrigger(config: config, rng: AlwaysFireRNG())
        let dt = 1.0 / 60.0

        // Ineligible well past the arming threshold.
        let suppressed = simulate(&trigger, duration: 30, dt: dt, eligible: { _ in false })
        XCTAssertTrue(suppressed.isEmpty,
                      "eligible=false must suppress all fires even with always-fire rolls past minRunTime; got fires at \(suppressed)")

        // Eligibility begins at t=30 (already armed since t=20).
        let fires = simulate(&trigger, duration: 5, dt: dt, startElapsed: 30)
        XCTAssertFalse(fires.isEmpty, "Trigger must fire once eligibility begins on an armed run")
        XCTAssertEqual(fires[0], 31.0, accuracy: 2 * dt,
                       "First fire should land one whole ELIGIBLE second after eligibility begins (t≈31): earlier (≈30) means ineligible frames banked rolls; later (≈51) means the arming clock wrongly froze while ineligible. Got \(fires[0])")
    }

    func testFractionalRollProgressIsPreservedAcrossIneligibleGaps() {
        let config = EncounterTrigger.Config(
            minRunTime: 0, minSpacing: 0, perSecondChance: 1.0, maxPerRun: .max)
        var trigger = EncounterTrigger(config: config, rng: AlwaysFireRNG())
        let dt = 0.01

        // 0.6 eligible seconds: below one whole second, no roll yet.
        let phaseA = simulate(&trigger, duration: 0.6, dt: dt)
        XCTAssertTrue(phaseA.isEmpty, "No roll may happen before one whole eligible second accumulates; got \(phaseA)")

        // 10 ineligible seconds: accumulator must freeze at 0.6.
        let phaseB = simulate(&trigger, duration: 10, dt: dt, startElapsed: 0.6, eligible: { _ in false })
        XCTAssertTrue(phaseB.isEmpty, "Ineligible frames must not roll; got \(phaseB)")

        // Eligibility resumes at t=10.6; the remaining 0.4 eligible seconds
        // complete the first whole second → fire at t≈11.0.
        let phaseC = simulate(&trigger, duration: 2, dt: dt, startElapsed: 10.6)
        XCTAssertFalse(phaseC.isEmpty, "Trigger must fire after the fractional second completes")
        XCTAssertEqual(phaseC[0], 11.0, accuracy: 2 * dt,
                       "Fractional roll progress (0.6 s) must survive the ineligible gap: expected the fire ≈ 0.4 s after resuming (t≈11.0), got \(phaseC[0]) — ≈11.6 means the accumulator was reset, ≈10.6 means ineligible time accumulated")
    }

    // MARK: - Score-bracket gate (penguinslide-gyu.17 amendment)

    /// Score-aware sibling of `simulate`: feeds the live score into the
    /// trigger (the GameScene contract) and records it at each fire so
    /// bracket assertions read the exact value the gate saw.
    private func simulateWithScore(
        _ trigger: inout EncounterTrigger,
        duration: TimeInterval,
        dt: TimeInterval,
        score: (TimeInterval) -> Int
    ) -> [(time: TimeInterval, score: Int)] {
        var fires: [(time: TimeInterval, score: Int)] = []
        var elapsed: TimeInterval = 0
        let frames = Int((duration / dt).rounded())
        for _ in 0..<frames {
            elapsed += dt
            let s = score(elapsed)
            if trigger.update(dt: dt, gameplayElapsed: elapsed, score: s, eligible: true) {
                fires.append((time: elapsed, score: s))
            }
        }
        return fires
    }

    /// Gate-only config: always-fire rolls with every time-domain gate
    /// open, so the score bracket is the ONLY thing limiting fires.
    private func bracketOnlyConfig(bracket: Int = 1000) -> EncounterTrigger.Config {
        EncounterTrigger.Config(minRunTime: 0, minSpacing: 0,
                                perSecondChance: 1.0, maxPerRun: .max,
                                scoreBracket: bracket)
    }

    /// Amendment case (a): two triggers never fire within the same
    /// 1000-point bracket — across a ramping score, every fire's bracket
    /// is unique even though every roll is forced to fire.
    func testTwoTriggersNeverFireWithinTheSameScoreBracket() {
        var trigger = EncounterTrigger(config: bracketOnlyConfig(), rng: AlwaysFireRNG())

        // 50 pts/s over 60 s: score sweeps 0 → 3000 through 4 brackets.
        let fires = simulateWithScore(&trigger, duration: 60, dt: 1.0 / 60.0) { Int($0 * 50) }

        XCTAssertFalse(fires.isEmpty, "Sanity: always-fire rolls must fire at least once")
        let brackets = fires.map { $0.score / 1000 }
        XCTAssertEqual(Set(brackets).count, brackets.count,
                       "Two fires landed in the same 1000-point bracket — the rate limit is broken: \(fires)")
    }

    /// Amendment case (b): the gate is per-bracket, not per-run — each
    /// successive bracket the score enters may host exactly one fire.
    func testTriggerCanFireInEachSuccessiveBracket() {
        var trigger = EncounterTrigger(config: bracketOnlyConfig(), rng: AlwaysFireRNG())

        // 100 pts/s over 35 s: bracket boundaries at t = 10/20/30, so the
        // run traverses brackets 0…3 with ≥ 4 roll-seconds inside each.
        let fires = simulateWithScore(&trigger, duration: 35, dt: 1.0 / 60.0) { Int($0 * 100) }

        let brackets = fires.map { $0.score / 1000 }
        XCTAssertEqual(brackets, brackets.sorted(),
                       "Fires must arrive in bracket order; got \(fires)")
        XCTAssertEqual(Set(brackets), Set([0, 1, 2, 3]),
                       "Every bracket the score traversed must host exactly one encounter; got brackets \(brackets) from \(fires)")
        XCTAssertEqual(fires.count, 4,
                       "Exactly one fire per traversed bracket expected; got \(fires)")
    }

    /// Amendment case (c): restart clears the gate — reset() forgets all
    /// consumed brackets along with the rest of the run state.
    func testResetClearsTheScoreBracketGate() {
        var trigger = EncounterTrigger(config: bracketOnlyConfig(), rng: AlwaysFireRNG())
        let dt = 1.0 / 60.0

        let first = simulateWithScore(&trigger, duration: 30, dt: dt) { _ in 500 }
        XCTAssertEqual(first.count, 1,
                       "A score parked inside one bracket hosts exactly one fire; got \(first)")

        let starved = simulateWithScore(&trigger, duration: 30, dt: dt) { _ in 500 }
        XCTAssertTrue(starved.isEmpty,
                      "The consumed bracket must stay closed for the rest of the run; got \(starved)")

        trigger.reset()
        let fresh = simulateWithScore(&trigger, duration: 30, dt: dt) { _ in 500 }
        XCTAssertEqual(fresh.count, 1,
                       "reset() must clear bracket consumption so a new run can host an encounter again; got \(fresh)")
    }

    /// Amendment case (d): the 0–999 bracket is an ordinary bracket — a
    /// brand-new run whose score never leaves it still gets its single
    /// encounter, at the first opportunity.
    func testFirstBracketIsAllowedItsSingleEncounter() {
        var trigger = EncounterTrigger(config: bracketOnlyConfig(), rng: AlwaysFireRNG())
        let dt = 1.0 / 60.0

        // 10 pts/s over 60 s: score peaks at 600, never leaving bracket 0.
        let fires = simulateWithScore(&trigger, duration: 60, dt: dt) { Int($0 * 10) }

        XCTAssertEqual(fires.count, 1,
                       "The 0–999 bracket hosts exactly one encounter; got \(fires)")
        XCTAssertEqual(fires[0].time, 1.0, accuracy: 2 * dt,
                       "The bracket-0 fire should land at the first whole-second roll (t≈1), not be deferred; got \(fires[0].time)")
    }

    /// `scoreBracket == 0` disables the gate entirely — the documented
    /// escape hatch the pure time-domain tests above rely on (their
    /// configs omit the field, taking the 0 property default).
    func testScoreBracketZeroDisablesTheGate() {
        let config = EncounterTrigger.Config(
            minRunTime: 0, minSpacing: 0, perSecondChance: 1.0, maxPerRun: .max)
        var trigger = EncounterTrigger(config: config, rng: AlwaysFireRNG())

        let fires = simulateWithScore(&trigger, duration: 10, dt: 1.0 / 60.0) { _ in 500 }

        XCTAssertGreaterThan(fires.count, 1,
                             "scoreBracket 0 must mean 'no bracket gate' (one fire per roll-second here); got \(fires)")
    }

    // MARK: - Statistical sanity

    func testSeededFireCountMatchesConfiguredChanceOverLongRun() {
        // 120 s eligible run, no spacing/cap interference. Expected fires =
        // 120 × perSecondChance = 36; binomial σ = √(120 × 0.3 × 0.7) ≈ 5.0.
        // ±4σ band [16, 56] is generous but still catches a per-frame roll
        // (which at 60 fps would yield thousands) or a broken accumulator
        // (zero or one fire).
        let chance = 0.3
        let config = EncounterTrigger.Config(
            minRunTime: 0, minSpacing: 0, perSecondChance: chance, maxPerRun: .max)
        var trigger = EncounterTrigger(config: config, rng: SplitMix64(seed: 42))

        let fires = simulate(&trigger, duration: 120, dt: 1.0 / 60.0)
        let expected = 120.0 * chance

        XCTAssertGreaterThanOrEqual(Double(fires.count), 16,
                                    "Seeded 120 s run at chance \(chance) fired only \(fires.count) times (expected ≈ \(expected)) — rolls are being lost")
        XCTAssertLessThanOrEqual(Double(fires.count), 56,
                                 "Seeded 120 s run at chance \(chance) fired \(fires.count) times (expected ≈ \(expected)) — probability is being over-rolled (per-frame rolls?)")
        print("EncounterTrigger statistical sanity: \(fires.count) fires over 120 s at perSecondChance=\(chance) (expected ≈ \(expected))")
    }

    // MARK: - Default config

    func testDefaultConfigMirrorsTuningEncounterKnobs() {
        let config = EncounterTrigger.Config.default
        XCTAssertEqual(config.minRunTime, Tuning.Encounter.minRunTime,
                       "Config.default.minRunTime drifted from Tuning.Encounter")
        XCTAssertEqual(config.minSpacing, Tuning.Encounter.minSpacing,
                       "Config.default.minSpacing drifted from Tuning.Encounter")
        XCTAssertEqual(config.perSecondChance, Tuning.Encounter.perSecondChance,
                       "Config.default.perSecondChance drifted from Tuning.Encounter")
        XCTAssertEqual(config.maxPerRun, Tuning.Encounter.maxPerRun,
                       "Config.default.maxPerRun drifted from Tuning.Encounter")
        XCTAssertEqual(config.scoreBracket, Tuning.Encounter.triggerScoreBracket,
                       "Config.default.scoreBracket drifted from Tuning.Encounter — production must always carry the gyu.17 rate-limit gate")
        XCTAssertGreaterThan(config.scoreBracket, 0,
                             "Production config must have the score-bracket gate ENABLED (a 0 knob would silently disable the gyu.17 amendment)")
    }
}
