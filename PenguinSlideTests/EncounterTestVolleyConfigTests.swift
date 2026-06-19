//
//  EncounterTestVolleyConfigTests.swift
//  PenguinSlideTests
//
//  penguinslide-gyu.22: pins the hermetic launch-argument test-volley
//  config (`-encounterTestVolley "count=3 interval=0.8 zSpeed=1200
//  hitRadius=0"`) that EncounterUITests scripts deterministic win/loss
//  volleys with. The grammar, the apply-on-begin semantics, and the
//  hitRadius override in the flight sweep are all test API — a drive-by
//  change must fail here first, in a fast pure-logic test, not a sim
//  UI run (the EncounterDebugStateTests precedent).
//

import XCTest
import SpriteKit
@testable import PenguinSlide

private typealias Overrides = SnowMonsterEncounterSystem.TestVolleyOverrides

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

final class EncounterTestVolleyConfigTests: XCTestCase {

    private let sceneSize = CGSize(width: 390, height: 844)

    /// The system holds its parent weakly (the scene owns the tree in
    /// production), so the case retains every parent it makes.
    private var retainedParents: [SKNode] = []

    override func tearDown() {
        retainedParents.removeAll()
        super.tearDown()
    }

    private func makeSystem() -> (system: SnowMonsterEncounterSystem,
                                  projector: DepthProjector) {
        let parent = SKNode()
        retainedParents.append(parent)
        let projector = DepthProjector(sceneSize: sceneSize)
        let system = SnowMonsterEncounterSystem()
        system.configure(parent: parent, projector: projector)
        return (system, projector)
    }

    // MARK: - Parsing (the launch-argument grammar)

    /// The exact invocation EncounterUITests uses: the flag plus one
    /// spec-string value in the argument list.
    func testParseFullSpecFromArguments() {
        let args = ["appPath", "-encounterTestVolley",
                    "count=3 interval=0.8 zSpeed=1200 hitRadius=0"]
        let parsed = Overrides.parse(arguments: args)
        XCTAssertEqual(parsed,
                       Overrides(count: 3, throwInterval: 0.8,
                                 zSpeed: 1200, lateralHitRadius: 0),
                       "full spec must parse every key; got \(String(describing: parsed))")
    }

    func testParseAcceptsCommaSeparators() {
        let parsed = Overrides.parse(spec: "count=5,interval=1.5")
        XCTAssertEqual(parsed, Overrides(count: 5, throwInterval: 1.5,
                                         zSpeed: nil, lateralHitRadius: nil))
    }

    /// Every key is optional — a partial spec leaves the rest nil so the
    /// Tuning-lerped plan keeps those knobs.
    func testParsePartialSpecLeavesOtherKnobsNil() {
        let parsed = Overrides.parse(spec: "hitRadius=400")
        XCTAssertEqual(parsed, Overrides(count: nil, throwInterval: nil,
                                         zSpeed: nil, lateralHitRadius: 400))
    }

    /// Absent flag, value-less flag, and all-garbage specs must all read
    /// as "no overrides" (nil) — a normal run can never half-configure.
    func testParseDegradesToNilNotHalfConfigured() {
        XCTAssertNil(Overrides.parse(arguments: ["appPath", "-otherFlag"]),
                     "absent flag must yield nil")
        XCTAssertNil(Overrides.parse(arguments: ["appPath", "-encounterTestVolley"]),
                     "flag with no value must yield nil")
        XCTAssertNil(Overrides.parse(spec: "bogus nonsense=12 count=abc"),
                     "unparseable spec must yield nil, not empty overrides")
    }

    // MARK: - Apply-on-begin semantics

    /// begin() lays the overrides over the Tuning-lerped plan: overridden
    /// knobs replace, un-overridden knobs keep their lerped values.
    func testBeginAppliesOverridesOnTopOfLerpedPlan() {
        let (system, _) = makeSystem()
        system.testVolleyOverrides = Overrides(count: 3, throwInterval: nil,
                                               zSpeed: 1200, zAccel: nil, lateralHitRadius: nil)
        system.begin(difficultyProgress: 0)
        XCTAssertEqual(system.plan,
                       SnowMonsterEncounterSystem.VolleyPlan(
                           count: 3,
                           throwInterval: Tuning.Encounter.throwIntervalStart,
                           zSpeed: 1200,
                           zAccel: Tuning.Encounter.zAccel),
                       "overridden knobs replace; un-overridden keep Tuning; got \(String(describing: system.plan))")
    }

