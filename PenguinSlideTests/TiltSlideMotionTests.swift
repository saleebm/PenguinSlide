//
//  TiltSlideMotionTests.swift
//  PenguinSlideTests
//
//  Characterization + extraction tests for TiltSlideMotion
//  (penguinslide-gyu.3). The FIXTURE arrays below were captured from the
//  pre-refactor Penguin.update velocity/integration math (Penguin.swift
//  lines ~125-137 as of the extraction commit) by replaying fixed
//  (tilt, dt) sequences through a bit-exact transcription with default
//  PenguinTuning knobs (tiltIntensity 0.25 → maxSpeed 1125,
//  tiltResponseRate 4.5, tiltCurve 1.45, iceDecayRate 0.7,
//  knockbackImpulseScale 0.5). CGFloat == Double on the simulator, so
//  the extracted struct must reproduce them to floating-point noise.
//
//  A second layer (`testPenguinDelegates...`) drives a REAL Penguin
//  instance in lockstep with a bare TiltSlideMotion and asserts exact
//  equality every frame — proving the delegation introduced zero drift.
//

import XCTest
import SpriteKit
@testable import PenguinSlide

final class TiltSlideMotionTests: XCTestCase {

    private let dt: TimeInterval = 1.0 / 60.0
    /// Matches Penguin's clamp inset: node.size.width (70) * 0.42.
    private let halfW: CGFloat = 70.0 * 0.42
    /// Wide corridor: velocity dynamics only, no wall contact.
    private let wideBounds: (left: CGFloat, right: CGFloat) = (0, 1_000_000)
    /// Narrow corridor (the game's shape): wall-clamp interplay.
    private let gameBounds: (left: CGFloat, right: CGFloat) = (0, 800)
    private let startX: CGFloat = 400
    /// Fixtures are exact doubles; the only divergence tolerated is
    /// cross-machine libm noise in pow/exp.
    private let acc: CGFloat = 1e-6

    override func setUp() {
        super.setUp()
        // Deterministic knobs: the test host may carry persisted
        // PenguinTuning overrides — replace with pristine defaults.
        Tuning.Penguin = PenguinTuning()
    }

    override func tearDown() {
        Tuning.Penguin = .loadFromUserDefaults()
        super.tearDown()
    }

    /// Drives the struct + an x mirror exactly the way Penguin.update
    /// does (velocity step, then integrate from the current x).
    private func step(_ motion: inout TiltSlideMotion, _ x: inout CGFloat, tilt: CGFloat) {
        motion.update(dt: dt, tilt: tilt)
        x = motion.integrate(x: x, dt: dt, halfWidth: halfW)
    }

    // MARK: - Characterization fixtures (pre-refactor Penguin.update traces)

    /// Ramp from rest to full tilt: vx approaches maxSpeed (1125) via
    /// tiltResponseRate; sampled at frames 1,5,10,20,30,60,120.
    func testFixture_RampToFullTilt() {
        let expectedVx: [CGFloat] = [81.288577880378028, 351.79956136015647,
                                     593.58762816635863, 873.97856983301665,
                                     1006.4258723679028, 1112.5023788944775,
                                     1124.8611639704022]
        let expectedX: [CGFloat] = [401.35480963133961, 418.46734035651849,
                                    460.47637550468397, 587.9746638851625,
                                    747.13186220888849, 1286.932227490373,
                                    2409.2875334296946]
        var motion = TiltSlideMotion(leftBound: wideBounds.left, rightBound: wideBounds.right)
        var x = startX
        var gotVx: [CGFloat] = [], gotX: [CGFloat] = []
        for frame in 1...120 {
            step(&motion, &x, tilt: 1.0)
            if [1, 5, 10, 20, 30, 60, 120].contains(frame) { gotVx.append(motion.vx); gotX.append(x) }
        }
        for (g, e) in zip(gotVx, expectedVx) { XCTAssertEqual(g, e, accuracy: acc) }
        for (g, e) in zip(gotX, expectedX) { XCTAssertEqual(g, e, accuracy: acc) }
        // Full tilt converges toward maxSpeed, never beyond.
        XCTAssertLessThanOrEqual(motion.vx, Tuning.Penguin.maxSpeed)
        XCTAssertGreaterThan(motion.vx, Tuning.Penguin.maxSpeed * 0.999)
        print("ramp trace OK: vx@120=\(motion.vx) (maxSpeed=\(Tuning.Penguin.maxSpeed))")
    }

