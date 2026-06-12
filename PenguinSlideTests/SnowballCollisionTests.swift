//
//  SnowballCollisionTests.swift
//  PenguinSlideTests
//
//  penguinslide-gyu.14 acceptance suite: manual depth-window collision +
//  dodge detection with severity scoring. Two layers, mirroring the bead:
//
//  - PURE: `SnowMonsterEncounterSystem.resolve` / `dodgeSeverity` are
//    static and node-free, so the hit slab, the strict lateral boundary,
//    mid-band drift capture, the segment-overlap tunneling contract, and
//    the severity clamp are all exercised as plain math (DepthProjector-
//    Tests' style), including frame-stepped simulations.
//  - SYSTEM: the live sweep in `update(dt:tilt:)` must resolve each ball
//    EXACTLY once (the `resolved` flag), consume it (node + shadow leave
//    the tree), route hits/dodges through `onSnowballHit` / `onDodge`,
//    and keep the `outstandingBalls` accounting exact for the
//    volley-completion bead (gyu.15).
//
//  I-frame interaction (acceptance note): the system is HP-agnostic —
//  `onSnowballHit` fires for every connecting ball whether or not the
//  penguin's i-frames are active, and the ball is consumed either way
//  (mirroring IcicleSystem.onIcicleHitPenguin's accepted == false
//  handling). `tryTakeHit`'s i-frame gating itself is covered by the
//  Penguin/PapiAvatar suites; here we pin that the hit callback carries
//  the ball's worldX so the receiver CAN make that call.
//

import XCTest
import SpriteKit
@testable import PenguinSlide

/// SplitMix64 — deterministic seeded RNG (same private helper the other
/// encounter suites redeclare).
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

final class SnowballCollisionTests: XCTestCase {

    private let sceneSize = CGSize(width: 390, height: 844)

    // Shipped knobs, named for readable assertions.
    private let window = Tuning.Encounter.depthWindow
    private let hitRadius = Tuning.Encounter.lateralHitRadius
    private let sevRadius = Tuning.Encounter.severityRadius

    /// The system holds its parent weakly — retain every parent a test
    /// creates (SnowballSystemTests' pattern).
    private var retainedParents: [SKNode] = []

    override func tearDown() {
        retainedParents.removeAll()
        super.tearDown()
    }

    private func makeSystem() -> (system: SnowMonsterEncounterSystem,
                                  parent: SKNode,
                                  projector: DepthProjector) {
        let parent = SKNode()
        retainedParents.append(parent)
        let projector = DepthProjector(sceneSize: sceneSize)
        let system = SnowMonsterEncounterSystem()
        system.configure(parent: parent, projector: projector)
        return (system, parent, projector)
    }

    @discardableResult
    private func spawn(_ system: SnowMonsterEncounterSystem,
                       target: CGFloat,
                       zSpeed: CGFloat = Tuning.Encounter.zSpeedStart,
                       seed: UInt64 = 7) -> Snowball? {
        var rng: any RandomNumberGenerator = SplitMix64(seed: seed)
        return system.spawnSnowball(targetWorldX: target,
                                    targetVx: 0,
                                    zSpeed: zSpeed,
                                    driftVx: 0,
                                    using: &rng)
    }

    // MARK: - Pure: hit slab + strict lateral boundary

    func testResolveHitInsideWindowWithLateralOverlap() {
        let res = SnowMonsterEncounterSystem.resolve(
            previousZ: window + 10, z: window - 1,
            ballWorldX: 100, papiWorldX: 100 + hitRadius - 1)
        XCTAssertEqual(res, .hit,
                       "ball at z = depthWindow − 1 with lateral miss < lateralHitRadius must connect")
    }

    func testResolveAboveWindowIsNoneEvenDeadCenter() {
        let res = SnowMonsterEncounterSystem.resolve(
            previousZ: window + 50, z: window + 1,
            ballWorldX: 100, papiWorldX: 100)
        XCTAssertEqual(res, .none,
                       "a dead-center ball still ABOVE the depth window must not connect yet (z = depthWindow + 1)")
    }

