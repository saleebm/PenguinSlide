//
//  VolleyOrchestrationTests.swift
//  PenguinSlideTests
//
//  penguinslide-gyu.15 acceptance suite: volley plan math (count /
//  interval / zSpeed lerped by difficulty progress), throw scheduling,
//  completion accounting ("onVolleyComplete only after the LAST ball
//  RESOLVES — never at the last throw"), deterministic termination,
//  reset/begin re-entry hygiene, and the pauseActions freeze seam.
//
//  The cycle is driven entirely by the system's own dt clock (manual
//  integration doctrine), so a full volley runs synchronously through
//  `update(dt:tilt:)` without a presenting SKView — monster-attached
//  cases exercise the guarded actor transitions plus the release
//  watchdog (SKAction completions never fire headless, by design the
//  watchdog covers exactly that stall).
//

import XCTest
import SpriteKit
@testable import PenguinSlide

/// SplitMix64 — tiny, well-distributed, fully deterministic per seed
/// (same helper SnowballSystemTests uses; private there, so redeclared).
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class VolleyOrchestrationTests: XCTestCase {

    private let sceneSize = CGSize(width: 390, height: 844)

    /// The system holds its parent weakly (the scene owns the tree in
    /// production), so the case retains every parent it makes.
    private var retainedParents: [SKNode] = []

    override func tearDown() {
        retainedParents.removeAll()
        super.tearDown()
    }

    private func makeSystem(seed: UInt64 = 9) -> (system: SnowMonsterEncounterSystem,
                                                  parent: SKNode,
                                                  projector: DepthProjector) {
        let parent = SKNode()
        retainedParents.append(parent)
        let projector = DepthProjector(sceneSize: sceneSize)
        let system = SnowMonsterEncounterSystem()
        system.configure(parent: parent, projector: projector)
        system.volleyRNG = SplitMix64(seed: seed)
        return (system, parent, projector)
    }

    /// Tick the system at 60 fps until `stop` returns true or `cap`
    /// simulated seconds elapse; returns the simulated time spent.
    @discardableResult
    private func tick(_ system: SnowMonsterEncounterSystem,
                      cap: TimeInterval,
                      until stop: () -> Bool) -> TimeInterval {
        let dt = 1.0 / 60.0
        var t: TimeInterval = 0
        while !stop() && t < cap {
            system.update(dt: dt, tilt: 0)
            t += dt
        }
        return t
    }

    // MARK: - Plan math (pure lerp by difficulty progress)

    func testPlanAtProgressZeroYieldsStartValues() {
        let plan = SnowMonsterEncounterSystem.volleyPlan(difficultyProgress: 0)
        XCTAssertEqual(plan.count, Tuning.Encounter.volleyCountStart)
        XCTAssertEqual(plan.throwInterval, Tuning.Encounter.throwIntervalStart,
                       accuracy: 1e-9)
        XCTAssertEqual(plan.zSpeed, Tuning.Encounter.zSpeedStart, accuracy: 1e-9)
    }

    func testPlanAtProgressOneYieldsEndValues() {
        let plan = SnowMonsterEncounterSystem.volleyPlan(difficultyProgress: 1)
        XCTAssertEqual(plan.count, Tuning.Encounter.volleyCountEnd)
        XCTAssertEqual(plan.throwInterval, Tuning.Encounter.throwIntervalEnd,
                       accuracy: 1e-9)
        XCTAssertEqual(plan.zSpeed, Tuning.Encounter.zSpeedEnd, accuracy: 1e-9)
    }

    func testPlanMidpointLerpsAllThreeKnobs() {
        let plan = SnowMonsterEncounterSystem.volleyPlan(difficultyProgress: 0.5)
        let expectedCount = Int((Double(Tuning.Encounter.volleyCountStart)
            + Double(Tuning.Encounter.volleyCountEnd - Tuning.Encounter.volleyCountStart) * 0.5)
            .rounded())
        XCTAssertEqual(plan.count, expectedCount)
        XCTAssertEqual(plan.throwInterval,
                       Tuning.Encounter.throwIntervalStart
                        + (Tuning.Encounter.throwIntervalEnd - Tuning.Encounter.throwIntervalStart) * 0.5,
                       accuracy: 1e-9)
        XCTAssertEqual(plan.zSpeed,
                       Tuning.Encounter.zSpeedStart
                        + (Tuning.Encounter.zSpeedEnd - Tuning.Encounter.zSpeedStart) * 0.5,
                       accuracy: 1e-9)
        // Sweep-the-knobs form (parameterized defaults): exact midpoint.
        let swept = SnowMonsterEncounterSystem.volleyPlan(difficultyProgress: 0.5,
                                                          countStart: 4, countEnd: 10,
                                                          intervalStart: 2.0, intervalEnd: 1.0,
                                                          zSpeedStart: 100, zSpeedEnd: 300)
        XCTAssertEqual(swept, SnowMonsterEncounterSystem.VolleyPlan(count: 7,
                                                                    throwInterval: 1.5,
                                                                    zSpeed: 200,
                                                                    zAccel: Tuning.Encounter.zAccel))
    }

    func testPlanProgressClampsOutsideUnitRange() {
        XCTAssertEqual(SnowMonsterEncounterSystem.volleyPlan(difficultyProgress: -3),
                       SnowMonsterEncounterSystem.volleyPlan(difficultyProgress: 0))
        XCTAssertEqual(SnowMonsterEncounterSystem.volleyPlan(difficultyProgress: 7),
                       SnowMonsterEncounterSystem.volleyPlan(difficultyProgress: 1))
    }

    // MARK: - Completion accounting (the bead's core acceptance)

    /// Scripted no-input volley with a stationary target on the aim
    /// line: every ball resolves (hit or dodge — jitter decides), and
    /// `onVolleyComplete` fires exactly once, strictly AFTER the last
    /// resolution — never at the last throw.
    func testVolleyCompleteFiresOnlyAfterLastBallResolves() {
        let (system, _, projector) = makeSystem(seed: 21)
        system.papiWorldXProvider = { projector.vanishingX }

        var events: [String] = []
        system.onSnowballHit = { _, _ in events.append("hit") }
        system.onDodge = { _, _ in events.append("dodge") }
        system.onVolleyComplete = { events.append("complete") }

        system.begin(difficultyProgress: 0)
        guard let plan = system.plan else { return XCTFail("begin computed no plan") }
        XCTAssertEqual(plan.count, Tuning.Encounter.volleyCountStart)

        // Phase 1: run until every throw has been made. At that moment
        // the volley must NOT be complete — the last ball just left the
        // hand and is still in flight.
        tick(system, cap: 60) { system.throwsMade == plan.count }
        XCTAssertEqual(system.throwsMade, plan.count, "throws never exhausted (hang)")
        XCTAssertFalse(events.contains("complete"),
                       "completion fired at the last THROW; it must wait for the last RESOLUTION")
        XCTAssertGreaterThan(system.outstandingBalls, 0)

        // Phase 2: let the in-flight balls finish.
        tick(system, cap: 60) { events.contains("complete") }
        XCTAssertEqual(events.last, "complete", "completion must be the final event")
        XCTAssertEqual(events.filter { $0 != "complete" }.count, plan.count,
                       "every planned ball must resolve exactly once (hit or dodge)")
        XCTAssertEqual(events.filter { $0 == "complete" }.count, 1)
        XCTAssertEqual(system.outstandingBalls, 0)

        // Exactly-once: further frames spawn nothing and never re-fire.
        tick(system, cap: 10) { false }
        XCTAssertEqual(events.filter { $0 == "complete" }.count, 1)
        XCTAssertEqual(system.throwsMade, plan.count)
        XCTAssertTrue(system.snowballs.isEmpty)
    }

    /// Target parked far outside the corridor: every ball crosses the
    /// camera plane laterally clear — an all-dodge volley still
    /// terminates through the same accounting.
    func testAllDodgeVolleyResolvesEveryBallAndCompletes() {
        let (system, _, projector) = makeSystem(seed: 5)
        // Aim clamps to the corridor; the target sits far beyond
        // lateralHitRadius of any reachable line, so no ball can hit.
        system.papiWorldXProvider = {
            projector.vanishingX + Tuning.Encounter.papiLateralRange * 10
        }

        var hits = 0, dodges = 0, completions = 0
        system.onSnowballHit = { _, _ in hits += 1 }
        system.onDodge = { _, _ in dodges += 1 }
        system.onVolleyComplete = { completions += 1 }

        system.begin(difficultyProgress: 0)
        tick(system, cap: 60) { completions > 0 }
        XCTAssertEqual(completions, 1, "all-dodge volley must still complete (no hang)")
        XCTAssertEqual(hits, 0)
        XCTAssertEqual(dodges, system.plan?.count ?? -1)
    }

    /// No target wired at all (GameScene's interim bridge): balls cull
    /// unresolved at the camera plane, and the outstanding accounting
    /// still drives completion — the phase machine can never park.
    func testVolleyWithNoTargetStillTerminatesDeterministically() {
        let (system, parent, _) = makeSystem(seed: 3)
        let baseline = parent.children.count

        var completions = 0
        system.onVolleyComplete = { completions += 1 }

        system.begin(difficultyProgress: 1)   // densest, fastest volley
        let took = tick(system, cap: 90) { completions > 0 }
        XCTAssertEqual(completions, 1, "providerless volley hung (took \(took)s)")
        XCTAssertEqual(system.throwsMade, Tuning.Encounter.volleyCountEnd)
        XCTAssertEqual(system.outstandingBalls, 0)
        XCTAssertEqual(parent.children.count, baseline, "balls/shadows leaked")
    }

    // MARK: - Scheduling semantics

    /// dt == 0 sentinel frames (phase transitions, settings/app resume)
    /// inject no scheduling time: no telegraph, no throw, no spawn.
    func testSentinelFramesInjectNoSchedulingTime() {
        let (system, _, _) = makeSystem()
        system.begin(difficultyProgress: 0)
        for _ in 0..<600 {
            system.update(dt: 0, tilt: 0)
        }
        XCTAssertEqual(system.throwsMade, 0)
        XCTAssertTrue(system.snowballs.isEmpty)
        XCTAssertEqual(system.outstandingBalls, 0)
    }

    /// Releases pace at the plan cadence: each cycle is recovery gap +
    /// telegraph + wind-up, so consecutive releases sit ~(interval +
    /// telegraphDuration + throwReleaseTime) apart on the dt clock.
    func testThrowCadenceFollowsPlanInterval() {
        let (system, _, _) = makeSystem(seed: 11)
        system.begin(difficultyProgress: 0)
        guard let plan = system.plan else { return XCTFail("no plan") }

        let dt = 1.0 / 60.0
        var t: TimeInterval = 0
        var releaseTimes: [TimeInterval] = []
        var lastThrows = 0
        while releaseTimes.count < 3 && t < 30 {
            system.update(dt: dt, tilt: 0)
            t += dt
            if system.throwsMade > lastThrows {
                lastThrows = system.throwsMade
                releaseTimes.append(t)
            }
        }
        XCTAssertEqual(releaseTimes.count, 3, "cycle stalled before three releases")

        let expectedGap = plan.throwInterval
            + Tuning.Encounter.telegraphDuration
            + SnowMonster.throwReleaseTime
        for (a, b) in zip(releaseTimes, releaseTimes.dropFirst()) {
            // One-frame quantization slack on each phase boundary.
            XCTAssertEqual(b - a, expectedGap, accuracy: 4 * dt,
                           "release cadence must follow the plan interval")
        }
        // First release needs no recovery gap: telegraph + wind-up only.
        XCTAssertEqual(releaseTimes[0],
                       Tuning.Encounter.telegraphDuration + SnowMonster.throwReleaseTime,
                       accuracy: 4 * dt)
    }

    // MARK: - Monster-driven cycle (guarded transitions + watchdog)

    /// With the actor attached, the cycle drives telegraph → throw in
    /// order through the guarded transitions, and the release watchdog
    /// spawns the ball even when the throw clip's SKAction completion
    /// never arrives (headless here; a paused/stalled action in
    /// production) — deterministic termination by construction.
    func testMonsterCycleTelegraphsThenThrowsWithWatchdogRelease() {
        let (system, parent, projector) = makeSystem(seed: 17)
        let monster = SnowMonster(parent: parent, projector: projector)
        system.monster = monster

        system.begin(difficultyProgress: 0)
        XCTAssertEqual(monster.state, .idle)

        // First real frame starts the wind-up.
        system.update(dt: 1.0 / 60.0, tilt: 0)
        XCTAssertEqual(monster.state, .telegraph)
        XCTAssertEqual(system.throwsMade, 0)

        // Telegraph elapses → throw commits (no ball yet: the release
        // signal is still pending). Cap carries frame-quantization slack.
        tick(system, cap: Tuning.Encounter.telegraphDuration + 0.25) {
            monster.state == .throwing
        }
        XCTAssertEqual(monster.state, .throwing)
        XCTAssertEqual(system.throwsMade, 0)
        XCTAssertTrue(system.snowballs.isEmpty)

        // Headless, onRelease never fires — the watchdog must release.
        let watchdogCap = SnowMonster.throwReleaseTime
            + SnowMonsterEncounterSystem.releaseWatchdogGrace + 1
        tick(system, cap: watchdogCap) { system.throwsMade == 1 }
        XCTAssertEqual(system.throwsMade, 1,
                       "watchdog must force the release when the clip stalls")
        XCTAssertEqual(system.snowballs.count, 1)
    }

    // MARK: - Lifecycle: reset / re-entry / pause

    /// reset() mid-volley abandons it wholesale: balls leave the tree,
    /// the accounting re-arms at zero, the monster returns to idle, and
    /// NO completion can fire from the torn-down volley afterwards.
    func testResetMidVolleyAbandonsWholesale() {
        let (system, parent, projector) = makeSystem(seed: 29)
        let monster = SnowMonster(parent: parent, projector: projector)
        system.monster = monster
        let baseline = parent.children.count

        var completions = 0
        system.onVolleyComplete = { completions += 1 }

        system.begin(difficultyProgress: 0)
        tick(system, cap: 60) { system.throwsMade >= 2 }
        XCTAssertGreaterThanOrEqual(system.throwsMade, 2)

        system.reset()
        XCTAssertTrue(system.snowballs.isEmpty)
        XCTAssertEqual(system.outstandingBalls, 0)
        XCTAssertEqual(system.throwsMade, 0)
        XCTAssertNil(system.plan)
        XCTAssertEqual(monster.state, .idle)
        XCTAssertEqual(parent.children.count, baseline, "reset leaked encounter nodes")

        // A dead volley stays dead: no spawns, no ghost completion.
        tick(system, cap: 15) { false }
        XCTAssertEqual(completions, 0)
        XCTAssertEqual(system.throwsMade, 0)
        XCTAssertTrue(system.snowballs.isEmpty)
    }

    /// begin() after reset() yields a clean second encounter: the full
    /// volley runs again from a cold state (idempotent re-entry).
    func testBeginAfterResetYieldsCleanSecondEncounter() {
        let (system, parent, projector) = makeSystem(seed: 41)
        system.papiWorldXProvider = { projector.vanishingX }
        let baseline = parent.children.count

        var resolutions = 0, completions = 0
        system.onSnowballHit = { _, _ in resolutions += 1 }
        system.onDodge = { _, _ in resolutions += 1 }
        system.onVolleyComplete = { completions += 1 }

        system.begin(difficultyProgress: 0)
        tick(system, cap: 60) { completions == 1 }
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(resolutions, Tuning.Encounter.volleyCountStart)

        system.reset()
        resolutions = 0

        // Second entry at a different difficulty: fresh plan, fresh
        // accounting, full traversal, zero node leaks.
        system.begin(difficultyProgress: 1)
        XCTAssertEqual(system.plan?.count, Tuning.Encounter.volleyCountEnd)
        XCTAssertEqual(system.throwsMade, 0)
        tick(system, cap: 90) { completions == 2 }
        XCTAssertEqual(completions, 2, "second encounter after reset never completed")
        XCTAssertEqual(resolutions, Tuning.Encounter.volleyCountEnd)
        XCTAssertEqual(system.outstandingBalls, 0)
        XCTAssertEqual(parent.children.count, baseline)
    }

    /// pauseActions() (the triggerGameOver freeze seam, mirroring
    /// pauseShardActions) freezes every encounter visual this system
    /// owns: the monster's clips AND the projectile nodes.
    func testPauseActionsFreezesMonsterAndProjectileNodes() {
        let (system, parent, projector) = makeSystem(seed: 13)
        let monster = SnowMonster(parent: parent, projector: projector)
        system.monster = monster

        var rng: any RandomNumberGenerator = SplitMix64(seed: 1)
        guard let ball = system.spawnSnowball(targetWorldX: projector.vanishingX,
                                              targetVx: 0,
                                              zSpeed: 300,
                                              using: &rng),
              let node = ball.node, let shadow = ball.shadow else {
            return XCTFail("spawn failed")
        }

        system.pauseActions()
        XCTAssertTrue(monster.node.isPaused)
        XCTAssertTrue(node.isPaused)
        XCTAssertTrue(shadow.isPaused)

        // The two-way seam unfreezes everything (settings-resume path).
        system.setActionsPaused(false)
        XCTAssertFalse(monster.node.isPaused)
        XCTAssertFalse(node.isPaused)
        XCTAssertFalse(shadow.isPaused)
    }
}
