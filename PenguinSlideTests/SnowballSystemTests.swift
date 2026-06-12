//
//  SnowballSystemTests.swift
//  PenguinSlideTests
//
//  penguinslide-gyu.13 acceptance suite: snowball spawn/aim math, depth
//  integration, perspective scaling, ground shadows, depth-sorted draw
//  order, corridor clamping, allocation discipline, and reset hygiene.
//
//  Snowballs are fully manually integrated (no SKActions, no physics
//  bodies — KTD3), so unlike the actor suites everything here can be
//  driven synchronously through `update(dt:tilt:)` without a presenting
//  SKView.
//

import XCTest
import SpriteKit
@testable import PenguinSlide

/// SplitMix64 — tiny, well-distributed, fully deterministic per seed
/// (same helper EncounterTriggerTests uses; private there, so redeclared).
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

final class SnowballSystemTests: XCTestCase {

    private let sceneSize = CGSize(width: 390, height: 844)

    /// The system holds its parent (and the Snowball model its nodes)
    /// weakly — the scene owns the tree in production. Tests that don't
    /// inspect the parent would otherwise let it deallocate mid-test,
    /// so the case retains every parent it makes.
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

    private func spawn(_ system: SnowMonsterEncounterSystem,
                       target: CGFloat,
                       vx: CGFloat = 0,
                       zSpeed: CGFloat = Tuning.Encounter.zSpeedStart,
                       driftVx: CGFloat? = 0,
                       seed: UInt64 = 7) -> Snowball? {
        var rng: any RandomNumberGenerator = SplitMix64(seed: seed)
        return system.spawnSnowball(targetWorldX: target,
                                    targetVx: vx,
                                    zSpeed: zSpeed,
                                    driftVx: driftVx,
                                    using: &rng)
    }

    // MARK: - Aim math (pure)

    func testAimAppliesPartialLeadPlusJitter() {
        // The Chase.leadFactor pattern with encounter knobs: predicted =
        // target + vx × flightTime × leadFactor + jitter, unclamped while
        // inside the corridor.
        let aimed = snowballAimWorldX(targetWorldX: 200, targetVx: 100,
                                      flightTime: 2.0, leadFactor: 0.35,
                                      jitter: 12,
                                      corridorCenter: 195, corridorHalfWidth: 280)
        XCTAssertEqual(aimed, 200 + 100 * 2.0 * 0.35 + 12, accuracy: 1e-9)
    }

    func testAimClampsToCorridorBothEdges() {
        let center: CGFloat = 195
        let half = Tuning.Encounter.papiLateralRange
        // Way right (big lead) and way left (big negative jitter): every
        // ball must stay dodgeable by construction.
        let right = snowballAimWorldX(targetWorldX: center + half, targetVx: 1000,
                                      flightTime: 3, leadFactor: 1,
                                      jitter: 500,
                                      corridorCenter: center, corridorHalfWidth: half)
        XCTAssertEqual(right, center + half, accuracy: 1e-9)
        let left = snowballAimWorldX(targetWorldX: center - half, targetVx: -1000,
                                     flightTime: 3, leadFactor: 1,
                                     jitter: -500,
                                     corridorCenter: center, corridorHalfWidth: half)
        XCTAssertEqual(left, center - half, accuracy: 1e-9)
    }

    // MARK: - Flight progress / height (pure, no fold-over)

    func testFlightProgressClampsAndNeverFoldsOver() {
        let spawnZ = Tuning.Encounter.zMonster
        XCTAssertEqual(snowballFlightProgress(z: spawnZ, spawnZ: spawnZ), 0)
        XCTAssertEqual(snowballFlightProgress(z: spawnZ / 2, spawnZ: spawnZ), 0.5,
                       accuracy: 1e-9)
        XCTAssertEqual(snowballFlightProgress(z: 0, spawnZ: spawnZ), 1)
        // Past the camera plane and beyond the spawn: clamped, never
        // inverted (the "no pop or fold-over at any z" guarantee).
        XCTAssertEqual(snowballFlightProgress(z: -50, spawnZ: spawnZ), 1)
        XCTAssertEqual(snowballFlightProgress(z: spawnZ * 2, spawnZ: spawnZ), 0)
        // Degenerate spawn depth must not divide by zero.
        XCTAssertEqual(snowballFlightProgress(z: 10, spawnZ: 0), 1)
    }

