//
//  EncounterFXTests.swift
//  PenguinSlideTests
//
//  Unit coverage for the encounter impact/dodge FX helper
//  (penguinslide-gyu.16, reworked by penguinslide-bo8): the powder-puff
//  placement/sizing (anchored at the impact point, just in front of the
//  avatar, scaled by depth scale, softened when i-frames absorbed the
//  hit), the gravity snow-chunk burst (manual integration: launch,
//  gravity pull, lifetime fade, removal), the hit-keyed camera shake,
//  the pure haptic mapping, dodge speed-line accents, and the
//  pause/reset lifecycle (game-over freeze + restart hygiene).
//
//  Like SnowMonsterTests/PapiAvatarTests: SKActions don't tick without
//  a presenting SKView, so assertions are SYNCHRONOUS — node presence,
//  keyed-action presence, tracked-array state, isPaused flags. Chunks
//  are tick-driven (NOT SKActions), so their motion IS assertable here
//  by calling fx.update(dt:) directly.
//

import XCTest
import SpriteKit
@testable import PenguinSlide

final class EncounterFXTests: XCTestCase {

    private let sceneSize = CGSize(width: 390, height: 844)

    private func make() -> (fx: EncounterFX, parent: SKNode, camera: SKCameraNode) {
        let parent = SKNode()
        let camera = SKCameraNode()
        let fx = EncounterFX(parent: parent, camera: camera, sceneSize: sceneSize)
        return (fx, parent, camera)
    }

    // MARK: - Haptic mapping (pure)

    /// Accepted hit → medium, i-frame-absorbed hit → light: EXACTLY the
    /// icicle path's distinction (onIcicleHitPenguin's hapticHit /
    /// hapticLight split).
    func testHitHapticMatchesIcicleAcceptedDistinction() {
        XCTAssertEqual(EncounterFX.hitHaptic(accepted: true), .medium)
        XCTAssertEqual(EncounterFX.hitHaptic(accepted: false), .light)
    }

    /// Dodge haptic fires (light) only at/above the severity threshold,
    /// so wide dodges stay haptic-silent.
    func testDodgeHapticRespectsSeverityThreshold() {
        let threshold = Tuning.Encounter.dodgeHapticSeverity
        XCTAssertEqual(EncounterFX.dodgeHaptic(severity: 1.0), .light)
        XCTAssertEqual(EncounterFX.dodgeHaptic(severity: threshold), .light)
        XCTAssertEqual(EncounterFX.dodgeHaptic(severity: threshold - 0.01), .none)
        XCTAssertEqual(EncounterFX.dodgeHaptic(severity: 0), .none)
    }

    // MARK: - Hit: powder puff

    /// The puff anchors AT the impact screen point, in the draw-order
    /// slot just in front of the avatar (the "into Papi" read), at the
    /// base size for depth scale 1, animating its one-shot, and is
    /// tracked for pause/reset.
    func testHitPuffAnchorsAtImpactPointJustInFrontOfAvatar() {
        let (fx, parent, _) = make()
        let point = CGPoint(x: 123, y: 310)

        fx.playHitBurst(at: point, depthScale: 1.0, accepted: true)

        guard let puff = parent.childNode(withName: "snowballPuff") as? SKSpriteNode else {
            return XCTFail("expected a snowballPuff node under the parent")
        }
        // SKNode stores position as Float32 — tolerance compare (the
        // PapiAvatarTests caveat).
        XCTAssertEqual(puff.position.x, point.x, accuracy: 1e-3)
        XCTAssertEqual(puff.position.y, point.y, accuracy: 1e-3)
        XCTAssertEqual(puff.zPosition, PapiAvatar.zPositionInEncounterRoot + 1)
        XCTAssertEqual(puff.zPosition, EncounterFX.burstZPosition)
        XCTAssertEqual(puff.size.width, Tuning.Encounter.impactPuffBaseSize, accuracy: 1e-3)
        XCTAssertEqual(puff.alpha, 1.0, accuracy: 1e-6)
        XCTAssertTrue(puff.hasActions(), "one-shot swell/fade should be running")
        XCTAssertTrue(fx.activeFX.contains { $0 === puff })
    }

    /// Puff footprint scales linearly with the avatar's depth scale.
    func testHitPuffScalesByAvatarDepthScale() {
        let (fx, parent, _) = make()
        fx.playHitBurst(at: .zero, depthScale: 0.5, accepted: true)

        let puff = parent.childNode(withName: "snowballPuff") as? SKSpriteNode
        XCTAssertEqual(puff?.size.width ?? 0,
                       Tuning.Encounter.impactPuffBaseSize * 0.5, accuracy: 1e-3)
    }

