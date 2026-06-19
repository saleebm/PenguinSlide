//
//  EncounterDebugStateTests.swift
//  PenguinSlideTests
//
//  penguinslide-gyu.21: pins the exact text format of the DEBUG-only
//  `encounterState:` accessibility mirror. EncounterUITests (gyu.22) and
//  agent-device scripts match on these strings, so a drive-by format change
//  must fail here first — in a fast pure-logic test, not a sim UI run.
//

import XCTest
@testable import PenguinSlide

final class EncounterDebugStateTests: XCTestCase {

    // MARK: - Bead-contract example

    /// The bead's literal example: "encounterState:encounter volley=3/8 hp=2"
    /// (phase, resolved/total, current hp), followed by the node-leak counts.
    func testMidVolleyFormatMatchesBeadContract() {
        let text = GameScene.debugEncounterStateText(phase: "encounter",
                                                     resolved: 3,
                                                     total: 8,
                                                     hp: 2,
                                                     worldChildren: 12,
                                                     encounterChildren: 5)
        XCTAssertEqual(text, "encounterState:encounter volley=3/8 hp=2 w=12 e=5",
                       "encounterState format is a test API — gyu.22 and agent-device match on it; got \(text)")
    }

    // MARK: - Phase-name prefixes

    /// Tests phase-match with `hasPrefix("encounterState:<phase> ")` — every
    /// phase name must produce that prefix, and no phase name may be a
    /// prefix of another (guards e.g. "encounter" accidentally matching an
    /// "encounterOutro"-style name).
    func testEveryPhaseNameYieldsAnUnambiguousPrefix() {
        let phases = ["normal", "intro", "encounter", "outro"]
        for phase in phases {
            let text = GameScene.debugEncounterStateText(phase: phase,
                                                         resolved: 0,
                                                         total: 0,
                                                         hp: 3,
                                                         worldChildren: 9,
                                                         encounterChildren: 0)
            XCTAssertTrue(text.hasPrefix("encounterState:\(phase) "),
                          "phase \(phase) must lead the label; got \(text)")
        }
        for a in phases {
            for b in phases where a != b {
                XCTAssertFalse(b.hasPrefix(a),
                               "phase name \(a) is a prefix of \(b): prefix-matching tests would be ambiguous")
            }
        }
    }

    // MARK: - Idle / reset state

    /// Outside an encounter there is no plan: the counter reads volley=0/0
    /// and full HP — the exact text a cold start and a post-outro reset
    /// (after penguin.reset() refires onHealthChanged) both converge to.
    func testIdleNormalStateReadsZeroVolley() {
        let text = GameScene.debugEncounterStateText(phase: "normal",
                                                     resolved: 0,
                                                     total: 0,
                                                     hp: Tuning.Penguin.maxHealth,
                                                     worldChildren: 14,
                                                     encounterChildren: 0)
        XCTAssertTrue(text.hasPrefix("encounterState:normal volley=0/0 hp=\(Tuning.Penguin.maxHealth)"),
                      "idle state must read volley=0/0 at full HP; got \(text)")
        XCTAssertTrue(text.hasSuffix("e=0"),
                      "encounterRoot must report empty (e=0) outside an encounter; got \(text)")
    }

    /// hp=0 is the lethal-ball frame: the frozen death frame must still show
    /// the full tally (onSnowballHit ticks the counter BEFORE tryTakeHit).
    func testLethalBallFrameShowsFullTallyAtZeroHP() {
        let text = GameScene.debugEncounterStateText(phase: "encounter",
                                                     resolved: 8,
                                                     total: 8,
                                                     hp: 0,
                                                     worldChildren: 12,
                                                     encounterChildren: 7)
        XCTAssertTrue(text.contains("volley=8/8"), "death frame must show the full tally; got \(text)")
        XCTAssertTrue(text.contains("hp=0"), "death frame must show hp=0; got \(text)")
    }
}