    func testLateralBoundaryIsExclusiveAtExactlyHitRadius() {
        // CONTRACT (asserted here, documented on `resolve`): the lateral
        // test is STRICT `<` — a miss of exactly lateralHitRadius is NOT
        // a hit, in-window or at the crossing.
        let inWindow = SnowMonsterEncounterSystem.resolve(
            previousZ: window, z: window / 2,
            ballWorldX: 0, papiWorldX: hitRadius)
        XCTAssertEqual(inWindow, .none,
                       "lateral miss of EXACTLY lateralHitRadius mid-window must miss (boundary is exclusive)")

        let atCrossing = SnowMonsterEncounterSystem.resolve(
            previousZ: 2, z: -1,
            ballWorldX: 0, papiWorldX: hitRadius)
        let expectedSeverity = SnowMonsterEncounterSystem
            .dodgeSeverity(lateralMiss: hitRadius)
        XCTAssertEqual(atCrossing, .dodged(severity: expectedSeverity),
                       "exactly-at-radius ball crossing the plane is the closest possible dodge, not a hit")
        XCTAssertGreaterThan(expectedSeverity, 0,
                             "the closest legal dodge must score > 0 — severityRadius is a separate, wider knob")
        // Just inside the radius IS a hit — the boundary pair.
        let justInside = SnowMonsterEncounterSystem.resolve(
            previousZ: window, z: window / 2,
            ballWorldX: 0, papiWorldX: hitRadius - 0.001)
        XCTAssertEqual(justInside, .hit, "a hair inside lateralHitRadius must connect")
    }

    func testHitTakesPriorityOverDodgeOnTheCrossingFrame() {
        // z ≤ 0 is still inside the one-sided hit slab: a laterally
        // overlapping ball that reaches the plane CONNECTED, it did not
        // get dodged.
        let res = SnowMonsterEncounterSystem.resolve(
            previousZ: 5, z: -2, ballWorldX: 50, papiWorldX: 60)
        XCTAssertEqual(res, .hit,
                       "lateral overlap on the plane-crossing frame must resolve .hit, never .dodged")
    }

    // MARK: - Pure: dodge severity at the crossing

    func testDodgeSeverityProportionalToClosenessAtCrossing() {
        let papi: CGFloat = 195
        // A 60 pt near-miss at the shipped severityRadius (150).
        let near = SnowMonsterEncounterSystem.resolve(
            previousZ: 3, z: -1, ballWorldX: papi + 60, papiWorldX: papi)
        XCTAssertEqual(near, .dodged(severity: 1 - 60 / sevRadius),
                       "severity must be 1 − miss/severityRadius at the crossing frame")

        // Closer shave scores strictly higher.
        guard case .dodged(let sevNear) = near,
              case .dodged(let sevFar) = SnowMonsterEncounterSystem.resolve(
                previousZ: 3, z: -1, ballWorldX: papi + 120, papiWorldX: papi)
        else { return XCTFail("both balls must resolve .dodged") }
        XCTAssertGreaterThan(sevNear, sevFar,
                             "a 60 pt miss must out-score a 120 pt miss — severity ∝ closeness")
    }

    func testFarMissYieldsSeverityZeroButStillResolvesDodged() {
        let papi: CGFloat = 195
        for miss in [sevRadius, sevRadius + 1, sevRadius * 5] {
            let res = SnowMonsterEncounterSystem.resolve(
                previousZ: 3, z: -1, ballWorldX: papi + miss, papiWorldX: papi)
            XCTAssertEqual(res, .dodged(severity: 0),
                           "a \(miss) pt miss (≥ severityRadius \(sevRadius)) must still resolve .dodged, scoring 0")
        }
    }