    func testFlightHeightLerpsHandDownToArrival() {
        let hand = Tuning.Encounter.snowballSpawnHeight
        let arrival = Tuning.Encounter.snowballArrivalHeight
        XCTAssertEqual(snowballFlightHeight(progress: 0), hand, accuracy: 1e-9)
        XCTAssertEqual(snowballFlightHeight(progress: 1), arrival, accuracy: 1e-9)
        XCTAssertEqual(snowballFlightHeight(progress: 0.5), (hand + arrival) / 2,
                       accuracy: 1e-9)
        // The hand calibration must agree with the monster constants —
        // the spawn-anchor contract below depends on it.
        XCTAssertEqual(hand,
                       SnowMonster.handOffsetFraction.y * Tuning.Encounter.monsterBaseSize,
                       accuracy: 1e-9)
    }

    // MARK: - Depth-keyed draw order (pure)

    func testZPositionDepthSortedWithinReservedBand() {
        let near = Tuning.Encounter.snowballZPositionNear
        let far = Tuning.Encounter.snowballZPositionFar
        XCTAssertEqual(snowballZPosition(z: 0), near, accuracy: 1e-9)
        XCTAssertEqual(snowballZPosition(z: Tuning.Encounter.zMonster), far,
                       accuracy: 1e-9)
        // Strictly monotonic: nearer always draws over farther.
        var last = snowballZPosition(z: Tuning.Encounter.zMonster)
        for z in stride(from: Tuning.Encounter.zMonster - 50, through: 0, by: -50) {
            let zp = snowballZPosition(z: z)
            XCTAssertGreaterThan(zp, last, "zPosition must rise as z drops")
            last = zp
        }
        // Out-of-range depths stay clamped inside the reserved band, and
        // the band respects the encounterRoot z-stack: above the
        // monster's slot, below Papi's 50..59 band.
        XCTAssertEqual(snowballZPosition(z: -100), near, accuracy: 1e-9)
        XCTAssertEqual(snowballZPosition(z: Tuning.Encounter.zMonster * 3), far,
                       accuracy: 1e-9)
        XCTAssertGreaterThan(far, SnowMonster.zPositionInEncounterRoot)
        XCTAssertLessThan(near, PapiAvatar.zPositionInEncounterRoot)
    }

    // MARK: - Spawn anchor (the monster-hand contract)

