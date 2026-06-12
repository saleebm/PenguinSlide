//
//  PapiAvatarTests.swift
//  PenguinSlideTests
//
//  Unit coverage for the PapiAvatar rear-view actor (penguinslide-gyu.11):
//  projector-correct placement, tilt dodge parity with the shared
//  TiltSlideMotion integrator, corridor clamping, the HP-proxy hit path
//  (delegation to the real Penguin, knockback mapped onto the avatar,
//  i-frame absorption and expiry through the ticked penguin clock),
//  hurt/i-frame visuals, and begin()/reset() hygiene.
//
//  Like SnowMonsterTests: SKActions don't tick without a presenting
//  SKView, so assertions are SYNCHRONOUS (state, keyed-action presence,
//  manual-integration results). The avatar's motion/lean/bob/flicker are
//  all manual integration, so they ARE exercised here frame by frame.
//  `Tuning.Penguin` is the live UserDefaults-backed struct — tests read
//  it rather than assuming defaults, mirroring the implementation.
//

import XCTest
import SpriteKit
@testable import PenguinSlide

final class PapiAvatarTests: XCTestCase {

    private let sceneSize = CGSize(width: 390, height: 844)
    private let dt: TimeInterval = 1.0 / 60.0

    private func make() -> (avatar: PapiAvatar,
                            parent: SKNode,
                            projector: DepthProjector,
                            penguin: Penguin) {
        let parent = SKNode()
        let projector = DepthProjector(sceneSize: sceneSize)
        // The real (side-view) penguin — hidden during encounters in the
        // app; here it only matters as the hp/i-frame authority.
        let penguin = Penguin(parent: SKNode(), baseY: 170,
                              leftBound: 30, rightBound: 360)
        let avatar = PapiAvatar(parent: parent, projector: projector, penguin: penguin)
        return (avatar, parent, projector, penguin)
    }

