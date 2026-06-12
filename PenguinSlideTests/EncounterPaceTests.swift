//
//  EncounterPaceTests.swift
//  PenguinSlideTests
//
//  penguinslide-fr7: encounter pace knob + dodgeability margin.
//
//  Mina's device feedback said the encounter played too slow, so
//  `Tuning.Encounter.paceScale` became the single number that speeds the
//  whole sequence up coherently. Two contracts are enforced here:
//
//  1. ONE-KNOB CONTRACT — every pace-derived knob (zSpeedStart/End,
//     groundScrollSpeed up; throwIntervalStart/End, telegraphDuration
//     down) must equal its pace-1.0 base scaled by `paceScale`, so feel
//     iteration is exactly one edit and the knobs can never drift apart.
//
//  2. DODGEABILITY MARGIN — at whatever pace ships, a center-aimed ball
//     at the FASTEST speed (zSpeedEnd) must be dodgeable from rest by a
//     player on the GENTLEST input setting (tiltIntensity 0), even when
//     the aim jitter and a max drift curve both conspire toward the
//     dodge side, and even ignoring the telegraph head start. The
//     simulation drives the real `TiltSlideMotion` (the exact integrator
//     PapiAvatar uses), so a future paceScale bump that breaks fairness
//     fails HERE before it reaches Mina's device.
//

import XCTest
import CoreGraphics
@testable import PenguinSlide