    /// Acceptance: balls visually START at the monster hands. The ball's
    /// projected spawn (ground point at zMonster + spawnHeight × scale)
    /// must coincide with `SnowMonster.snowballSpawnPoint()` when aimed
    /// along the hand's worldX — exactly, by projection linearity.
    func testSpawnSeatsBallAtMonsterHandPlane() {
        let (system, parent, projector) = makeSystem()
        let monster = SnowMonster(parent: parent, projector: projector)

        guard let ball = spawn(system, target: projector.vanishingX),
              let node = ball.node, let shadow = ball.shadow else {
            return XCTFail("spawn failed after configure")
        }

        // Spawn scale is the projector's zMonster factor (0.25 shipped).
        let spawnScale = projector.depthFactor(z: Tuning.Encounter.zMonster)
        XCTAssertEqual(node.xScale, spawnScale, accuracy: 1e-6)
        XCTAssertEqual(node.yScale, spawnScale, accuracy: 1e-6)

        // Height: hand height exactly (y is worldX-independent under
        // this projection, so this holds for every aim line). Position
        // tolerances are 1e-3: SKNode stores position as Float32
        // (same note as SnowMonsterTests.assertEqual).
        let ground = projector.project(worldX: ball.worldX,
                                       z: Tuning.Encounter.zMonster)
        XCTAssertEqual(node.position.y,
                       ground.point.y + Tuning.Encounter.snowballSpawnHeight * ground.scale,
                       accuracy: 1e-3)
        XCTAssertEqual(node.position.y, monster.snowballSpawnPoint().y, accuracy: 1e-3)
        XCTAssertEqual(node.position.x, ground.point.x, accuracy: 1e-3)

        // Lateral identity: a ball aimed along the hand's own worldX
        // projects exactly onto the hand point.
        let handProjected = projector.project(worldX: monster.snowballSpawnWorldX,
                                              z: Tuning.Encounter.zMonster)
        XCTAssertEqual(handProjected.point.x, monster.snowballSpawnPoint().x,
                       accuracy: 1e-3)

        // Shadow seats on the projector's ground line under the ball.
        XCTAssertEqual(shadow.position.x, ground.point.x, accuracy: 1e-3)
        XCTAssertEqual(shadow.position.y, ground.point.y, accuracy: 1e-3)
        XCTAssertLessThan(shadow.position.y, node.position.y)
    }

    func testSpawnBeforeConfigureReturnsNil() {
        let system = SnowMonsterEncounterSystem()
        var rng: any RandomNumberGenerator = SplitMix64(seed: 1)
        XCTAssertNil(system.spawnSnowball(targetWorldX: 0, targetVx: 0,
                                          zSpeed: 300, using: &rng))
        XCTAssertTrue(system.snowballs.isEmpty)
    }

    // MARK: - Flight: smooth growth, no pop

    /// Acceptance: balls grow smoothly from the hand scale to ~full
    /// scale approaching the camera — strictly monotonic, with a
    /// per-frame delta bound that rules out pops.
    func testFlightGrowsSmoothlyToFullScale() {
        let (system, _, projector) = makeSystem()
        let zSpeed = Tuning.Encounter.zSpeedEnd   // fastest = biggest steps
        guard let spawned = spawn(system, target: projector.vanishingX, zSpeed: zSpeed),
              let node = spawned.node else {
            return XCTFail("spawn failed")
        }

        var lastScale = node.xScale
        XCTAssertEqual(lastScale, projector.depthFactor(z: Tuning.Encounter.zMonster),
                       accuracy: 1e-6)

        let dt: TimeInterval = 1.0 / 60.0
        var frames = 0
        while !system.snowballs.isEmpty {
            system.update(dt: dt, tilt: 0)
            frames += 1
            XCTAssertLessThan(frames, 1000, "ball never reached the camera plane")
            guard !system.snowballs.isEmpty else { break }
            let scale = node.xScale
            XCTAssertGreaterThan(scale, lastScale, "growth must be strictly monotonic")
            XCTAssertLessThan(scale - lastScale, 0.05,
                              "per-frame scale jump reads as a pop")
            XCTAssertLessThanOrEqual(scale, 1.0 + 1e-6,
                                     "scale must never overshoot the camera plane")
            lastScale = scale
        }
        // By the final alive frame the ball is essentially full size.
        XCTAssertGreaterThan(lastScale, 0.9)
        // And the crossing culled the node from the tree (no fold-over
        // frame behind the camera).
        XCTAssertNil(node.parent)
    }

    func testManualSpinAdvancesWithFlightOnly() {
        let (system, _, projector) = makeSystem()
        guard let ball = spawn(system, target: projector.vanishingX),
              let node = ball.node else { return XCTFail("spawn failed") }
        XCTAssertNotEqual(ball.spinSpeed, 0)
        let r0 = node.zRotation
        system.update(dt: 0.5, tilt: 0)
        XCTAssertEqual(node.zRotation, r0 + ball.spinSpeed * 0.5, accuracy: 1e-6)
        // Sentinel frame (dt == 0): zero integration, zero spin.
        let r1 = node.zRotation
        system.update(dt: 0, tilt: 0)
        XCTAssertEqual(node.zRotation, r1, accuracy: 1e-9)
        // No SKAction drives the ball — pause semantics are pure-manual.
        XCTAssertFalse(node.hasActions())
    }