    func testSeverityClampedToUnitInterval() {
        // Sweep the whole miss range: never below 0, never above 1.
        for miss in stride(from: CGFloat(0), through: sevRadius * 3, by: 7.5) {
            let s = SnowMonsterEncounterSystem.dodgeSeverity(lateralMiss: miss)
            XCTAssertGreaterThanOrEqual(s, 0, "severity must never go negative (miss \(miss))")
            XCTAssertLessThanOrEqual(s, 1, "severity must never exceed 1 (miss \(miss))")
        }
        XCTAssertEqual(SnowMonsterEncounterSystem.dodgeSeverity(lateralMiss: 0), 1,
                       "a zero-distance miss is the definitional severity ceiling")
        // Sign-robust (miss is a distance) and knob-edit safe.
        XCTAssertEqual(SnowMonsterEncounterSystem.dodgeSeverity(lateralMiss: -30),
                       SnowMonsterEncounterSystem.dodgeSeverity(lateralMiss: 30),
                       "severity reads |miss| — a signed input must not clamp to 1")
        XCTAssertEqual(SnowMonsterEncounterSystem.dodgeSeverity(lateralMiss: 10,
                                                                severityRadius: 0), 0,
                       "non-positive severityRadius must degrade to 0, not divide by zero")
    }

    func testSeverityRadiusKnobIsWiderThanHitRadius() {
        // Polish note 1: if severityRadius ≤ lateralHitRadius, every
        // legal dodge (miss ≥ hitRadius) scores 0 and the close-call
        // treatment goes dead. Pin the knob relationship.
        XCTAssertGreaterThan(sevRadius, hitRadius,
                             "severityRadius must exceed lateralHitRadius or all dodge severities collapse to 0")
    }

    // MARK: - Pure: frame-stepped simulations

    /// "Exactly once across consecutive frames" at the math layer: step a
    /// dead-center ball through the window; the FIRST non-.none result is
    /// .hit, on the first frame the swept segment touches the slab. (The
    /// caller-side once-only flag is pinned by the system tests below.)
    func testFrameSteppedHitFiresOnFirstInWindowFrame() {
        let papi: CGFloat = 195
        var z = window * 3
        let dz = window / 7          // several consecutive in-window frames
        var firstResolution: (frame: Int, z: CGFloat, result: SnowballResolution)?
        var frame = 0
        while z > -dz, firstResolution == nil {
            let previousZ = z
            z -= dz
            frame += 1
            let res = SnowMonsterEncounterSystem.resolve(
                previousZ: previousZ, z: z, ballWorldX: papi, papiWorldX: papi)
            if res != .none { firstResolution = (frame, z, res) }
        }
        guard let first = firstResolution else {
            return XCTFail("dead-center ball traversed the window without resolving")
        }
        XCTAssertEqual(first.result, .hit, "dead-center ball must resolve .hit, not dodge")
        XCTAssertLessThan(first.z, window, "hit must fire only once inside the depth window")
        XCTAssertGreaterThan(first.z, 0,
                             "with sub-window steps the hit lands before the plane, frame \(first.frame)")
        XCTAssertGreaterThan(first.z, window - dz - 1e-9,
                             "hit must fire on the FIRST in-window frame, not a later one")
    }

    /// A drifting ball that is laterally CLEAR when it enters the window
    /// but curves inside the radius mid-band must still connect — the
    /// lateral test re-runs every in-window frame.
    func testDriftingBallEnteringRadiusInsideWindowMidBandIsCaught() {
        let papi: CGFloat = 195
        let dt: CGFloat = 1.0 / 60.0
        let zSpeed: CGFloat = 100      // slow: many in-window frames
        let driftVx: CGFloat = -150    // curving toward papi
        var z: CGFloat = 50
        var worldX = papi + 80         // entry miss 80 ≥ hitRadius — clear
        var sawInWindowMiss = false
        var hit: (z: CGFloat, miss: CGFloat)?
        var frames = 0

        while z > 0, hit == nil, frames < 1000 {
            let previousZ = z
            z -= zSpeed * dt
            worldX += driftVx * dt
            frames += 1
            let res = SnowMonsterEncounterSystem.resolve(
                previousZ: previousZ, z: z, ballWorldX: worldX, papiWorldX: papi)
            switch res {
            case .none:
                if z < window { sawInWindowMiss = true }
            case .hit:
                hit = (z, abs(worldX - papi))
            case .dodged:
                XCTFail("ball drifted into the hit radius mid-band; it must not score a dodge")
            }
        }

        guard let hit else {
            return XCTFail("drift into the radius INSIDE the window went undetected")
        }
        XCTAssertTrue(sawInWindowMiss,
                      "test setup: the ball must spend in-window frames laterally CLEAR before drifting in (mid-band capture, not window-entry overlap)")
        XCTAssertLessThan(hit.miss, hitRadius, "hit fired with miss \(hit.miss) ≥ radius")
        XCTAssertGreaterThan(hit.z, 0, "mid-band hit must land before the camera plane")
        XCTAssertLessThan(hit.z, window, "mid-band hit must land inside the window")
    }

