//
//  EncounterOutroTests.swift
//  PenguinSlideTests
//
//  Unit coverage for the outro transition's seams (penguinslide-gyu.18):
//  the SnowMonster melt state machine (the 2026-06-11 amendment — the
//  exit waits for the monster melting into its puddle), the melt
//  spritesheet contract, Penguin.recenter()'s position-only partial
//  reset (hp / i-frames must carry over the outro untouched), and
//  IcicleSystem.holdSpawns(for:)'s post-encounter grace hold.
//
//  Like SnowMonsterTests / PapiAvatarTests: SKActions don't tick
//  without a presenting SKView, so assertions here are SYNCHRONOUS
//  (state set on a transition call, guard rejections, keyed-action
//  presence, manual-integration results). The full choreography —
//  score arithmetic across the outro, hearts continuity on the HUD,
//  the ten back-to-back-encounters stress — is the EncounterUITests
//  bead's job (gyu.22), driven via debugForceEncounter and the
//  encounterState debug label.
//

import XCTest
import SpriteKit
@testable import PenguinSlide

final class EncounterOutroTests: XCTestCase {

    private let sceneSize = CGSize(width: 390, height: 844)

    private func makeMonster() -> (monster: SnowMonster, parent: SKNode) {
        let parent = SKNode()
        let projector = DepthProjector(sceneSize: sceneSize)
        let monster = SnowMonster(parent: parent, projector: projector)
        return (monster, parent)
    }

    private func makePenguin() -> Penguin {
        Penguin(parent: SKNode(), baseY: 170, leftBound: 30, rightBound: 360)
    }

    // MARK: - SnowMonster melt state machine

    /// melt() enters .melting, runs a keyed clip, and is exactly-once:
    /// a second melt on an already-melting monster is rejected.
    func testMeltEntersMeltingStateExactlyOnce() {
        let (monster, _) = makeMonster()

        XCTAssertTrue(monster.melt())
        XCTAssertEqual(monster.state, .melting)
        XCTAssertTrue(monster.node.hasActions(),
                      "melt must run its clip on the node")
        XCTAssertFalse(monster.melt(), "second melt must be rejected")
        XCTAssertEqual(monster.state, .melting)
    }

    /// .melting is terminal until reset(): every other cycle transition
    /// rejects it — a melted monster can never roar, telegraph, or
    /// throw before the per-entry scrub.
    func testMeltingRejectsAllOtherTransitions() {
        let (monster, _) = makeMonster()
        XCTAssertTrue(monster.melt())

        XCTAssertFalse(monster.roar())
        XCTAssertFalse(monster.telegraph())
        XCTAssertFalse(monster.throwSnowball(onRelease: {
            XCTFail("a melting monster must never release a ball")
        }))
        XCTAssertFalse(monster.setLane(worldX: 50),
                       "lane moves are .idle-only and must reject .melting")
        XCTAssertEqual(monster.state, .melting)
    }

    /// The win can land while the monster is mid-cycle (a stale
    /// telegraph hold, or the last throw's follow-through still
    /// playing) — melt must be legal from any non-melting state and
    /// scrub the telegraph leftovers (tint, scale breathe).
    func testMeltLegalFromTelegraphAndThrowing() {
        let (telegraphing, _) = makeMonster()
        XCTAssertTrue(telegraphing.telegraph())
        XCTAssertTrue(telegraphing.melt())
        XCTAssertEqual(telegraphing.state, .melting)
        XCTAssertEqual(telegraphing.node.colorBlendFactor, 0,
                       "melt must scrub the telegraph warning tint")

        let (throwing, _) = makeMonster()
        XCTAssertTrue(throwing.throwSnowball(onRelease: {}))
        XCTAssertTrue(throwing.melt())
        XCTAssertEqual(throwing.state, .melting)
    }

    /// reset() — the outro midpoint's encounterSystem.reset() path —
    /// returns a melted monster to a clean idle for the next entry.
    func testResetRestoresIdleFromMelting() {
        let (monster, _) = makeMonster()
        XCTAssertTrue(monster.melt())

        monster.reset()

        XCTAssertEqual(monster.state, .idle)
        XCTAssertTrue(monster.telegraph(),
                      "a reset monster must accept the next cycle")
    }

    // MARK: - Melt sheet contract

    /// The melt clip's frame slicing must match the manifest contract
    /// (spritecook-assets.json: snow_monster_melt, 16 frames — the real
    /// SpriteCook sheet swapped in by penguinslide-6m5). The sheet and
    /// the slicer both bind through this count — a mismatch bleeds
    /// frame boundaries.
    func testMeltFramesMatchManifestContract() {
        let frames = EncounterAnimations.frames(for: .monsterMelt)
        XCTAssertEqual(frames.count, 16)
        XCTAssertFalse(EncounterAnimations.loops(.monsterMelt),
                       "melt is a one-shot that holds its final puddle frame")
    }

    /// The melt is duration-stretched (timePerFrame = duration / count),
    /// not fixed-fps: meltDuration is the knob's contract regardless of
    /// the sheet's frame count. Sanity-pin the knob itself.
    func testMeltDurationKnobIsPositive() {
        XCTAssertGreaterThan(Tuning.Encounter.meltDuration, 0)
        XCTAssertGreaterThan(Tuning.Encounter.outroDuration, 0)
        XCTAssertGreaterThan(Tuning.Encounter.postEncounterGrace, 0)
    }

