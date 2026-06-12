//
//  SnowMonsterTests.swift
//  PenguinSlideTests
//
//  Unit coverage for the SnowMonster actor (penguinslide-gyu.12):
//  projector-correct placement, state-machine transition guards, the
//  throw-release contract consumed by the snowball system (.13), the
//  spawn-point seam, reset hygiene, and the shuffle knob gate.
//
//  SKActions don't tick without a presenting SKView, so these tests
//  deliberately assert SYNCHRONOUS behavior only: state set on a
//  transition call, guard rejections, constants, and geometry. Clip
//  completion / release timing is exercised end-to-end by the
//  encounter XCUI suite.
//

import XCTest
import SpriteKit
@testable import PenguinSlide

final class SnowMonsterTests: XCTestCase {

    private let sceneSize = CGSize(width: 390, height: 844)

    private func makeMonster(worldX: CGFloat? = nil) -> (monster: SnowMonster,
                                                         parent: SKNode,
                                                         projector: DepthProjector) {
        let parent = SKNode()
        let projector = DepthProjector(sceneSize: sceneSize)
        let monster = SnowMonster(parent: parent, projector: projector, worldX: worldX)
        return (monster, parent, projector)
    }

    /// SKNode stores position as Float32 internally, so projected
    /// CGPoints come back with ~1e-5 rounding — compare per-component
    /// with a tolerance instead of exact CGPoint equality.
    private func assertEqual(_ actual: CGPoint, _ expected: CGPoint,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 1e-3, "x", file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 1e-3, "y", file: file, line: line)
    }

    // MARK: Placement

    /// Acceptance: renders at the projector-correct scale/position for
    /// zMonster. With the shipped knobs (focal 300, zMonster 900) the
    /// scale must be exactly 0.25, and the node must sit on the
    /// projected ground station of its lane.
    func testSpawnsAtProjectorStationAndScale() {
        let (monster, parent, projector) = makeMonster()

        let expected = projector.project(worldX: projector.vanishingX,
                                         z: Tuning.Encounter.zMonster)
        assertEqual(monster.node.position, expected.point)
        XCTAssertEqual(monster.node.xScale, expected.scale, accuracy: 1e-9)
        XCTAssertEqual(monster.node.yScale, expected.scale, accuracy: 1e-9)
        XCTAssertEqual(expected.scale,
                       Tuning.Encounter.focal / (Tuning.Encounter.focal + Tuning.Encounter.zMonster),
                       accuracy: 1e-9)
        XCTAssertTrue(monster.node.parent === parent)
        XCTAssertEqual(monster.laneWorldX, projector.vanishingX)
        XCTAssertEqual(monster.state, .idle)
        // Feet anchor: the projected point is the ground station.
        XCTAssertEqual(monster.node.anchorPoint, CGPoint(x: 0.5, y: 0))
    }

    func testCustomLanePlacement() {
        let lane: CGFloat = 120
        let (monster, _, projector) = makeMonster(worldX: lane)
        let expected = projector.project(worldX: lane, z: Tuning.Encounter.zMonster)
        assertEqual(monster.node.position, expected.point)
        XCTAssertEqual(monster.laneWorldX, lane)
    }

    // MARK: State machine guards

    func testTelegraphOnlyFromIdle() {
        let (monster, _, _) = makeMonster()
        XCTAssertTrue(monster.telegraph())
        XCTAssertEqual(monster.state, .telegraph)
        // Re-telegraphing mid-telegraph is rejected.
        XCTAssertFalse(monster.telegraph())
        XCTAssertEqual(monster.state, .telegraph)
    }

    func testThrowLegalFromTelegraphAndIdle() {
        // Normal cycle: telegraph → throw.
        let (cycled, _, _) = makeMonster()
        cycled.telegraph()
        XCTAssertTrue(cycled.throwSnowball(onRelease: {}))
        XCTAssertEqual(cycled.state, .throwing)
        // No double-throw while one is in flight.
        XCTAssertFalse(cycled.throwSnowball(onRelease: {}))

        // Variant path: orchestrator may skip the wind-up.
        let (direct, _, _) = makeMonster()
        XCTAssertTrue(direct.throwSnowball(onRelease: {}))
        XCTAssertEqual(direct.state, .throwing)
    }

    /// Acceptance: roar must never disturb the throw cycle — it's
    /// rejected from every non-idle state, and while roaring the cycle
    /// transitions are rejected right back.
    func testRoarCannotDisturbCycleAndViceVersa() {
        let (monster, _, _) = makeMonster()

        monster.telegraph()
        XCTAssertFalse(monster.roar())
        monster.throwSnowball(onRelease: {})
        XCTAssertFalse(monster.roar())
        monster.reset()

        XCTAssertTrue(monster.roar())
        XCTAssertEqual(monster.state, .roaring)
        XCTAssertFalse(monster.telegraph())
        XCTAssertFalse(monster.throwSnowball(onRelease: {}))
        XCTAssertFalse(monster.roar())
        XCTAssertEqual(monster.state, .roaring)
    }

    // MARK: Throw-release contract (.13)

    /// The release constants are the snowball system's spawn-sync
    /// contract: the index must split the throw clip into non-empty
    /// wind-up and follow-through segments, and the exposed release
    /// time must agree with index/fps.
    func testThrowReleaseConstantsAreCoherentWithClip() {
        let throwFrameCount = EncounterAnimations.frames(for: .monsterThrow).count
        XCTAssertGreaterThan(SnowMonster.throwReleaseFrameIndex, 0)
        XCTAssertLessThan(SnowMonster.throwReleaseFrameIndex, throwFrameCount)
        XCTAssertEqual(SnowMonster.throwReleaseTime,
                       Double(SnowMonster.throwReleaseFrameIndex) / SnowMonster.animationFps,
                       accuracy: 1e-9)
    }

    /// Calibration pin for the delivered SpriteCook throw sheet
    /// (penguinslide-gyu.24, sha12 ddb4e56b4da9): the ball departs on
    /// frame index 8 from the viewer-left hand held high. If the art
    /// is swapped again, recalibrate the constants AND this pin
    /// together (see spritecook-assets.json snow_monster_throw.wiring).
    func testThrowReleaseCalibrationMatchesDeliveredArt() {
        XCTAssertEqual(SnowMonster.throwReleaseFrameIndex, 8)
        XCTAssertEqual(SnowMonster.handOffsetFraction.x, -0.35, accuracy: 1e-9)
        XCTAssertEqual(SnowMonster.handOffsetFraction.y, 0.84, accuracy: 1e-9)
        // The hand must stay inside the sprite footprint.
        XCTAssertLessThanOrEqual(abs(SnowMonster.handOffsetFraction.x), 0.5)
        XCTAssertGreaterThan(SnowMonster.handOffsetFraction.y, 0)
        XCTAssertLessThanOrEqual(SnowMonster.handOffsetFraction.y, 1)
    }

    func testSnowballSpawnSeamGeometry() {
        let (monster, _, _) = makeMonster()

        XCTAssertEqual(monster.snowballSpawnZ, Tuning.Encounter.zMonster)
        XCTAssertEqual(monster.snowballSpawnWorldX,
                       monster.laneWorldX
                           + SnowMonster.handOffsetFraction.x * Tuning.Encounter.monsterBaseSize,
                       accuracy: 1e-9)

        let onScreen = Tuning.Encounter.monsterBaseSize * monster.node.xScale
        let spawn = monster.snowballSpawnPoint()
        XCTAssertEqual(spawn.x,
                       monster.node.position.x + SnowMonster.handOffsetFraction.x * onScreen,
                       accuracy: 1e-9)
        XCTAssertEqual(spawn.y,
                       monster.node.position.y + SnowMonster.handOffsetFraction.y * onScreen,
                       accuracy: 1e-9)
        // The hand is above the feet — spawn must sit higher than the
        // ground station and offset toward the throwing side.
        XCTAssertGreaterThan(spawn.y, monster.node.position.y)
    }

    // MARK: Reset

    /// Acceptance: all actions stop cleanly on reset() — keyed actions
    /// gone, idle loop restored, tint/scale/lane back to home.
    func testResetRestoresCleanIdleFromAnyState() {
        let (monster, _, projector) = makeMonster()

        monster.telegraph()
        monster.throwSnowball(onRelease: { XCTFail("pending release must be cancelled by reset") })
        monster.setActionsPaused(true)
        monster.reset()

        XCTAssertEqual(monster.state, .idle)
        XCTAssertFalse(monster.node.isPaused)
        XCTAssertEqual(monster.node.colorBlendFactor, 0)
        XCTAssertEqual(monster.laneWorldX, projector.vanishingX)
        assertEqual(monster.node.position,
                    projector.project(worldX: projector.vanishingX,
                                      z: Tuning.Encounter.zMonster).point)
        XCTAssertEqual(monster.node.xScale,
                       projector.depthFactor(z: Tuning.Encounter.zMonster),
                       accuracy: 1e-9)
        // Only the idle "frames" loop should be running.
        XCTAssertNotNil(monster.node.action(forKey: "frames"))
        XCTAssertNil(monster.node.action(forKey: "telegraph"))
        XCTAssertNil(monster.node.action(forKey: "shuffle"))
        // And the cycle is immediately drivable again.
        XCTAssertTrue(monster.telegraph())
    }

    // MARK: Lane control

    func testShuffleGatedByKnobDefaultOff() {
        let (monster, _, projector) = makeMonster()
        let before = monster.laneWorldX

        var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
        // v1 ships with the knob off — shuffle must be a hard no-op.
        XCTAssertFalse(Tuning.Encounter.monsterShuffleEnabled,
                       "v1 fairness default changed — revisit shuffle tests")
        XCTAssertFalse(monster.shuffleLane(using: &rng))
        XCTAssertEqual(monster.laneWorldX, before)
        assertEqual(monster.node.position,
                    projector.project(worldX: before, z: Tuning.Encounter.zMonster).point)
    }

    func testSetLaneOnlyFromIdle() {
        let (monster, _, projector) = makeMonster()

        XCTAssertTrue(monster.setLane(worldX: 150, animated: false))
        XCTAssertEqual(monster.laneWorldX, 150)
        assertEqual(monster.node.position,
                    projector.project(worldX: 150, z: Tuning.Encounter.zMonster).point)
        // Spawn seam tracks the lane.
        XCTAssertEqual(monster.snowballSpawnWorldX,
                       150 + SnowMonster.handOffsetFraction.x * Tuning.Encounter.monsterBaseSize,
                       accuracy: 1e-9)

        monster.telegraph()
        XCTAssertFalse(monster.setLane(worldX: 0, animated: false))
        XCTAssertEqual(monster.laneWorldX, 150)
    }
}