    /// reset() (outro teardown / restart) must NOT scrub the overrides —
    /// every begin() of the same app launch gets the same scripted volley.
    func testOverridesSurviveResetAndReapplyOnNextBegin() {
        let (system, _) = makeSystem()
        system.testVolleyOverrides = Overrides(count: 2, throwInterval: 0.5,
                                               zSpeed: nil, lateralHitRadius: nil)
        system.begin(difficultyProgress: 1)
        system.reset()
        system.begin(difficultyProgress: 1)
        XCTAssertEqual(system.plan?.count, 2)
        XCTAssertEqual(system.plan?.throwInterval, 0.5)
        XCTAssertEqual(system.plan?.zSpeed, Tuning.Encounter.zSpeedEnd,
                       "un-overridden zSpeed must still lerp from difficulty progress")
    }

    /// nil overrides (every production run) leave the plan untouched.
    func testNilOverridesLeavePlanIdentical() {
        let (system, _) = makeSystem()
        system.begin(difficultyProgress: 0.5)
        XCTAssertEqual(system.plan,
                       SnowMonsterEncounterSystem.volleyPlan(difficultyProgress: 0.5))
    }

    // MARK: - hitRadius override in the flight sweep

    /// Drive a spawned ball through the sweep until it resolves,
    /// recording which callback fired.
    private enum Outcome { case hit, dodge }
    private func flyOneBall(system: SnowMonsterEncounterSystem,
                            targetWorldX: CGFloat,
                            papiWorldX: CGFloat) -> Outcome? {
        var outcome: Outcome?
        system.papiWorldXProvider = { papiWorldX }
        system.onSnowballHit = { _, _ in outcome = .hit }
        system.onDodge = { _, _ in outcome = .dodge }
        var rng: any RandomNumberGenerator = SplitMix64(seed: 7)
        XCTAssertNotNil(system.spawnSnowball(targetWorldX: targetWorldX,
                                             targetVx: 0,
                                             zSpeed: 600,
                                             driftVx: 0,
                                             using: &rng))
        for _ in 0..<200 where !system.snowballs.isEmpty {
            system.update(dt: 1.0 / 60.0, tilt: 0)
        }
        return outcome
    }

    /// hitRadius=0 (the WIN config): even a dead-on ball can never
    /// connect — it crosses the camera plane as a dodge.
    func testZeroHitRadiusForcesDodgeOnDeadOnBall() {
        let (system, projector) = makeSystem()
        system.testVolleyOverrides = Overrides(count: nil, throwInterval: nil,
                                               zSpeed: nil, lateralHitRadius: 0)
        let outcome = flyOneBall(system: system,
                                 targetWorldX: projector.vanishingX,
                                 papiWorldX: projector.vanishingX)
        XCTAssertEqual(outcome, .dodge,
                       "hitRadius=0 must turn a dead-on ball into a dodge; got \(String(describing: outcome))")
    }

    /// hitRadius=400 (the LOSS config): a ball missing by far more than
    /// the production radius (38) still connects.
    func testWidenedHitRadiusForcesHitOnWideBall() {
        let (system, projector) = makeSystem()
        system.testVolleyOverrides = Overrides(count: nil, throwInterval: nil,
                                               zSpeed: nil, lateralHitRadius: 400)
        let outcome = flyOneBall(system: system,
                                 targetWorldX: projector.vanishingX + 150,
                                 papiWorldX: projector.vanishingX)
        XCTAssertEqual(outcome, .hit,
                       "hitRadius=400 must connect a ~150 pt miss; got \(String(describing: outcome))")
    }

    /// Sanity inverse of the widened case: with NO overrides the same
    /// ~150 pt-wide ball dodges (production radius is 38) — proving the
    /// override, not the geometry, flipped the outcome above.
    func testSameWideBallDodgesWithoutOverrides() {
        let (system, projector) = makeSystem()
        let outcome = flyOneBall(system: system,
                                 targetWorldX: projector.vanishingX + 150,
                                 papiWorldX: projector.vanishingX)
        XCTAssertEqual(outcome, .dodge,
                       "without overrides a ~150 pt miss must dodge; got \(String(describing: outcome))")
    }
}