    // MARK: - Pure: tunneling guard (segment contract)

    func testShippedKnobsCannotStepAcrossWindowAtThirtyFps() {
        // Knob-coherence guard: at max zSpeed and a 30 fps frame, the
        // depth step stays well inside the window, so the band is
        // sampled at least once with z > 0.
        let worstStep = Tuning.Encounter.zSpeedEnd * (1.0 / 30.0)
        XCTAssertLessThan(worstStep, window,
                          "zSpeedEnd/30fps step (\(worstStep)) must not span the depthWindow (\(window)); if you raise the knobs past this, the segment contract below is what keeps hits detectable")
    }

    func testGiantStepCannotTunnelPastTheWindow() {
        // SEGMENT CONTRACT: the resolver tests the swept segment
        // [z, previousZ] against a ONE-SIDED slab (z' < depthWindow), and
        // resolution runs before the near-plane cull — so even a single
        // step from beyond the window to past the plane resolves.
        let papi: CGFloat = 195
        let throughEverything = SnowMonsterEncounterSystem.resolve(
            previousZ: Tuning.Encounter.zMonster, z: -5,
            ballWorldX: papi, papiWorldX: papi)
        XCTAssertEqual(throughEverything, .hit,
                       "a one-frame step across the ENTIRE flight must still connect a dead-center ball (segment overlap, not point-in-band)")

        let missThroughEverything = SnowMonsterEncounterSystem.resolve(
            previousZ: Tuning.Encounter.zMonster, z: -5,
            ballWorldX: papi + 90, papiWorldX: papi)
        XCTAssertEqual(missThroughEverything,
                       .dodged(severity: 1 - 90 / sevRadius),
                       "a one-frame step past the plane with a lateral miss must resolve .dodged, never vanish unresolved")
    }

    func testMaxSpeedThirtyFpsFrameSteppedBallAlwaysResolves() {
        // Worst legal flight: zSpeedEnd at 30 fps, dead center. The ball
        // must resolve .hit (never reach the cull unresolved), exactly
        // once under the caller-side flag discipline.
        let papi: CGFloat = 195
        let dt: CGFloat = 1.0 / 30.0
        var z = Tuning.Encounter.zMonster
        var resolutions: [SnowballResolution] = []
        var resolved = false
        var frames = 0
        while z > 0, frames < 1000 {
            let previousZ = z
            z -= Tuning.Encounter.zSpeedEnd * dt
            frames += 1
            if !resolved {
                let res = SnowMonsterEncounterSystem.resolve(
                    previousZ: previousZ, z: z, ballWorldX: papi, papiWorldX: papi)
                if res != .none {
                    resolutions.append(res)
                    resolved = true   // exactly-once: the flag the system keeps
                }
            }
        }
        XCTAssertEqual(resolutions, [.hit],
                       "max-speed 30 fps dead-center ball must resolve exactly one .hit before the cull")
    }

    // MARK: - System: hit consumes the ball exactly once

