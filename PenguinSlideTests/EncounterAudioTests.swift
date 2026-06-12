//
//  EncounterAudioTests.swift
//  PenguinSlideTests
//
//  penguinslide-gyu.28: encounter music sting + bg-music duck/restore.
//  penguinslide-gyu.27: encounter SFX (throw whoosh, snowball impact,
//  dodge whoosh, flyby, monster roar).
//  The runtime choreography (duck/restore, sounds firing on their
//  events with sane mix levels, background-silences-everything) is
//  device-verified under penguinslide-x06; these tests pin the
//  compile-time contracts that protect it:
//    - the missing-file guard (absent staged audio must yield nil, never
//      a trapping SKAction.playSoundFileNamed),
//    - the delivered .caf sets actually being in the app bundle,
//    - the Tuning.Encounter audio knobs staying coherent (a "duck" that
//      sits at/above the 0.18 baseline would restore upward; SFX levels
//      staying in the bed/shatter neighborhood), and
//    - the pure gyu.27 volume mappings (severity-lerped dodge whoosh,
//      accepted-scaled impact, the flyby near-miss threshold).
//

import XCTest
import SpriteKit
@testable import PenguinSlide

final class EncounterAudioTests: XCTestCase {

    /// Guard contract: a file that isn't bundled yields nil, so call
    /// sites skip the run(_:) and the build stays silent-but-safe.
    /// (SKAction.playSoundFileNamed with a missing resource is a crash
    /// at action-creation time — the whole reason the guard exists.)
    func testGuardedOneShotReturnsNilForMissingFile() {
        XCTAssertNil(GameScene.guardedOneShot("definitely_not_a_real_sound.caf"))
    }

    /// Delivery contract: the gyu.28 audio set (intro sting, win sting,
    /// ambience loop) is bundled in this build, so the cached sting
    /// actions and the ambience node are live rather than guarded-out.
    func testEncounterAudioFilesAreBundled() {
        for file in ["encounter_sting.caf",
                     "encounter_win.caf",
                     "encounter_ambience.caf"] {
            XCTAssertNotNil(GameScene.guardedOneShot(file),
                            "\(file) missing from the app bundle")
        }
    }

    /// Knob sanity: the duck must sit strictly BELOW the 0.18 bed
    /// baseline (GameScene.bgMusicVolume) and at/above silence; ramps
    /// must be positive so changeVolume actually ramps; the ambience
    /// level stays under the 0.22 shatter ceiling so SFX cut through.
    func testEncounterAudioKnobsAreCoherent() {
        XCTAssertGreaterThanOrEqual(Tuning.Encounter.bgDuckVolume, 0)
        XCTAssertLessThan(Tuning.Encounter.bgDuckVolume, 0.18)
        XCTAssertGreaterThan(Tuning.Encounter.bgDuckRamp, 0)
        XCTAssertGreaterThan(Tuning.Encounter.bgRestoreRamp, 0)
        XCTAssertGreaterThan(Tuning.Encounter.ambienceVolume, 0)
        XCTAssertLessThanOrEqual(Tuning.Encounter.ambienceVolume, 0.22)
    }

    // MARK: - gyu.27 encounter SFX

    /// Delivery contract: the gyu.27 SFX set is bundled in this build,
    /// so the system's SKAudioNodes and the roar one-shot are live
    /// rather than guarded-out. (guardedOneShot doubles as the bundle
    /// probe — it nil-guards on the exact Bundle.main.url check the
    /// audio-node factory uses.)
    func testEncounterSfxFilesAreBundled() {
        for file in ["snowball_throw.caf",
                     "snowball_impact.caf",
                     "dodge_whoosh.caf",
                     "snowball_flyby.caf",
                     "snowman_roar.caf"] {
            XCTAssertNotNil(GameScene.guardedOneShot(file),
                            "\(file) missing from the app bundle")
        }
    }