    /// SKNode stores position as Float32 internally — compare with a
    /// tolerance (same caveat as SnowMonsterTests).
    private func assertEqual(_ actual: CGPoint, _ expected: CGPoint,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 1e-3, "x", file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 1e-3, "y", file: file, line: line)
    }

    // MARK: Placement

    /// Spawns centered on the corridor at the camera-plane ground
    /// station (z = 0, scale exactly 1) in the avatar's reserved
    /// draw-order slot.
    func testSpawnsCenteredAtCameraPlaneStation() {
        let (avatar, parent, projector, _) = make()

        let expected = projector.project(worldX: projector.vanishingX, z: 0)
        XCTAssertEqual(expected.scale, 1.0, accuracy: 1e-9)
        assertEqual(avatar.node.position, expected.point)
        XCTAssertEqual(avatar.worldX, projector.vanishingX)
        XCTAssertEqual(avatar.node.xScale, 1.0, accuracy: 1e-6)
        XCTAssertEqual(avatar.node.yScale, 1.0, accuracy: 1e-6)
        XCTAssertEqual(avatar.node.zPosition, PapiAvatar.zPositionInEncounterRoot)
        XCTAssertEqual(avatar.node.anchorPoint, CGPoint(x: 0.5, y: 0))
        XCTAssertTrue(avatar.node.parent === parent)
        // Slide loop running from construction.
        XCTAssertNotNil(avatar.node.action(forKey: "frames"))
    }

    // MARK: Tilt dodge (shared-integrator parity)

    /// The dodge must be EXACTLY the shared TiltSlideMotion dynamics
    /// with the corridor bounds — frame-by-frame equality against a
    /// reference integrator run with the same inputs (this is the
    /// "same response as normal mode" wiring guarantee; the integrator
    /// itself is characterized in TiltSlideMotionTests).
    func testTiltResponseMatchesSharedIntegratorExactly() {
        let (avatar, _, projector, _) = make()

        var reference = TiltSlideMotion(
            leftBound: projector.vanishingX - Tuning.Encounter.papiLateralRange,
            rightBound: projector.vanishingX + Tuning.Encounter.papiLateralRange
        )
        var referenceX = projector.vanishingX
        let halfWidth = avatar.node.size.width * PapiAvatar.halfWidthFraction

        for _ in 0..<90 {   // 1.5 s of rightward tilt
            avatar.update(dt: dt, tilt: 0.7)
            reference.update(dt: dt, tilt: 0.7)
            referenceX = reference.integrate(x: referenceX, dt: dt, halfWidth: halfWidth)
        }

        XCTAssertEqual(avatar.worldX, referenceX, accuracy: 1e-9)
        XCTAssertEqual(avatar.vx, reference.vx, accuracy: 1e-9)
        // Tilt-right moves the avatar right of center, and the node's
        // screen x tracks worldX (lateral identity at z = 0).
        XCTAssertGreaterThan(avatar.worldX, projector.vanishingX)
        XCTAssertEqual(avatar.node.position.x, referenceX, accuracy: 1e-3)
    }

    /// Acceptance: full tilt parks the avatar at the corridor edge with
    /// zero velocity (clamp zeroes vx) and NO jitter on later frames.
    func testFullTiltHoldsCorridorEdgeWithoutJitter() {
        let (avatar, _, projector, _) = make()

        for _ in 0..<600 { avatar.update(dt: dt, tilt: 1.0) }   // 10 s

        let edgeX = projector.vanishingX + Tuning.Encounter.papiLateralRange
            - avatar.node.size.width * PapiAvatar.halfWidthFraction
        XCTAssertEqual(avatar.worldX, edgeX, accuracy: 1e-6)
        XCTAssertEqual(avatar.vx, 0, accuracy: 1e-9)

        // Still pressing: worldX must not oscillate off the wall.
        for _ in 0..<10 {
            avatar.update(dt: dt, tilt: 1.0)
            XCTAssertEqual(avatar.worldX, edgeX, accuracy: 1e-9)
        }
    }

    /// Dodge accent: the rear-slide sheet mirrors (xScale sign) toward
    /// the dodge direction once |vx| reads as deliberate motion.
    func testDodgeMirrorFollowsVelocityDirection() {
        let (avatar, _, _, _) = make()

        // Sample MID-FLIGHT (few frames only): the corridor is narrow, so
        // a long full-tilt run parks on the wall where the clamp zeroes
        // vx — facing latches the last deliberate direction either way.
        for _ in 0..<6 { avatar.update(dt: dt, tilt: -1.0) }
        XCTAssertGreaterThan(abs(avatar.vx), Tuning.Penguin.idleSlideThresholdPtPerSec)
        XCTAssertLessThan(avatar.node.xScale, 0, "dodging left mirrors the sheet")
        XCTAssertGreaterThan(avatar.node.yScale, 0)

        for _ in 0..<60 { avatar.update(dt: dt, tilt: 1.0) }
        XCTAssertGreaterThan(avatar.node.xScale, 0, "dodging right restores the sheet")
    }

    /// Lean trim (gyu.26): the final PapiRearSlide sheet bakes subtle
    /// lean frames into the loop, so the avatar's zRotation spring
    /// targets `leanMaxAngle × Tuning.Encounter.papiLeanScale` — the
    /// penguin's exact spring recipe and stiffness/damping knobs, with
    /// only the target amplitude scaled (never a forked spring).
    /// Replicates the trimmed spring frame-by-frame against the avatar's
    /// actual vx history and pins exact parity; a dropped (or untrimmed)
    /// scale factor diverges within a handful of frames.
    func testLeanSpringTargetsTrimmedAngle() {
        let (avatar, _, _, _) = make()

        var expectedLeanVelocity: CGFloat = 0
        var maxLean: CGFloat = 0

        for frame in 0..<120 {   // 2 s: ramp → wall park → lean decay
            // What the implementation reads this frame (Float32-backed).
            let rotationBefore = avatar.node.zRotation
            avatar.update(dt: dt, tilt: 1.0)

            let target = -(avatar.vx / Tuning.Penguin.maxSpeed)
                * Tuning.Penguin.leanMaxAngle
                * Tuning.Encounter.papiLeanScale
            let omega = sqrt(Tuning.Penguin.leanStiffness)
            let accel = Tuning.Penguin.leanStiffness * (target - rotationBefore)
                - 2 * omega * Tuning.Penguin.leanDampingRatio * expectedLeanVelocity
            expectedLeanVelocity += accel * CGFloat(dt)
            let expectedRotation = rotationBefore + expectedLeanVelocity * CGFloat(dt)

            XCTAssertEqual(avatar.node.zRotation, expectedRotation, accuracy: 1e-4,
                           "trimmed-spring divergence at frame \(frame)")
            maxLean = max(maxLean, abs(avatar.node.zRotation))
        }

        // Not vacuous: the dodge actually leaned the sprite…
        XCTAssertGreaterThan(maxLean, 0.02, "lean never developed — spring inert?")
        // …and the knob contract holds: a trim in (0, 1], never an amplifier.
        XCTAssertGreaterThan(Tuning.Encounter.papiLeanScale, 0)
        XCTAssertLessThanOrEqual(Tuning.Encounter.papiLeanScale, 1.0)
    }

    // MARK: Hit path (HP proxy + knockback mapping)

    /// An encounter hit decrements the REAL penguin's hp (single
    /// authority), maps the knockback impulse onto the AVATAR's motion
    /// (away from the ball, Penguin's formula), and arms the hurt
    /// feedback through the chained onHealthChanged.
    func testHitDelegatesHpAndMapsKnockbackToAvatar() {
        let (avatar, _, _, penguin) = make()
        let hpBefore = penguin.hp

        // Ball to the avatar's right → shoved left (negative vx).
        XCTAssertTrue(avatar.takeHit(fromWorldX: avatar.worldX + 50))

        XCTAssertEqual(penguin.hp, hpBefore - 1)
        let expectedImpulse = -Tuning.Penguin.maxSpeed * Tuning.Penguin.knockbackImpulseScale
        XCTAssertEqual(avatar.vx, expectedImpulse, accuracy: 1e-6)
        XCTAssertNotNil(avatar.node.action(forKey: "hurtFlash"))
        XCTAssertNotNil(avatar.node.action(forKey: "hurtSquash"))
    }

    func testKnockbackDirectionIsAwayFromBallOnBothSides() {
        let (avatar, _, _, _) = make()
        // Ball to the LEFT → shoved right (positive vx).
        XCTAssertTrue(avatar.takeHit(fromWorldX: avatar.worldX - 50))
        XCTAssertGreaterThan(avatar.vx, 0)
    }

    /// Acceptance: a hit during active i-frames is absorbed — no HP
    /// change, no extra knockback, no double hurt anim. All delegated to
    /// Penguin.tryTakeHit's gate.
    func testHitDuringIFramesIsAbsorbed() throws {
        try XCTSkipUnless(Tuning.Penguin.maxHealth >= 2,
                          "i-frames only arm while the penguin survives")
        let (avatar, _, _, penguin) = make()

        XCTAssertTrue(avatar.takeHit(fromWorldX: avatar.worldX + 50))
        XCTAssertTrue(penguin.isInvulnerable)
        let hp = penguin.hp
        let vx = avatar.vx

        XCTAssertFalse(avatar.takeHit(fromWorldX: avatar.worldX - 50))
        XCTAssertEqual(penguin.hp, hp, "absorbed hit must not cost HP")
        XCTAssertEqual(avatar.vx, vx, accuracy: 1e-9,
                       "absorbed hit must not add knockback")
    }

    /// The avatar ticks the penguin's hit clock every frame (the hidden
    /// penguin's own update isn't running during an encounter), so the
    /// i-frame window expires on the normal-mode schedule and the next
    /// hit lands again.
    func testIFrameWindowExpiresThroughAvatarTickedClock() throws {
        try XCTSkipUnless(Tuning.Penguin.maxHealth >= 2,
                          "i-frames only arm while the penguin survives")
        let (avatar, _, _, penguin) = make()

        XCTAssertTrue(avatar.takeHit(fromWorldX: avatar.worldX + 50))
        XCTAssertTrue(penguin.isInvulnerable)

        let steps = Int(ceil(Tuning.Penguin.iFrameDuration / dt)) + 2
        for _ in 0..<steps { avatar.update(dt: dt, tilt: 0) }

        XCTAssertFalse(penguin.isInvulnerable)
        XCTAssertEqual(avatar.node.alpha, 1.0, accuracy: 1e-6,
                       "flicker must clear when the window ends")
        XCTAssertTrue(avatar.takeHit(fromWorldX: avatar.worldX + 50),
                      "post-window hits land again")
    }

    /// I-frame flicker reads the live knobs: while invulnerable the
    /// avatar's alpha alternates between 1.0 and exactly iFrameDimAlpha.
    func testIFrameFlickerUsesLiveKnobs() throws {
        try XCTSkipUnless(Tuning.Penguin.maxHealth >= 2,
                          "i-frames only arm while the penguin survives")
        try XCTSkipUnless(Tuning.Penguin.iFrameDuration >= 0.5,
                          "window too short to sample both flicker states")
        try XCTSkipUnless(Tuning.Penguin.iFrameFlashHz >= 2.5,
                          "flash too slow for the 0.4 s sample to see both states")
        let (avatar, _, _, penguin) = make()
        avatar.takeHit(fromWorldX: avatar.worldX + 50)

        var sawLit = false
        var sawDim = false
        for _ in 0..<24 {   // 0.4 s — inside the window, ≥3 flash cycles
            avatar.update(dt: dt, tilt: 0)
            XCTAssertTrue(penguin.isInvulnerable)
            if abs(avatar.node.alpha - 1.0) < 1e-3 {
                sawLit = true
            } else {
                XCTAssertEqual(avatar.node.alpha, Tuning.Penguin.iFrameDimAlpha,
                               accuracy: 1e-3)
                sawDim = true
            }
        }
        XCTAssertTrue(sawLit && sawDim, "flicker must alternate states")
    }

    // MARK: Health-callback chaining

    /// The avatar chains onto penguin.onHealthChanged without clobbering
    /// the existing downstream (GameScene's HUD wiring): the prior
    /// closure still fires, first, with the same hp.
    func testHealthCallbackChainPreservesDownstream() {
        let parent = SKNode()
        let projector = DepthProjector(sceneSize: sceneSize)
        let penguin = Penguin(parent: SKNode(), baseY: 170,
                              leftBound: 30, rightBound: 360)
        var hudSaw: [Int] = []
        penguin.onHealthChanged = { hudSaw.append($0) }   // pre-existing wiring

        let avatar = PapiAvatar(parent: parent, projector: projector, penguin: penguin)
        avatar.takeHit(fromWorldX: avatar.worldX + 10)

        XCTAssertEqual(hudSaw, [penguin.hp], "HUD wiring must still fire")
        XCTAssertNotNil(avatar.node.action(forKey: "hurtFlash"),
                        "avatar feedback rides the same callback")
    }

    /// onHealthChanged also fires on hp INCREASES (Penguin.reset()
    /// restores max hp through it) — that must not flash the avatar.
    func testHpRestoreDoesNotPlayHurtFeedback() {
        let (avatar, _, _, penguin) = make()

        avatar.takeHit(fromWorldX: avatar.worldX + 10)
        avatar.reset()                       // scrub the hit's actions
        XCTAssertNil(avatar.node.action(forKey: "hurtFlash"))

        penguin.reset()                      // hp back to max → callback fires
        XCTAssertNil(avatar.node.action(forKey: "hurtFlash"),
                     "hp restore must not read as a hit")
        XCTAssertNil(avatar.node.action(forKey: "hurtSquash"))
    }

    // MARK: begin()/reset() hygiene

    /// Acceptance: begin() recenters worldX and resets motion; reset()
    /// leaves no leftover actions, tints, mirror, rotation, or dim.
    func testBeginRecentersAndScrubsAllVisualState() {
        let (avatar, _, projector, _) = make()

        // Dirty every channel: offset + velocity + mirror + lean…
        for _ in 0..<60 { avatar.update(dt: dt, tilt: -1.0) }
        // …hurt tint/squash + i-frame dim + paused actions.
        avatar.takeHit(fromWorldX: avatar.worldX + 10)
        avatar.update(dt: dt, tilt: 0)
        avatar.setActionsPaused(true)

        avatar.begin()

        XCTAssertEqual(avatar.worldX, projector.vanishingX)
        XCTAssertEqual(avatar.vx, 0)
        assertEqual(avatar.node.position,
                    projector.project(worldX: projector.vanishingX, z: 0).point)
        XCTAssertFalse(avatar.node.isPaused)
        XCTAssertEqual(avatar.node.alpha, 1.0)
        XCTAssertEqual(avatar.node.zRotation, 0)
        XCTAssertEqual(avatar.node.xScale, 1.0, accuracy: 1e-6)
        XCTAssertEqual(avatar.node.yScale, 1.0, accuracy: 1e-6)
        XCTAssertEqual(avatar.node.colorBlendFactor, 0)
        // Only the slide loop survives.
        XCTAssertNotNil(avatar.node.action(forKey: "frames"))
        XCTAssertNil(avatar.node.action(forKey: "hurtFlash"))
        XCTAssertNil(avatar.node.action(forKey: "hurtSquash"))
    }

    func testSetActionsPausedTogglesNodePause() {
        let (avatar, _, _, _) = make()
        avatar.setActionsPaused(true)
        XCTAssertTrue(avatar.node.isPaused)
        avatar.setActionsPaused(false)
        XCTAssertFalse(avatar.node.isPaused)
    }

    // MARK: Death visuals (penguinslide-gyu.19)

    /// triggerDeathAnimation (Penguin's scale-down/fade/tip recipe on
    /// the rear-view node): the slide loop and any hurt squash are
    /// removed so the death pose isn't undercut, the keyed "death"
    /// action runs, and the node stays UNPAUSED — GameScene's
    /// game-over freeze (encounterSystem.pauseActions) deliberately
    /// skips the avatar so the tip plays over the frozen world.
    func testDeathAnimationFreezesLoopAndRunsDeathAction() {
        let (avatar, _, _, penguin) = make()
        // Death follows a final accepted hit in production.
        while penguin.isAlive() {
            avatar.takeHit(fromWorldX: avatar.worldX + 10)
            avatar.update(dt: Tuning.Penguin.iFrameDuration + 0.05, tilt: 0)
        }

        avatar.triggerDeathAnimation()

        XCTAssertNotNil(avatar.node.action(forKey: "death"))
        XCTAssertNil(avatar.node.action(forKey: "frames"),
                     "the rear-slide loop must freeze for the death pose")
        XCTAssertNil(avatar.node.action(forKey: "hurtSquash"),
                     "a same-hit squash must not fight the death scale")
        XCTAssertFalse(avatar.node.isPaused,
                       "the death anim must keep playing over the frozen world")
    }

    /// restart()-from-encounter-death hygiene: reset() after a death
    /// animation scrubs the death action and restores the clean
    /// centered slide (alpha/scale/rotation reset, loop running) —
    /// "restart from EITHER world converges to the same fresh state."
    func testResetAfterDeathRestoresCleanSlide() {
        let (avatar, _, projector, _) = make()
        // Dirty the mirror first so the sign-aware death scale is the
        // path under test.
        for _ in 0..<60 { avatar.update(dt: dt, tilt: -1.0) }
        avatar.triggerDeathAnimation()

        avatar.reset()

        XCTAssertNil(avatar.node.action(forKey: "death"))
        XCTAssertNotNil(avatar.node.action(forKey: "frames"))
        XCTAssertEqual(avatar.worldX, projector.vanishingX)
        XCTAssertEqual(avatar.node.alpha, 1.0)
        XCTAssertEqual(avatar.node.xScale, 1.0, accuracy: 1e-6)
        XCTAssertEqual(avatar.node.yScale, 1.0, accuracy: 1e-6)
        XCTAssertEqual(avatar.node.zRotation, 0)
        XCTAssertFalse(avatar.node.isPaused)
    }
}