    func testSystemHitFiresExactlyOnceAndConsumesBall() {
        let (system, parent, projector) = makeSystem()
        let baseline = parent.children.count
        guard let ball = spawn(system, target: projector.vanishingX) else {
            return XCTFail("spawn failed after configure")
        }
        XCTAssertEqual(system.outstandingBalls, 1, "spawn must increment outstanding accounting")

        system.papiWorldXProvider = { ball.worldX }   // dead center, stationary
        var hits: [(worldX: CGFloat, point: CGPoint)] = []
        var dodges = 0
        system.onSnowballHit = { worldX, point in hits.append((worldX, point)) }
        system.onDodge = { _, _ in dodges += 1 }

        let dt: TimeInterval = 1.0 / 60.0
        var frames = 0
        var elapsedAtHit: CGFloat?
        while !system.snowballs.isEmpty, frames < 600 {
            system.update(dt: dt, tilt: 0)
            frames += 1
            if hits.count == 1, elapsedAtHit == nil {
                elapsedAtHit = CGFloat(frames) * CGFloat(dt)
            }
        }

        XCTAssertEqual(hits.count, 1,
                       "a dead-center ball must resolve .hit EXACTLY once across consecutive frames (got \(hits.count))")
        XCTAssertEqual(dodges, 0, "a connecting ball must never also report a dodge")
        // The hit landed inside the depth window, not at spawn or cull.
        if let t = elapsedAtHit {
            let zAtHit = Tuning.Encounter.zMonster - Tuning.Encounter.zSpeedStart * t
            XCTAssertLessThan(zAtHit, window,
                              "hit fired at z=\(zAtHit), above the depth window")
            XCTAssertGreaterThan(zAtHit, -Tuning.Encounter.zSpeedStart * CGFloat(dt),
                                 "hit fired after the ball should have been culled")
        }
        // Consumed: callback payload carries the worldX (tryTakeHit's
        // impactX contract), and ball + shadow left the tree.
        XCTAssertEqual(hits.first?.worldX ?? .nan, ball.worldX, accuracy: 1e-9,
                       "hit payload must carry the ball's encounter worldX")
        XCTAssertTrue(system.snowballs.isEmpty, "hit must consume the ball")
        XCTAssertEqual(parent.children.count, baseline,
                       "hit consumption must remove ball AND shadow nodes")
        XCTAssertEqual(system.outstandingBalls, 0,
                       "resolution must decrement outstanding accounting exactly once")
    }

    // MARK: - System: dodge at the plane crossing

    func testSystemDodgeFiresOnceWithSeverityAndScreenPoint() {
        let (system, parent, projector) = makeSystem()
        let baseline = parent.children.count
        guard let ball = spawn(system, target: projector.vanishingX) else {
            return XCTFail("spawn failed after configure")
        }
        let papiX = ball.worldX + 80   // clear of hitRadius, inside sevRadius
        system.papiWorldXProvider = { papiX }
        var hits = 0
        var dodges: [(severity: CGFloat, point: CGPoint)] = []
        system.onSnowballHit = { _, _ in hits += 1 }
        system.onDodge = { severity, point in dodges.append((severity, point)) }

        var frames = 0
        while !system.snowballs.isEmpty, frames < 600 {
            system.update(dt: 1.0 / 60.0, tilt: 0)
            frames += 1
        }

        XCTAssertEqual(hits, 0, "an 80 pt miss must never connect")
        XCTAssertEqual(dodges.count, 1,
                       "the crossing must resolve .dodged exactly once (got \(dodges.count))")
        XCTAssertEqual(dodges.first?.severity ?? .nan, 1 - 80 / sevRadius,
                       accuracy: 1e-6,
                       "severity must be the normalized closeness AT the crossing (miss 80, radius \(sevRadius))")
        // The reported screen point is the camera-plane projection: at
        // z ≤ 0 the projector clamps to the identity plane, so x is the
        // ball's worldX and y the papi plane plus full arrival height.
        XCTAssertEqual(dodges.first?.point.x ?? .nan, ball.worldX, accuracy: 1e-6,
                       "dodge screen point x must be the ball's camera-plane position (floatBonus placement)")
        XCTAssertEqual(dodges.first?.point.y ?? .nan,
                       projector.papiPlaneY + Tuning.Encounter.snowballArrivalHeight,
                       accuracy: 1e-6,
                       "dodge screen point y must sit at the arrival height over the papi plane")
        XCTAssertTrue(system.snowballs.isEmpty, "a dodged ball is culled after exiting the near plane")
        XCTAssertEqual(parent.children.count, baseline, "dodge cull must remove ball AND shadow")
        XCTAssertEqual(system.outstandingBalls, 0)
    }