    // MARK: - Penguin.recenter (position-only partial reset)

    /// recenter() restores the mid-strip stance — position, rotation,
    /// slide velocity (including the stray encounter knockback vx that
    /// tryTakeHit pushed onto the hidden side-view body) — while hp and
    /// the armed i-frames carry over UNTOUCHED. The hearts-continuity
    /// acceptance ("entered 3, hit once, shows 2") rides on exactly
    /// this: the penguin stays the single HP source across the outro.
    func testRecenterRestoresPositionButPreservesHpAndIFrames() {
        let penguin = makePenguin()
        let centerX: CGFloat = (30 + 360) / 2
        let baseY: CGFloat = 170
        let startHp = penguin.hp

        // One encounter hit: hp drops, i-frames arm, knockback lands on
        // the (conceptually hidden) side-view motion.
        XCTAssertTrue(penguin.tryTakeHit(from: penguin.node.position.x - 10))
        XCTAssertEqual(penguin.hp, startHp - 1)
        XCTAssertTrue(penguin.isInvulnerable)
        XCTAssertNotEqual(penguin.vx, 0, "knockback should have set a stray vx")

        // Drift the node off-center, as an encounter would leave it.
        penguin.node.position = CGPoint(x: centerX + 87, y: baseY + 12)
        penguin.node.zRotation = 0.3

        penguin.recenter()

        XCTAssertEqual(penguin.node.position.x, centerX, accuracy: 1e-3)
        XCTAssertEqual(penguin.node.position.y, baseY, accuracy: 1e-3)
        XCTAssertEqual(penguin.node.zRotation, 0)
        XCTAssertEqual(penguin.vx, 0, "stray knockback vx must be cleared")
        // The continuity contract: damage state is NOT reset.
        XCTAssertEqual(penguin.hp, startHp - 1, "hp must carry over the outro")
        XCTAssertTrue(penguin.isInvulnerable, "armed i-frames must survive recenter")
    }

    /// recenter() must not rewind the hit clock either: i-frames armed
    /// before the outro still expire on schedule afterwards (the clock
    /// keeps its single authority — only reset() rewinds it).
    func testRecenterDoesNotRewindHitClock() {
        let penguin = makePenguin()
        XCTAssertTrue(penguin.tryTakeHit(from: 0))
        XCTAssertTrue(penguin.isInvulnerable)

        penguin.recenter()

        // Tick past the i-frame window on the same (untouched) clock.
        penguin.tickHitClock(dt: Tuning.Penguin.iFrameDuration + 0.05)
        XCTAssertFalse(penguin.isInvulnerable,
                       "i-frames must expire on the original schedule after recenter")
    }

    // MARK: - IcicleSystem.holdSpawns (post-encounter grace)

    /// The grace hold: after holdSpawns(for: g), no icicle spawns for at
    /// least g + the fresh spawn interval of update time, then spawning
    /// resumes — and `elapsed` (the ramp clock) is the caller's frozen
    /// gameplay clock throughout, so cadence picks up where it left off.
    func testHoldSpawnsDelaysFirstSpawnByAtLeastTheGrace() {
        let scene = SKScene(size: sceneSize)
        let parent = SKNode()
        scene.addChild(parent)
        let camera = SKCameraNode()
        scene.addChild(camera)
        let penguin = Penguin(parent: parent, baseY: 100,
                              leftBound: 30, rightBound: 360)
        let icicles = IcicleSystem(scene: scene, parent: parent,
                                   camera: camera, penguin: penguin,
                                   iceTopY: 230, iceLandingY: 126,
                                   iceLeftX: 30, iceRightX: 360,
                                   sceneSize: sceneSize)

        func icicleCount() -> Int {
            var n = 0
            parent.enumerateChildNodes(withName: "icicle") { _, _ in n += 1 }
            return n
        }

        // The intro midpoint's reset() already ran in the real flow:
        // timer 0, interval back to spawnIntervalStart.
        icicles.reset()
        let grace = Tuning.Encounter.postEncounterGrace
        icicles.holdSpawns(for: grace)

        // Frozen-during-encounter gameplay clock, well past the run-start
        // grace so the spawn gate is purely the held timer.
        let rampElapsed: TimeInterval = 50
        let dt: TimeInterval = 0.05
        let firstSpawnDue = grace + Tuning.Icicle.spawnIntervalStart

        var t: TimeInterval = 0
        while t + dt < firstSpawnDue - 1e-9 {
            icicles.update(dt: dt, elapsed: rampElapsed)
            t += dt
            XCTAssertEqual(icicleCount(), 0,
                           "icicle spawned \(t)s after return — due no sooner than \(firstSpawnDue)s (grace \(grace) + interval)")
        }

        // A few steps past the due point must produce the first spawn.
        for _ in 0..<8 { icicles.update(dt: dt, elapsed: rampElapsed) }
        XCTAssertGreaterThan(icicleCount(), 0,
                             "spawning must resume once the grace + interval elapse")
    }
}