    // MARK: - Draw order with multiple balls

    func testDrawOrderFrontToBackWithMultipleBallsInFlight() {
        let (system, _, projector) = makeSystem()
        // Stagger three balls in depth by spawning between updates.
        _ = spawn(system, target: projector.vanishingX - 100, seed: 1)
        system.update(dt: 0.5, tilt: 0)
        _ = spawn(system, target: projector.vanishingX, seed: 2)
        system.update(dt: 0.5, tilt: 0)
        _ = spawn(system, target: projector.vanishingX + 100, seed: 3)
        system.update(dt: 1.0 / 60.0, tilt: 0)

        let balls = system.snowballs
        XCTAssertEqual(balls.count, 3)
        let sorted = balls.sorted { $0.z < $1.z }   // nearest first
        for (nearer, farther) in zip(sorted, sorted.dropFirst()) {
            XCTAssertLessThan(nearer.z, farther.z)
            XCTAssertGreaterThan(nearer.node!.zPosition, farther.node!.zPosition,
                                 "nearer ball must draw over farther ball")
            // Each shadow rides just below its OWN ball, keeping the
            // pair depth-sorted as a unit.
            XCTAssertEqual(nearer.shadow!.zPosition,
                           nearer.node!.zPosition - SnowMonsterEncounterSystem.shadowZPositionOffset,
                           accuracy: 1e-9)
        }
    }

    // MARK: - Shadows

    /// Acceptance: shadows track the ball's ground line and intensify
    /// exactly like icicle shadows do conceptually — scale and alpha
    /// lerp up the same Feel knobs as flight progresses.
    func testShadowTracksGroundLineAndIntensifies() {
        let (system, _, projector) = makeSystem()
        guard let spawned = spawn(system, target: projector.vanishingX + 150),
              let shadow = spawned.shadow else { return XCTFail("spawn failed") }

        XCTAssertEqual(shadow.alpha, Tuning.Feel.shadowMinAlpha, accuracy: 1e-6)
        var lastAlpha = shadow.alpha
        var lastScale = shadow.xScale

        let dt: TimeInterval = 1.0 / 30.0
        while system.snowballs.count == 1 {
            system.update(dt: dt, tilt: 0)
            guard let ball = system.snowballs.first else { break }
            // Tracks: shadow sits on the projected ground point of the
            // ball's CURRENT worldX/z every frame.
            let ground = projector.project(worldX: ball.worldX, z: ball.z)
            XCTAssertEqual(shadow.position.x, ground.point.x, accuracy: 1e-3)
            XCTAssertEqual(shadow.position.y, ground.point.y, accuracy: 1e-3)
            // Intensifies: monotonic alpha + scale ramps.
            XCTAssertGreaterThan(shadow.alpha, lastAlpha)
            XCTAssertGreaterThan(shadow.xScale, lastScale)
            XCTAssertLessThanOrEqual(shadow.alpha, Tuning.Feel.shadowMaxAlpha + 1e-6)
            lastAlpha = shadow.alpha
            lastScale = shadow.xScale
        }
        // The flight ended near full intensity, and the crossing culled
        // the shadow with its ball.
        XCTAssertGreaterThan(lastAlpha, Tuning.Feel.shadowMaxAlpha * 0.9)
        XCTAssertNil(shadow.parent)
    }

    // MARK: - Drift / corridor

