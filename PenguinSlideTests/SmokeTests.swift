//
//  SmokeTests.swift
//  PenguinSlideTests
//
//  Seed test for the host-app unit-test target (penguinslide-gyu.6).
//  Proves the bundle builds, `@testable import PenguinSlide` resolves
//  against the app host, and exercises the pure PenguinTuning math that
//  downstream encounter beads (DepthProjector, EncounterTrigger,
//  TiltSlideMotion, snowball collision) will extend with their own suites.
//

import XCTest
@testable import PenguinSlide

final class SmokeTests: XCTestCase {

    /// Fresh-install defaults must keep the derived trio
    /// (maxSpeed / tiltResponseRate / tiltCurve) coherent with
    /// `tiltIntensityDefault` — `init()` routes through
    /// `applyTiltIntensity`, so any drift here means the formula and
    /// the stored defaults disagree.
    func testPenguinTuningDefaultsAreCoherentWithDerivedFormula() {
        let tuning = PenguinTuning()
        let derived = PenguinTuning.derived(from: PenguinTuning.tiltIntensityDefault)

        XCTAssertEqual(tuning.tiltIntensity, PenguinTuning.tiltIntensityDefault)
        XCTAssertEqual(tuning.maxSpeed, derived.maxSpeed)
        XCTAssertEqual(tuning.tiltResponseRate, derived.tiltResponseRate)
        XCTAssertEqual(tuning.tiltCurve, derived.tiltCurve)
        XCTAssertTrue(PenguinTuning.speedRange.contains(tuning.maxSpeed))

        print("""
        Tuning.Penguin defaults: tiltIntensity=\(tuning.tiltIntensity) \
        maxSpeed=\(tuning.maxSpeed) tiltResponseRate=\(tuning.tiltResponseRate) \
        tiltCurve=\(tuning.tiltCurve) iceDecayRate=\(tuning.iceDecayRate) \
        maxHealth=\(tuning.maxHealth) iFrameDuration=\(tuning.iFrameDuration)
        """)
    }

    /// `applyTiltIntensity` clamps out-of-range input and keeps the
    /// derived fields in sync with the clamped value.
    func testApplyTiltIntensityClampsAndStaysCoherent() {
        var tuning = PenguinTuning()

        tuning.applyTiltIntensity(2.0)
        XCTAssertEqual(tuning.tiltIntensity, 1.0)
        XCTAssertEqual(tuning.maxSpeed, PenguinTuning.derived(from: 1.0).maxSpeed)

        tuning.applyTiltIntensity(-1.0)
        XCTAssertEqual(tuning.tiltIntensity, 0.0)
        XCTAssertEqual(tuning.maxSpeed, PenguinTuning.derived(from: 0.0).maxSpeed)
    }

    /// penguinslide-gyu.8 acceptance: every encounter animation state must
    /// slice to the frame count recorded in `spritecook-assets.json` (the
    /// integration contract). An empty/short array means the imageset or
    /// the frame-count constant drifted from the delivered sheet.
    func testEncounterAnimationsFramesMatchManifestCounts() {
        let expected: [(EncounterAnimState, Int, Bool)] = [
            (.monsterIdle, 12, true),
            (.monsterThrow, 10, false),
            (.monsterRoar, 8, false),
            (.papiSlide, 8, true),
        ]
        for (state, count, loops) in expected {
            XCTAssertEqual(EncounterAnimations.frames(for: state).count, count, "\(state)")
            XCTAssertEqual(EncounterAnimations.loops(state), loops, "\(state)")
        }
    }
}