    /// I-frame-absorbed hit dials the whole impact soft: smaller/dimmer
    /// puff and fewer chunks — the icicle "softer pop" treatment.
    func testAbsorbedHitImpactIsSofter() {
        let (fx, parent, _) = make()
        fx.playHitBurst(at: .zero, depthScale: 1.0, accepted: false)

        guard let puff = parent.childNode(withName: "snowballPuff") as? SKSpriteNode else {
            return XCTFail("expected a snowballPuff node under the parent")
        }
        XCTAssertEqual(puff.size.width,
                       Tuning.Encounter.impactPuffBaseSize * Tuning.Encounter.impactFXSoftenScale,
                       accuracy: 1e-3)
        XCTAssertLessThan(puff.alpha, 1.0)
        XCTAssertEqual(fx.activeChunks.count, Tuning.Encounter.impactChunkCountAbsorbed)
    }

    // MARK: - Hit: gravity snow chunks (penguinslide-bo8)

    /// An accepted hit launches the full chunk count, every chunk
    /// parented at the impact point in the slot just above the puff.
    func testHitSpawnsGravityChunksAtImpactPoint() {
        let (fx, parent, _) = make()
        let point = CGPoint(x: 200, y: 300)

        fx.playHitBurst(at: point, depthScale: 1.0, accepted: true)

        XCTAssertEqual(fx.activeChunks.count, Tuning.Encounter.impactChunkCount)
        let nodes = parent.children.filter { $0.name == "snowChunk" }
        XCTAssertEqual(nodes.count, Tuning.Encounter.impactChunkCount)
        for node in nodes {
            XCTAssertEqual(node.position.x, point.x, accuracy: 1e-3)
            XCTAssertEqual(node.position.y, point.y, accuracy: 1e-3)
            XCTAssertEqual(node.zPosition, EncounterFX.burstZPosition + 1)
        }
        // Every chunk launches with an upward vertical component (the
        // splash read) — gravity then owns the arc.
        XCTAssertTrue(fx.activeChunks.allSatisfy { $0.vy > 0 })
    }

    /// update(dt:) integrates manually: gravity pulls vy down each tick,
    /// positions move by velocity, alpha fades with age — and a dt == 0
    /// sentinel frame is a free no-op (the repo physics doctrine).
    func testChunkIntegrationAppliesGravityAndFade() {
        let (fx, _, _) = make()
        fx.playHitBurst(at: .zero, depthScale: 1.0, accepted: true)
        let vyBefore = fx.activeChunks.map(\.vy)

        fx.update(dt: 0)   // sentinel frame: nothing may move
        XCTAssertEqual(fx.activeChunks.map(\.vy), vyBefore,
                       "dt == 0 must be a free no-op")

        let dt: TimeInterval = 1.0 / 60.0
        fx.update(dt: dt)

        for (before, after) in zip(vyBefore, fx.activeChunks.map(\.vy)) {
            XCTAssertEqual(after,
                           before - Tuning.Encounter.impactChunkGravity * CGFloat(dt),
                           accuracy: 1e-3,
                           "gravity must decrement vy by g·dt every tick")
        }
        XCTAssertTrue(fx.activeChunks.allSatisfy { ($0.node?.alpha ?? 1) < 1.0 },
                      "alpha fades with age")
    }

    /// Chunks remove themselves (node + tracking entry) once their
    /// lifetime elapses — the array can't grow across a long volley.
    func testChunksExpireAfterLifetime() {
        let (fx, parent, _) = make()
        fx.playHitBurst(at: .zero, depthScale: 1.0, accepted: true)
        XCTAssertFalse(fx.activeChunks.isEmpty)

        // Step well past the lifetime in a few coarse ticks.
        for _ in 0..<10 { fx.update(dt: Tuning.Encounter.impactChunkLifetime / 4) }

        XCTAssertTrue(fx.activeChunks.isEmpty)
        XCTAssertTrue(parent.children.filter { $0.name == "snowChunk" }.isEmpty)
    }

    /// Accepted hits shake the camera (keyed on the hit — full
    /// amplitude, the same "shake" action key as the icicle recipe);
    /// absorbed hits don't (the icicle path's "no shake" branch).
    func testAcceptedHitShakesCameraAbsorbedDoesNot() {
        let (fxA, _, cameraA) = make()
        fxA.playHitBurst(at: .zero, depthScale: 1.0, accepted: true)
        XCTAssertNotNil(cameraA.action(forKey: "shake"))

        let (fxB, _, cameraB) = make()
        fxB.playHitBurst(at: .zero, depthScale: 1.0, accepted: false)
        XCTAssertNil(cameraB.action(forKey: "shake"))
    }