    func testDriftCurvesBallButStaysInCorridor() {
        let (system, _, projector) = makeSystem()
        // Absurd drift override: the per-frame clamp must hold the line.
        guard let spawned = spawn(system, target: projector.vanishingX, driftVx: 4000)
        else { return XCTFail("spawn failed") }
        let startX = spawned.worldX

        system.update(dt: 0.25, tilt: 0)
        guard let ball = system.snowballs.first else { return XCTFail("ball culled early") }
        XCTAssertGreaterThan(ball.worldX, startX, "drift must move the ball laterally")
        XCTAssertLessThanOrEqual(ball.worldX,
                                 projector.vanishingX + Tuning.Encounter.papiLateralRange)

        system.update(dt: 1.0, tilt: 0)
        if let pinned = system.snowballs.first {
            XCTAssertEqual(pinned.worldX,
                           projector.vanishingX + Tuning.Encounter.papiLateralRange,
                           accuracy: 1e-6, "huge drift pins to the corridor edge, never escapes")
        }
    }

    // MARK: - Allocation discipline

    /// Acceptance: steady-state flight is allocation-free at the node
    /// level — nodes are created per THROW only, never per frame.
    func testSteadyStateFlightCreatesNoNodesPerFrame() {
        let (system, parent, projector) = makeSystem()
        let baseline = parent.children.count
        for i in 0..<4 {
            _ = spawn(system, target: projector.vanishingX, seed: UInt64(i + 1))
        }
        let inFlight = parent.children.count
        XCTAssertEqual(inFlight, baseline + 8, "4 balls + 4 shadows, created at throw time")

        // Tiny dt keeps every ball alive across all frames.
        for _ in 0..<240 {
            system.update(dt: 1.0 / 600.0, tilt: 0)
            XCTAssertEqual(parent.children.count, inFlight,
                           "flight loop must never create or leak nodes per frame")
        }
        XCTAssertEqual(system.snowballs.count, 4)
    }

    // MARK: - Culling / reset hygiene

    func testCameraPlaneCrossingCullsBallAndShadow() {
        let (system, parent, projector) = makeSystem()
        let baseline = parent.children.count
        _ = spawn(system, target: projector.vanishingX)
        XCTAssertEqual(parent.children.count, baseline + 2)

        // One giant step drives z far past 0 in a single frame.
        system.update(dt: 60, tilt: 0)
        XCTAssertTrue(system.snowballs.isEmpty)
        XCTAssertEqual(parent.children.count, baseline,
                       "crossing must cull ball AND shadow")
    }

    /// Acceptance: reset() culls all balls + shadows with zero leaks,
    /// verified by node count.
    func testResetCullsAllBallsAndShadowsWithZeroLeaks() {
        let (system, parent, projector) = makeSystem()
        let baseline = parent.children.count
        for i in 0..<5 {
            _ = spawn(system, target: projector.vanishingX, seed: UInt64(i + 11))
        }
        system.update(dt: 0.5, tilt: 0)   // mid-flight
        XCTAssertEqual(parent.children.count, baseline + 10)

        system.reset()
        XCTAssertTrue(system.snowballs.isEmpty)
        XCTAssertEqual(parent.children.count, baseline,
                       "reset leaked nodes into encounterRoot")
        XCTAssertEqual(system.outstandingBalls, 0)

        // Reusable after reset (restart hygiene).
        _ = spawn(system, target: projector.vanishingX)
        XCTAssertEqual(system.snowballs.count, 1)
        XCTAssertEqual(parent.children.count, baseline + 2)
    }

    func testSetActionsPausedTogglesProjectileNodes() {
        let (system, _, projector) = makeSystem()
        guard let ball = spawn(system, target: projector.vanishingX),
              let node = ball.node, let shadow = ball.shadow else {
            return XCTFail("spawn failed")
        }
        system.setActionsPaused(true)
        XCTAssertTrue(node.isPaused)
        XCTAssertTrue(shadow.isPaused)
        system.setActionsPaused(false)
        XCTAssertFalse(node.isPaused)
        XCTAssertFalse(shadow.isPaused)
    }
}
