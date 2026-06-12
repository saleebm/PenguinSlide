//
//  EncounterFXTests.swift
//  PenguinSlideTests
//
//  Unit coverage for the encounter impact/dodge FX helper
//  (penguinslide-gyu.16): the SnowballBurst sheet contract, hit-burst
//  placement/sizing (anchored at the impact point, just in front of the
//  avatar, scaled by depth scale, softened when i-frames absorbed the
//  hit), the hit-keyed camera shake, the pure haptic mapping (the
//  accepted/absorbed distinction mirroring onIcicleHitPenguin, and the
//  dodge severity threshold), dodge speed-line accents, and the
//  pause/reset lifecycle (game-over freeze + restart hygiene).
//
//  Like SnowMonsterTests/PapiAvatarTests: SKActions don't tick without
//  a presenting SKView, so assertions are SYNCHRONOUS — node presence,
//  keyed-action presence, tracked-array state, isPaused flags.
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

    // MARK: - Sheet contract (spritecook-assets.json)

    /// snowball_impact_burst: 8 frames, one-shot — the EncounterAnimations
    /// entry must agree with the manifest (the SpriteCook integration
    /// contract, same as the actor sheets).
    func testBurstSheetSlicesEightOneShotFrames() {
        XCTAssertEqual(EncounterAnimations.snowballBurstFrames.count, 8)
        XCTAssertFalse(EncounterAnimations.loops(.snowballBurst))
        XCTAssertEqual(EncounterAnimations.frames(for: .snowballBurst).count, 8)
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

    // MARK: - Hit burst

    /// The burst anchors AT the impact screen point, in the draw-order
    /// slot just in front of the avatar (the "into Papi" read), at the
    /// base size for depth scale 1, animating its one-shot, and is
    /// tracked for pause/reset.
    func testHitBurstAnchorsAtImpactPointJustInFrontOfAvatar() {
        let (fx, parent, _) = make()
        let point = CGPoint(x: 123, y: 310)

        fx.playHitBurst(at: point, depthScale: 1.0, accepted: true)

        guard let burst = parent.childNode(withName: "snowballBurst") as? SKSpriteNode else {
            return XCTFail("expected a snowballBurst node under the parent")
        }
        // SKNode stores position as Float32 — tolerance compare (the
        // PapiAvatarTests caveat).
        XCTAssertEqual(burst.position.x, point.x, accuracy: 1e-3)
        XCTAssertEqual(burst.position.y, point.y, accuracy: 1e-3)
        XCTAssertEqual(burst.zPosition, PapiAvatar.zPositionInEncounterRoot + 1)
        XCTAssertEqual(burst.zPosition, EncounterFX.burstZPosition)
        XCTAssertEqual(burst.size.width, Tuning.Encounter.burstBaseSize, accuracy: 1e-3)
        XCTAssertEqual(burst.size.height, Tuning.Encounter.burstBaseSize, accuracy: 1e-3)
        XCTAssertEqual(burst.alpha, 1.0, accuracy: 1e-6)
        XCTAssertTrue(burst.hasActions(), "one-shot animation should be running")
        XCTAssertEqual(fx.activeFX.count, 1)
        XCTAssertTrue(fx.activeFX.first === burst)
    }

    /// Burst footprint scales linearly with the avatar's depth scale.
    func testHitBurstScalesByAvatarDepthScale() {
        let (fx, parent, _) = make()
        fx.playHitBurst(at: .zero, depthScale: 0.5, accepted: true)

        let burst = parent.childNode(withName: "snowballBurst") as? SKSpriteNode
        XCTAssertEqual(burst?.size.width ?? 0,
                       Tuning.Encounter.burstBaseSize * 0.5, accuracy: 1e-3)
    }

    /// I-frame-absorbed hit dials the burst soft: smaller (by the
    /// absorbed scale knob) and dimmer — the icicle "softer pop"
    /// treatment.
    func testAbsorbedHitBurstIsSofter() {
        let (fx, parent, _) = make()
        fx.playHitBurst(at: .zero, depthScale: 1.0, accepted: false)

        guard let burst = parent.childNode(withName: "snowballBurst") as? SKSpriteNode else {
            return XCTFail("expected a snowballBurst node under the parent")
        }
        XCTAssertEqual(burst.size.width,
                       Tuning.Encounter.burstBaseSize * Tuning.Encounter.burstAbsorbedScale,
                       accuracy: 1e-3)
        XCTAssertLessThan(burst.alpha, 1.0)
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

    /// pauseActions freezes every live transient node per-node — the
    /// triggerGameOver seam, so a death mid-burst leaves a coherent
    /// frozen frame (acceptance).
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

    /// reset() clears every transient FX node from the tree and the
    /// tracking array (acceptance) — the endEncounterPresentation /
    /// outro-swap teardown seam.
    func testResetRemovesAllTransientFXNodes() {
        let (fx, parent, _) = make()
        fx.playHitBurst(at: .zero, depthScale: 1.0, accepted: true)
        fx.playDodgeAccent(at: .zero, severity: 1.0, direction: 1)
        XCTAssertFalse(parent.children.isEmpty)

        fx.reset()

        XCTAssertTrue(fx.activeFX.isEmpty)
        XCTAssertNil(parent.childNode(withName: "snowballBurst"))
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

        fx.playHitBurst(at: .zero, depthScale: 1.0, accepted: false)
        XCTAssertEqual(fx.activeFX.count, 1)
        XCTAssertNotNil(parent.childNode(withName: "snowballBurst"))
    }
}