    /// Dodge whoosh volume lerps min → max with severity: close shaves
    /// are LOUDER, out-of-range severities clamp instead of
    /// extrapolating past the knobs.
    func testDodgeWhooshVolumeScalesWithSeverity() {
        let lo = SnowMonsterEncounterSystem.dodgeWhooshVolume(severity: 0)
        let mid = SnowMonsterEncounterSystem.dodgeWhooshVolume(severity: 0.5)
        let hi = SnowMonsterEncounterSystem.dodgeWhooshVolume(severity: 1)
        XCTAssertEqual(lo, Tuning.Encounter.dodgeWhooshVolumeMin)
        XCTAssertEqual(hi, Tuning.Encounter.dodgeWhooshVolumeMax)
        XCTAssertGreaterThan(mid, lo)
        XCTAssertLessThan(mid, hi)
        // Clamp contract — a bad caller degrades to the nearest knob.
        XCTAssertEqual(SnowMonsterEncounterSystem.dodgeWhooshVolume(severity: -2), lo)
        XCTAssertEqual(SnowMonsterEncounterSystem.dodgeWhooshVolume(severity: 7), hi)
    }

    /// Impact volume mirrors the accepted/absorbed soft-FX distinction:
    /// an i-frame-absorbed hit is strictly quieter than an HP-losing one.
    func testImpactVolumeAcceptedScaling() {
        let full = SnowMonsterEncounterSystem.impactVolume(accepted: true)
        let soft = SnowMonsterEncounterSystem.impactVolume(accepted: false)
        XCTAssertEqual(full, Tuning.Encounter.impactVolume)
        XCTAssertEqual(soft, Tuning.Encounter.impactVolume
                             * Tuning.Encounter.impactAbsorbedScale)
        XCTAssertLessThan(soft, full)
    }

    /// Flyby layer fires only for near-misses, with an INCLUSIVE
    /// threshold (severity exactly at the knob fires — the dodgeHaptic
    /// >= convention).
    func testFlybyNearMissThreshold() {
        let t = Tuning.Encounter.flybySeverityMin
        XCTAssertTrue(SnowMonsterEncounterSystem.flybyFires(severity: 1))
        XCTAssertTrue(SnowMonsterEncounterSystem.flybyFires(severity: t))
        XCTAssertFalse(SnowMonsterEncounterSystem.flybyFires(severity: t - 0.01))
        XCTAssertFalse(SnowMonsterEncounterSystem.flybyFires(severity: 0))
    }

    /// Mix-discipline sanity for the gyu.27 knobs: everything audible
    /// (> 0) but capped in the established neighborhood (bed 0.18,
    /// shatter ceiling 0.22; the accepted impact gets a touch more as
    /// the failure beat) so the encounter never drowns the mix. The
    /// absorbed scale must genuinely soften, and the whoosh lerp must
    /// point upward (min < max) or "close shaves are louder" inverts.
    func testEncounterSfxKnobsAreCoherent() {
        XCTAssertGreaterThan(Tuning.Encounter.throwWhooshVolume, 0)
        XCTAssertLessThanOrEqual(Tuning.Encounter.throwWhooshVolume, 0.3)
        XCTAssertGreaterThan(Tuning.Encounter.impactVolume, 0)
        XCTAssertLessThanOrEqual(Tuning.Encounter.impactVolume, 0.35)
        XCTAssertGreaterThan(Tuning.Encounter.impactAbsorbedScale, 0)
        XCTAssertLessThan(Tuning.Encounter.impactAbsorbedScale, 1)
        XCTAssertGreaterThan(Tuning.Encounter.dodgeWhooshVolumeMin, 0)
        XCTAssertLessThan(Tuning.Encounter.dodgeWhooshVolumeMin,
                          Tuning.Encounter.dodgeWhooshVolumeMax)
        XCTAssertLessThanOrEqual(Tuning.Encounter.dodgeWhooshVolumeMax, 0.25)
        XCTAssertGreaterThan(Tuning.Encounter.flybyVolume, 0)
        XCTAssertLessThanOrEqual(Tuning.Encounter.flybyVolume, 0.25)
        XCTAssertGreaterThanOrEqual(Tuning.Encounter.flybySeverityMin, 0)
        XCTAssertLessThanOrEqual(Tuning.Encounter.flybySeverityMin, 1)
    }
}