    /// Release-glide: 60 frames full tilt, then tilt = 0 — decay must
    /// follow iceDecayRate (0.7), NOT tiltResponseRate (asymmetric friction).
    func testFixture_ReleaseGlideUsesIceDecayRate() {
        let expectedVx: [CGFloat] = [1099.5986028628356, 989.99558715900741,
                                     783.96717619067397, 552.45233179197999,
                                     274.3397090131931]
        var motion = TiltSlideMotion(leftBound: wideBounds.left, rightBound: wideBounds.right)
        var x = startX
        for _ in 1...60 { step(&motion, &x, tilt: 1.0) }
        XCTAssertEqual(motion.vx, 1112.5023788944775, accuracy: acc)
        var got: [CGFloat] = []
        for frame in 1...120 {
            step(&motion, &x, tilt: 0)
            if [1, 10, 30, 60, 120].contains(frame) { got.append(motion.vx) }
        }
        for (g, e) in zip(got, expectedVx) { XCTAssertEqual(g, e, accuracy: acc) }
        XCTAssertEqual(x, 2477.3363625709949, accuracy: acc)
        // Analytic cross-check: one tilt-0 step multiplies vx by exp(-decay*dt).
        let before = motion.vx
        step(&motion, &x, tilt: 0)
        XCTAssertEqual(motion.vx, before * exp(-Tuning.Penguin.iceDecayRate * CGFloat(dt)), accuracy: acc)
    }

    /// Hard reverse: full right for 60 frames, then full left — vx swings
    /// through zero and approaches -maxSpeed.
    func testFixture_HardReverse() {
        let expectedVx: [CGFloat] = [950.82825766399321, -68.078714531796223,
                                     -889.16898430919548, -1100.1435938185521]
        var motion = TiltSlideMotion(leftBound: wideBounds.left, rightBound: wideBounds.right)
        var x = startX
        for _ in 1...60 { step(&motion, &x, tilt: 1.0) }
        var got: [CGFloat] = []
        for frame in 1...60 {
            step(&motion, &x, tilt: -1.0)
            if [1, 10, 30, 60].contains(frame) { got.append(motion.vx) }
        }
        for (g, e) in zip(got, expectedVx) { XCTAssertEqual(g, e, accuracy: acc) }
        XCTAssertEqual(x, 635.42307844895129, accuracy: acc)
    }

    /// Wall-hold: in the game-shaped corridor, full tilt pins x at
    /// rightBound - halfW (first contact at frame 32 from x=400) and the
    /// clamp zeroes vx EVERY frame — no push-through accumulation.
    func testFixture_WallHoldClampsAndZeroesVx() {
        var motion = TiltSlideMotion(leftBound: gameBounds.left, rightBound: gameBounds.right)
        var x = startX
        let maxX = gameBounds.right - halfW   // 770.6
        var firstWallFrame = 0
        for frame in 1...300 {
            step(&motion, &x, tilt: 1.0)
            if firstWallFrame == 0 && x >= maxX {
                firstWallFrame = frame
            } else if firstWallFrame > 0 {
                // Once pinned: position glued to the wall, vx zeroed.
                XCTAssertEqual(x, maxX)
                XCTAssertEqual(motion.vx, 0)
            }
        }
        XCTAssertEqual(firstWallFrame, 32)
        XCTAssertEqual(x, maxX)
        XCTAssertEqual(motion.vx, 0)
        print("wall-hold OK: pinned at frame \(firstWallFrame), x=\(x), vx=\(motion.vx)")
    }

    /// tiltCurve exponent at partial tilt: target = 0.5^1.45 * 1125 and
    /// the first frame from rest is target * (1 - exp(-rate*dt)).
    func testFixture_PartialTiltCurveExponent() {
        var motion = TiltSlideMotion(leftBound: wideBounds.left, rightBound: wideBounds.right)
        var x = startX
        step(&motion, &x, tilt: 0.5)
        XCTAssertEqual(motion.vx, 29.753361029605863, accuracy: acc)
        let target = pow(0.5, Tuning.Penguin.tiltCurve) * Tuning.Penguin.maxSpeed
        XCTAssertEqual(target, 411.77410198470716, accuracy: acc)
        let alpha = 1 - exp(-Tuning.Penguin.tiltResponseRate * CGFloat(dt))
        XCTAssertEqual(motion.vx, target * alpha, accuracy: acc)
        for _ in 2...120 { step(&motion, &x, tilt: 0.5) }
        XCTAssertEqual(motion.vx, 411.72328502345323, accuracy: acc)
        XCTAssertEqual(x, 1135.4422841840719, accuracy: acc)
    }

    /// Knockback interplay on vx: impulse = dir * maxSpeed *
    /// knockbackImpulseScale lands on top of the current velocity, then
    /// the glide decay smooths it out — exactly the pre-refactor
    /// `vx += dir * maxSpeed * knockbackImpulseScale` in tryTakeHit.
    func testFixture_KnockbackImpulseInterplay() {
        var motion = TiltSlideMotion(leftBound: wideBounds.left, rightBound: wideBounds.right)
        var x = startX
        for _ in 1...60 { step(&motion, &x, tilt: 1.0) }
        motion.applyImpulse(direction: -1)   // shoved left mid-slide
        XCTAssertEqual(motion.vx, 550.00237889447749, accuracy: acc)
        let expectedVx: [CGFloat] = [543.62297005116591, 489.4370909782437,
                                     387.58012572389731, 273.12309840931198]
        var got: [CGFloat] = []
        for frame in 1...60 {
            step(&motion, &x, tilt: 0)
            if [1, 10, 30, 60].contains(frame) { got.append(motion.vx) }
        }
        for (g, e) in zip(got, expectedVx) { XCTAssertEqual(g, e, accuracy: acc) }
        XCTAssertEqual(x, 1680.1712158771641, accuracy: acc)
    }