    // MARK: - Dodge accent

    /// A dodge spawns tracked speed-line nodes near the crossing point,
    /// with severity scaling the line count up to the knob max.
    func testDodgeAccentSpawnsTrackedSpeedLines() {
        let (fx, parent, _) = make()
        let point = CGPoint(x: 200, y: 250)

        fx.playDodgeAccent(at: point, severity: 1.0, direction: 1)

        let lines = parent.children.filter { $0.name == "dodgeSpeedLine" }
        XCTAssertEqual(lines.count, Tuning.Encounter.dodgeAccentLineCountMax)
        XCTAssertEqual(fx.activeFX.count, lines.count)
        for line in lines {
            XCTAssertEqual(line.position.x, point.x, accuracy: 1e-3)
            XCTAssertEqual(line.zPosition, EncounterFX.dodgeAccentZPosition)
            XCTAssertTrue(line.hasActions(), "speed line should be animating out")
        }
    }

    /// Even a severity-0 dodge shows at least one (faint) line, and the
    /// streak mirrors with the pass direction.
    func testDodgeAccentMinimumLineAndDirectionMirror() {
        let (fx, parent, _) = make()
        fx.playDodgeAccent(at: .zero, severity: 0, direction: -1)

        let lines = parent.children.compactMap { $0 as? SKSpriteNode }
            .filter { $0.name == "dodgeSpeedLine" }
        XCTAssertEqual(lines.count, 1)
        XCTAssertLessThan(lines[0].xScale, 0, "direction -1 mirrors the streak via xScale")
    }

    // MARK: - Pause registration (game-over freeze)

    /// pauseActions freezes every live SKAction-driven node per-node —
    /// the triggerGameOver seam, so a death mid-puff/mid-whoosh leaves a
    /// coherent frozen frame. (Chunks need no isPaused: they're frozen
    /// by the update guard — ticks stop on game over.)
    func testPauseActionsFreezesLiveFXNodes() {
        let (fx, _, _) = make()
        fx.playHitBurst(at: .zero, depthScale: 1.0, accepted: true)
        fx.playDodgeAccent(at: .zero, severity: 1.0, direction: 1)
        XCTAssertFalse(fx.activeFX.isEmpty)
        XCTAssertTrue(fx.activeFX.allSatisfy { !$0.isPaused })

        fx.pauseActions()

        XCTAssertTrue(fx.activeFX.allSatisfy { $0.isPaused })

        // And the unfreeze side of the seam is symmetric.
        fx.setActionsPaused(false)
        XCTAssertTrue(fx.activeFX.allSatisfy { !$0.isPaused })
    }

    // MARK: - Reset hygiene

    /// reset() clears every transient FX node — puffs, speed lines AND
    /// chunks — from the tree and the tracking arrays (acceptance): the
    /// endEncounterPresentation / outro-swap teardown seam.
    func testResetRemovesAllTransientFXNodes() {
        let (fx, parent, _) = make()
        fx.playHitBurst(at: .zero, depthScale: 1.0, accepted: true)
        fx.playDodgeAccent(at: .zero, severity: 1.0, direction: 1)
        XCTAssertFalse(parent.children.isEmpty)

        fx.reset()

        XCTAssertTrue(fx.activeFX.isEmpty)
        XCTAssertTrue(fx.activeChunks.isEmpty)
        XCTAssertNil(parent.childNode(withName: "snowballPuff"))
        XCTAssertNil(parent.childNode(withName: "snowChunk"))
        XCTAssertNil(parent.childNode(withName: "dodgeSpeedLine"))
        XCTAssertTrue(parent.children.isEmpty,
                      "FX owns every node it parents — reset must scrub them all")
    }

    /// Repeated hits/dodges keep spawning fresh one-shots after a reset
    /// (no latched state), and a second reset is a safe no-op.
    func testResetIsReentrant() {
        let (fx, parent, _) = make()
        fx.reset()
        fx.playHitBurst(at: .zero, depthScale: 1.0, accepted: true)
        fx.reset()
        fx.reset()
        XCTAssertTrue(parent.children.isEmpty)
        XCTAssertTrue(fx.activeFX.isEmpty)
        XCTAssertTrue(fx.activeChunks.isEmpty)

        fx.playHitBurst(at: .zero, depthScale: 1.0, accepted: false)
        XCTAssertNotNil(parent.childNode(withName: "snowballPuff"))
        XCTAssertEqual(fx.activeChunks.count, Tuning.Encounter.impactChunkCountAbsorbed)
    }
}