final class EncounterPaceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Deterministic input-feel knobs: the test host may carry
        // persisted PenguinTuning overrides (same recipe as
        // TiltSlideMotionTests).
        Tuning.Penguin = PenguinTuning()
    }

    override func tearDown() {
        Tuning.Penguin = .loadFromUserDefaults()
        super.tearDown()
    }

    // MARK: - One-knob contract

    func testPaceScaleIsFasterThanTheFlaggedBuild() {
        // The 2026-06-11 build Mina flagged as "too slow" is pace 1.0.
        // Whatever value iteration lands on must stay above it; the
        // dodgeability test below bounds it from the other side.
        XCTAssertGreaterThan(Tuning.Encounter.paceScale, 1.0,
                             "paceScale must exceed 1.0 — 1.0 is the exact pace Mina flagged as too slow (penguinslide-fr7)")
    }

    func testEveryPaceDerivedKnobScalesFromItsBaseByPaceScale() {
        let pace = Tuning.Encounter.paceScale

        // Speed knobs scale UP.
        XCTAssertEqual(Tuning.Encounter.zSpeedStart,
                       Tuning.Encounter.baseZSpeedStart * pace,
                       accuracy: 1e-9,
                       "zSpeedStart must be base x paceScale — edit paceScale, not the derived knob")
        XCTAssertEqual(Tuning.Encounter.zSpeedEnd,
                       Tuning.Encounter.baseZSpeedEnd * pace,
                       accuracy: 1e-9,
                       "zSpeedEnd must be base x paceScale")
        XCTAssertEqual(Tuning.Encounter.groundScrollSpeed,
                       Tuning.Encounter.baseGroundScrollSpeed * pace,
                       accuracy: 1e-9,
                       "groundScrollSpeed must be base x paceScale so the forward-slide read speeds up with the balls")

        // Time knobs scale DOWN.
        XCTAssertEqual(Tuning.Encounter.throwIntervalStart,
                       Tuning.Encounter.baseThrowIntervalStart / TimeInterval(pace),
                       accuracy: 1e-9,
                       "throwIntervalStart must be base / paceScale")
        XCTAssertEqual(Tuning.Encounter.throwIntervalEnd,
                       Tuning.Encounter.baseThrowIntervalEnd / TimeInterval(pace),
                       accuracy: 1e-9,
                       "throwIntervalEnd must be base / paceScale")
        XCTAssertEqual(Tuning.Encounter.telegraphDuration,
                       Tuning.Encounter.baseTelegraphDuration / TimeInterval(pace),
                       accuracy: 1e-9,
                       "telegraphDuration must be base / paceScale")
    }

    func testGroundScrollNeverOutpacesSnowballs() {
        // Documented invariant from the forward-slide knobs: snowballs
        // must always visibly outpace the ground. Both sides scale by
        // the same paceScale, so this holds at any pace as long as the
        // BASE relation holds — assert the live values anyway.
        XCTAssertLessThan(Tuning.Encounter.groundScrollSpeed,
                          Tuning.Encounter.zSpeedStart,
                          "groundScrollSpeed must stay below zSpeedStart or snowballs stop reading as faster than the ground")
    }

    // MARK: - Dodgeability margin

    /// Worst-case lateral distance a fair dodge can require: the hit
    /// radius itself, plus the full aim jitter landing toward the dodge
    /// side, plus a max-rate drift curve chasing the dodge for the whole
    /// flight. (A rational player dodges away from the ball's actual
    /// lateral position, so this strictly over-asks.)
    private func worstCaseClearance(flightTime: TimeInterval) -> CGFloat {
        Tuning.Encounter.lateralHitRadius
            + Tuning.Encounter.snowballAimJitter
            + Tuning.Encounter.snowballDriftVxMax * CGFloat(flightTime)
    }

    func testFastestBallIsDodgeableFromRestOnGentlestTiltSetting() {
        // Gentlest input feel a player can configure: tiltIntensity 0
        // (slowest maxSpeed, slowest response). If THIS clears, every
        // settings position clears.
        var calm = PenguinTuning()
        calm.applyTiltIntensity(0)
        Tuning.Penguin = calm

        // Fastest ball of the run (end-of-ramp zSpeed) over the full
        // monster->plane depth. The dodge clock starts at the THROW,
        // not at telegraph start — the telegraph head start is real
        // reaction budget on device, withheld here as extra margin.
        let flightTime = TimeInterval(Tuning.Encounter.zMonster
                                      / Tuning.Encounter.zSpeedEnd)
        let required = worstCaseClearance(flightTime: flightTime)

        // The exact integrator + corridor PapiAvatar uses (worldX space:
        // center 0, bounds +-papiLateralRange, sprite half-width inset).
        let range = Tuning.Encounter.papiLateralRange
        let inset = Tuning.Encounter.papiBaseSize * PapiAvatar.halfWidthFraction
        var motion = TiltSlideMotion(leftBound: -range, rightBound: range)

        var x: CGFloat = 0
        var elapsed: TimeInterval = 0
        let dt: TimeInterval = 1.0 / 120.0
        while x < required && elapsed < flightTime {
            motion.update(dt: dt, tilt: 1.0)
            x = motion.integrate(x: x, dt: dt, halfWidth: inset)
            elapsed += dt
        }

        XCTAssertGreaterThanOrEqual(
            x, required,
            "full tilt from rest must clear \(required) pt before the fastest ball lands (flight \(flightTime) s) — paceScale is too hot for the gentlest tilt setting")
        XCTAssertLessThanOrEqual(
            elapsed, flightTime * 0.6,
            "dodge must complete with >=40% of the flight window to spare — a pass with no margin is a fail on device, where reaction time eats the difference")
    }

    func testDodgeCorridorHasRoomForTheWorstCaseClearance() {
        // The wall must never be what makes a dodge impossible: the
        // corridor (minus the avatar's clamp inset) needs to hold the
        // full worst-case clearance from a center start.
        let flightTime = TimeInterval(Tuning.Encounter.zMonster
                                      / Tuning.Encounter.zSpeedEnd)
        let required = worstCaseClearance(flightTime: flightTime)
        let usable = Tuning.Encounter.papiLateralRange
            - Tuning.Encounter.papiBaseSize * PapiAvatar.halfWidthFraction
        XCTAssertGreaterThan(
            usable, required,
            "papiLateralRange minus the clamp inset (\(usable) pt) must exceed the worst-case dodge clearance (\(required) pt), or a center-start dodge can be walled off")
    }
}