    /// Live knob read: mutating Tuning.Penguin.applyTiltIntensity
    /// mid-sequence changes the response on the very next update call
    /// (the settings slider contract — knobs are read per call, not
    /// captured at init).
    func testFixture_LiveTuningMutationMidSequence() {
        var motion = TiltSlideMotion(leftBound: wideBounds.left, rightBound: wideBounds.right)
        var x = startX
        for _ in 1...30 { step(&motion, &x, tilt: 1.0) }
        XCTAssertEqual(motion.vx, 1006.4258723679028, accuracy: acc)

        Tuning.Penguin.applyTiltIntensity(1.0)   // maxSpeed 1950, rate 6.0, curve 1.3

        let expectedVx: [CGFloat] = [1096.2188226278402, 1602.878477222873,
                                     1903.0222103974334]
        var got: [CGFloat] = []
        for frame in 1...30 {
            step(&motion, &x, tilt: 1.0)
            if [1, 10, 30].contains(frame) { got.append(motion.vx) }
        }
        for (g, e) in zip(got, expectedVx) { XCTAssertEqual(g, e, accuracy: acc) }
        // vx blew past the old maxSpeed (1125) → the new knob took effect.
        XCTAssertGreaterThan(motion.vx, 1125)
    }

    // MARK: - Delegation equivalence (real Penguin vs bare struct)

    /// Drives a REAL Penguin and a bare TiltSlideMotion in lockstep
    /// through a mixed scenario (ramp into the wall, partial reverse,
    /// knockback hit, release-glide) and asserts vx and x are EXACTLY
    /// equal every frame — the extraction is provably behavior-neutral.
    func testPenguinDelegatesToTiltSlideMotionExactly() {
        let penguin = Penguin(parent: SKNode(), baseY: 0,
                              leftBound: gameBounds.left, rightBound: gameBounds.right)
        var motion = TiltSlideMotion(leftBound: gameBounds.left, rightBound: gameBounds.right)
        var x = penguin.node.position.x
        XCTAssertEqual(x, startX)   // spawns centered in the corridor
        // Mirror Penguin's exact clamp inset (sprite is 70pt wide; no
        // scale actions run because the node is not in a live scene).
        let penguinHalfW = penguin.node.size.width * 0.42

        func assertLockstep(frame: Int, phase: String) {
            XCTAssertEqual(penguin.vx, motion.vx, "vx diverged at \(phase) frame \(frame)")
            XCTAssertEqual(penguin.node.position.x, x, "x diverged at \(phase) frame \(frame)")
        }
        func run(_ tilt: CGFloat, frames: Int, phase: String) {
            for frame in 1...frames {
                penguin.update(dt: dt, tilt: tilt)
                motion.update(dt: dt, tilt: tilt)
                x = motion.integrate(x: x, dt: dt, halfWidth: penguinHalfW)
                // SKNode stores positions as Float32 internally, so the
                // penguin's x quantizes on every node.position write/read
                // (true pre- and post-refactor alike). Mirror it so the
                // lockstep comparison is bit-exact.
                x = CGFloat(Float(x))
                assertLockstep(frame: frame, phase: phase)
            }
        }

        run(1.0, frames: 60, phase: "ramp-into-wall")     // hits right wall ~frame 32
        run(-0.5, frames: 40, phase: "partial-reverse")

        // Knockback: impact to the right of the penguin → dir = -1.
        let impactX = penguin.node.position.x + 50
        XCTAssertTrue(penguin.tryTakeHit(from: impactX))
        motion.applyImpulse(direction: -1)
        assertLockstep(frame: 0, phase: "post-knockback")

        run(0, frames: 60, phase: "release-glide")

        // reset() symmetry: both go back to rest.
        penguin.reset()
        motion.reset()
        x = penguin.node.position.x
        XCTAssertEqual(penguin.vx, 0)
        XCTAssertEqual(motion.vx, 0)

        run(0.7, frames: 30, phase: "post-reset-ramp")
        print("lockstep OK: final vx=\(penguin.vx) x=\(penguin.node.position.x)")
    }

    // MARK: - Surface contracts

    /// applyImpulse from rest adds exactly maxSpeed * knockbackImpulseScale.
    func testImpulseMatchesKnockbackFormula() {
        var motion = TiltSlideMotion(leftBound: 0, rightBound: 800)
        motion.applyImpulse(direction: 1)
        XCTAssertEqual(motion.vx, Tuning.Penguin.maxSpeed * Tuning.Penguin.knockbackImpulseScale)
        motion.applyImpulse(direction: -1)
        XCTAssertEqual(motion.vx, 0, accuracy: acc)
    }

    func testResetZeroesVelocity() {
        var motion = TiltSlideMotion(leftBound: 0, rightBound: 800)
        var x = startX
        for _ in 1...30 { step(&motion, &x, tilt: 1.0) }
        XCTAssertNotEqual(motion.vx, 0)
        motion.reset()
        XCTAssertEqual(motion.vx, 0)
    }
}