    func testSystemFarMissDodgeScoresZeroButStillResolves() {
        let (system, _, projector) = makeSystem()
        guard let ball = spawn(system, target: projector.vanishingX) else {
            return XCTFail("spawn failed after configure")
        }
        system.papiWorldXProvider = { ball.worldX + self.sevRadius + 50 }
        var dodges: [CGFloat] = []
        system.onDodge = { severity, _ in dodges.append(severity) }

        var frames = 0
        while !system.snowballs.isEmpty, frames < 600 {
            system.update(dt: 1.0 / 60.0, tilt: 0)
            frames += 1
        }
        XCTAssertEqual(dodges, [0],
                       "a beyond-severityRadius miss still RESOLVES (outstanding accounting needs it) but scores severity 0")
        XCTAssertEqual(system.outstandingBalls, 0)
    }

    // MARK: - System: no target wired (interim bridge)

    func testNoProviderSkipsCollisionAndCullsCleanly() {
        let (system, parent, projector) = makeSystem()
        let baseline = parent.children.count
        spawn(system, target: projector.vanishingX)
        var callbacks = 0
        system.onSnowballHit = { _, _ in callbacks += 1 }
        system.onDodge = { _, _ in callbacks += 1 }
        // papiWorldXProvider stays nil — the pre-gyu.14 flight behavior.
        var frames = 0
        while !system.snowballs.isEmpty, frames < 600 {
            system.update(dt: 1.0 / 60.0, tilt: 0)
            frames += 1
        }
        XCTAssertEqual(callbacks, 0,
                       "with no papiWorldXProvider the collision pass must be skipped entirely")
        XCTAssertEqual(parent.children.count, baseline, "unresolved cull must not leak nodes")
        XCTAssertEqual(system.outstandingBalls, 0,
                       "even an unresolved cull retires the ball from outstanding accounting")
    }

    // MARK: - System: outstanding-ball accounting (volley seam, gyu.15)

    func testOutstandingBallAccountingAcrossMixedResolutions() {
        let (system, _, projector) = makeSystem()
        guard let hitBall = spawn(system, target: projector.vanishingX, seed: 1),
              let dodgeBall = spawn(system, target: projector.vanishingX + 200, seed: 2)
        else { return XCTFail("spawns failed") }
        XCTAssertEqual(system.outstandingBalls, 2, "+1 per spawn")
        // Precondition: the dodge ball is laterally clear of the target.
        XCTAssertGreaterThanOrEqual(abs(dodgeBall.worldX - hitBall.worldX), hitRadius,
                                    "test geometry: second ball must spawn outside the hit radius of the first")

        system.papiWorldXProvider = { hitBall.worldX }
        var hits = 0, dodges = 0
        system.onSnowballHit = { _, _ in hits += 1 }
        system.onDodge = { _, _ in dodges += 1 }

        var frames = 0
        var outstandingAfterHit: Int?
        while !system.snowballs.isEmpty, frames < 600 {
            system.update(dt: 1.0 / 60.0, tilt: 0)
            frames += 1
            if hits == 1, dodges == 0, outstandingAfterHit == nil {
                outstandingAfterHit = system.outstandingBalls
            }
        }
        XCTAssertEqual(hits, 1)
        XCTAssertEqual(dodges, 1)
        XCTAssertEqual(outstandingAfterHit, 1,
                       "after the hit resolves (window) but before the dodge (plane), exactly one ball is outstanding")
        XCTAssertEqual(system.outstandingBalls, 0,
                       "each resolution decrements exactly once — the volley-completion signal")
    }

    func testResetZeroesOutstandingAccounting() {
        let (system, _, projector) = makeSystem()
        for i in 0..<3 { spawn(system, target: projector.vanishingX, seed: UInt64(i + 1)) }
        system.update(dt: 0.5, tilt: 0)   // mid-flight
        XCTAssertEqual(system.outstandingBalls, 3)
        system.reset()
        XCTAssertEqual(system.outstandingBalls, 0,
                       "a torn-down volley must not leave ghost balls in the completion accounting")
    }
}
