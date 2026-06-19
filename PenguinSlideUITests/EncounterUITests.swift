//
//  EncounterUITests.swift
//  PenguinSlideUITests
//
//  penguinslide-gyu.22: end-to-end XCUI coverage of the Snow Monster
//  encounter (requirement R10), driven ENTIRELY through the DEBUG hooks —
//  never random triggers or physics timing (repo test doctrine):
//
//  - `debugForceEncounter` (hidden SKLabelNode tap target, gyu.21) enters
//    the intro on demand.
//  - The `encounterState:` mirror label (gyu.21) is the synchronous state
//    read: "encounterState:<phase> volley=r/t hp=n w=.. e=.." (format
//    pinned by EncounterDebugStateTests).
//  - The `-encounterTestVolley` launch argument (this bead) scripts a
//    deterministic volley. The simulator has NO gyro, so outcomes cannot
//    be steered by tilt; instead `hitRadius=0` makes every ball a dodge
//    (forced WIN) and `hitRadius=400` makes every ball connect — the
//    corridor is ±280, so no aim jitter can escape (forced LOSS). This is
//    deliberately more hermetic than orchestrating MotionInjector from
//    XCUITest, which is shell-script territory (test-smoke.sh). Grammar
//    documented on SnowMonsterEncounterSystem.TestVolleyOverrides; parse
//    behavior pinned by EncounterTestVolleyConfigTests.
//
//  Everything here targets SKLabelNode accessibility labels
//  (app.otherElements) or SwiftUI buttons. "Element not found" usually
//  means a Release build — every hook is DEBUG-gated.
//

import XCTest

final class EncounterUITests: XCTestCase {

    /// Mirrors PenguinTuning.maxHealth's default (3). The settings UI can
    /// override tuning via UserDefaults, but maxHealth has no settings
    /// control, so the default holds on any simulator this suite runs on.
    private static let maxHealth = 3

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Launch / drive helpers

    /// Launch the app, optionally with a hermetic test-volley spec (the
    /// DEBUG-gated `-encounterTestVolley` launch argument GameScene parses
    /// at didMove time).
    private func launchApp(volley: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let volley {
            app.launchArguments += ["-encounterTestVolley", volley]
        }
        app.launch()
        NSLog("[EncounterUITests] launched app (volley spec: \(volley ?? "<none — Tuning defaults>"))")
        return app
    }

    private func startRun(_ app: XCUIApplication,
                          file: StaticString = #filePath, line: UInt = #line) {
        let tapToStart = app.otherElements["Tap to start"]
        XCTAssertTrue(tapToStart.waitForExistence(timeout: 5),
                      "start prompt should appear on launch", file: file, line: line)
        tapToStart.tap()
        NSLog("[EncounterUITests] run started")
    }

    /// Tap the gyu.21 debug hook that forces the encounter intro. Mid-
    /// encounter taps are no-ops by contract (testNoNestedEncounter).
    private func forceEncounter(_ app: XCUIApplication,
                                file: StaticString = #filePath, line: UInt = #line) {
        let hook = app.otherElements["debugForceEncounter"]
        XCTAssertTrue(hook.waitForExistence(timeout: 5),
                      "debugForceEncounter hook not found — Release build? (DEBUG-only node)",
                      file: file, line: line)
        hook.tap()
        NSLog("[EncounterUITests] tapped debugForceEncounter (state: \(stateSnapshot(app)))")
    }

    // MARK: - encounterState mirror reading

    /// Parsed form of the gyu.21 mirror label.
    private struct EncounterState {
        let raw: String
        let phase: String     // normal | intro | encounter | outro
        let resolved: Int     // balls resolved (hit or dodged) this volley
        let total: Int        // the volley plan's ball count (0 = no plan)
        let hp: Int           // shared penguin HP
    }

    private func stateElement(_ app: XCUIApplication) -> XCUIElement {
        // The label's text mutates (phase/volley/hp fields), so match the
        // stable prefix and resolve firstMatch fresh on every read — never
        // cache allElementsBoundByIndex against a mutating HUD (see
        // PenguinSlideUITests.testScoreIncrementsDuringRound).
        app.otherElements.matching(
            NSPredicate(format: "label BEGINSWITH %@", "encounterState:")).firstMatch
    }

    /// Non-asserting raw read, for interpolation into failure messages.
    private func stateSnapshot(_ app: XCUIApplication) -> String {
        let element = stateElement(app)
        return element.exists ? element.label : "<encounterState label not found>"
    }

    /// Asserting read: the label must exist and parse.
    private func readState(_ app: XCUIApplication,
                           file: StaticString = #filePath, line: UInt = #line) -> EncounterState {
        let element = stateElement(app)
        XCTAssertTrue(element.waitForExistence(timeout: 5),
                      "encounterState label not found — Release build? (DEBUG-only node)",
                      file: file, line: line)
        let raw = element.label
        guard let state = Self.parse(stateText: raw) else {
            XCTFail("unparseable encounterState label: \"\(raw)\"", file: file, line: line)
            return EncounterState(raw: raw, phase: "?", resolved: -1, total: -1, hp: -1)
        }
        return state
    }

    /// Parse "encounterState:<phase> volley=r/t hp=n w=.. e=..". The
    /// format is pinned by EncounterDebugStateTests so a drive-by change
    /// fails there (fast, pure logic) before it fails here.
    private static func parse(stateText: String) -> EncounterState? {
        guard stateText.hasPrefix("encounterState:") else { return nil }
        let fields = stateText.dropFirst("encounterState:".count).split(separator: " ")
        guard let phaseField = fields.first else { return nil }
        var resolved = -1, total = -1, hp = -1
        for field in fields.dropFirst() {
            if field.hasPrefix("volley=") {
                let parts = field.dropFirst("volley=".count).split(separator: "/")
                if parts.count == 2 {
                    resolved = Int(parts[0]) ?? -1
                    total = Int(parts[1]) ?? -1
                }
            } else if field.hasPrefix("hp=") {
                hp = Int(field.dropFirst("hp=".count)) ?? -1
            }
        }
        guard resolved >= 0, total >= 0, hp >= 0 else { return nil }
        return EncounterState(raw: stateText, phase: String(phaseField),
                              resolved: resolved, total: total, hp: hp)
    }

    /// Poll the state label until `condition` holds, logging every state
    /// change as an NSLog breadcrumb so failures localize precisely.
    /// Fails (with the last observed state in the message) on timeout.
    @discardableResult
    private func waitForState(_ app: XCUIApplication,
                              timeout: TimeInterval,
                              description: String,
                              file: StaticString = #filePath, line: UInt = #line,
                              until condition: (EncounterState) -> Bool) -> EncounterState {
        let deadline = Date().addingTimeInterval(timeout)
        var lastLogged = ""
        repeat {
            let state = readState(app, file: file, line: line)
            if state.raw != lastLogged {
                NSLog("[EncounterUITests] state → \(state.raw) (waiting for: \(description))")
                lastLogged = state.raw
            }
            if condition(state) { return state }
            usleep(250_000)
        } while Date() < deadline
        let last = readState(app, file: file, line: line)
        if condition(last) { return last }
        XCTFail("timed out (\(Int(timeout)) s) waiting for \(description); last observed state: \(last.raw)",
                file: file, line: line)
        return last
    }

    /// Digits-only score query (the testScoreIncrementsDuringRound
    /// pattern): the HUD score is the only bare positive integer in the
    /// tree. ALWAYS resolve via firstMatch — never allElementsBoundByIndex
    /// against the mutating HUD.
    private func scoreQuery(_ app: XCUIApplication) -> XCUIElementQuery {
        app.otherElements.matching(NSPredicate(format: "label MATCHES %@", "^[1-9][0-9]*$"))
    }

    // MARK: - 1. Intro banner + encounter HUD

    func testForceEncounterShowsIntroAndHUD() throws {
        let app = launchApp()

        XCTContext.runActivity(named: "Start a run and force the encounter") { _ in
            startRun(app)
            forceEncounter(app)
        }

        XCTContext.runActivity(named: "Intro banner appears during the intro") { _ in
            let banner = app.otherElements["PAPI PENGUIN VS. THE SNOW MONSTER"]
            XCTAssertTrue(banner.waitForExistence(timeout: 5),
                          "intro banner should appear after forcing the encounter; state: \(stateSnapshot(app))")
            NSLog("[EncounterUITests] intro banner visible (state: \(stateSnapshot(app)))")
        }

        XCTContext.runActivity(named: "Volley progress appears and the banner clears") { _ in
            // The progress counter ("0 / 6" etc.) reveals at encounter
            // entry; the " / " separator is part of the Copy contract.
            let progress = app.otherElements.matching(
                NSPredicate(format: "label MATCHES %@", "^\\d+ / \\d+$")).firstMatch
            XCTAssertTrue(progress.waitForExistence(timeout: 10),
                          "volley progress label should appear at encounter entry; state: \(stateSnapshot(app))")
            NSLog("[EncounterUITests] progress label visible: \(progress.label) (state: \(stateSnapshot(app)))")

            let banner = app.otherElements["PAPI PENGUIN VS. THE SNOW MONSTER"]
            XCTAssertTrue(banner.waitForNonExistence(timeout: 5),
                          "intro banner should clear once the encounter begins; state: \(stateSnapshot(app))")
        }
    }

    // MARK: - 2. Loss path → standard game-over → fresh round

    func testEncounterLossFlowsToGameOver() throws {
        // Forced LOSS config: hitRadius=400 connects every ball (corridor
        // ±280 means no jitter escapes), and interval 1.6 s > the 1.0 s
        // i-frame window so each of the first three hits drains a heart —
        // a deterministic no-input death on the gyro-less simulator.
        let app = launchApp(volley: "count=6 interval=1.6 zSpeed=420 hitRadius=400")
        startRun(app)
        forceEncounter(app)

        XCTContext.runActivity(named: "HP drains via the state label") { _ in
            let hitState = waitForState(app, timeout: 30,
                                        description: "first snowball hit (hp < \(Self.maxHealth))") {
                $0.hp < Self.maxHealth
            }
            NSLog("[EncounterUITests] first hit landed: \(hitState.raw)")
        }

        XCTContext.runActivity(named: "HP exhausts into the standard game-over page") { _ in
            let playAgain = app.buttons["Play Again"]
            XCTAssertTrue(playAgain.waitForExistence(timeout: 30),
                          "Play Again should appear once HP exhausts mid-volley; state: \(stateSnapshot(app))")
            NSLog("[EncounterUITests] game-over page up (state: \(stateSnapshot(app)))")
            playAgain.tap()
        }

        XCTContext.runActivity(named: "Play Again restores a fresh normal round") { _ in
            let fresh = waitForState(app, timeout: 10,
                                     description: "fresh normal round (phase normal, full hp, no volley)") {
                $0.phase == "normal" && $0.hp == Self.maxHealth && $0.total == 0
            }
            NSLog("[EncounterUITests] fresh round state: \(fresh.raw)")
            XCTAssertFalse(app.otherElements["Tap to start"].exists,
                           "restart resumes play directly — no start prompt; state: \(fresh.raw)")
            let score = scoreQuery(app).firstMatch
            XCTAssertTrue(score.waitForExistence(timeout: 10),
                          "score label should climb again after restart; state: \(stateSnapshot(app))")
            NSLog("[EncounterUITests] post-restart score visible: \(score.label)")
        }
    }

    // MARK: - 3. Win path → DODGED! → back to the run, score paid

    func testEncounterWinReturnsToRun() throws {
        // Forced WIN config: hitRadius=0 means no ball can ever connect —
        // every ball resolves as a dodge with zero tilt input. Short,
        // quick volley keeps the test snappy.
        let app = launchApp(volley: "count=3 interval=0.8 zSpeed=1200 hitRadius=0")
        startRun(app)

        var entryScore = 0
        XCTContext.runActivity(named: "Read the entry score") { _ in
            // Let the survival drip climb past 0 so the score label matches
            // the digits-only predicate (firstMatch — see helper).
            let score = scoreQuery(app).firstMatch
            XCTAssertTrue(score.waitForExistence(timeout: 10),
                          "entry score should climb above 0 before the encounter")
            entryScore = Int(score.label) ?? 0
            XCTAssertGreaterThan(entryScore, 0, "entry score should parse as a positive Int")
            NSLog("[EncounterUITests] entry score: \(entryScore)")
        }

        forceEncounter(app)

        XCTContext.runActivity(named: "Survive the volley → DODGED! banner") { _ in
            let banner = app.otherElements["DODGED!"]
            XCTAssertTrue(banner.waitForExistence(timeout: 30),
                          "DODGED! banner should play at the win outro; state: \(stateSnapshot(app))")
            NSLog("[EncounterUITests] DODGED! banner visible (state: \(stateSnapshot(app)))")
        }

        XCTContext.runActivity(named: "State returns to normal") { _ in
            waitForState(app, timeout: 15, description: "phase normal after the outro") {
                $0.phase == "normal"
            }
        }

        XCTContext.runActivity(named: "Exit score strictly greater than entry") { _ in
            // The win pays volleyCompletionBonus (+ per-dodge bonuses)
            // while the survival drip was frozen, so the score read back
            // in .normal must exceed the entry read strictly.
            let score = scoreQuery(app).firstMatch
            XCTAssertTrue(score.waitForExistence(timeout: 10),
                          "score label should be visible again after the outro; state: \(stateSnapshot(app))")
            let exitScore = Int(score.label) ?? -1
            NSLog("[EncounterUITests] exit score: \(exitScore) (entry was \(entryScore))")
            XCTAssertGreaterThan(exitScore, entryScore,
                                 "win bonus must land: exit score \(exitScore) should exceed entry \(entryScore); state: \(stateSnapshot(app))")
        }
    }

    // MARK: - 4. HP continuity across the encounter boundary

    func testEncounterHPContinuity() throws {
        // Exactly ONE guaranteed hit: a single always-connecting ball.
        // The volley completes regardless of outcome (completion is
        // resolution accounting, not a no-hit requirement), so the run
        // survives into the outro with hp = maxHealth - 1.
        let app = launchApp(volley: "count=1 interval=1.0 zSpeed=900 hitRadius=400")
        startRun(app)
        forceEncounter(app)

        XCTContext.runActivity(named: "Exactly one hit lands (state label hp field)") { _ in
            let hitState = waitForState(app, timeout: 30,
                                        description: "the single ball connects (hp \(Self.maxHealth - 1))") {
                $0.hp == Self.maxHealth - 1
            }
            XCTAssertEqual(hitState.resolved, 1,
                           "the hit must be the volley's one resolved ball; state: \(hitState.raw)")
        }

        XCTContext.runActivity(named: "Hearts carry across the outro (hp field mirror)") { _ in
            // Hearts are sprites (invisible to XCUITest) — the state
            // label's hp field is the assertable mirror per the bead.
            let backToNormal = waitForState(app, timeout: 20,
                                            description: "phase normal after the win outro") {
                $0.phase == "normal"
            }
            XCTAssertEqual(backToNormal.hp, Self.maxHealth - 1,
                           "hp must carry maxHealth-1 across the encounter boundary; state: \(backToNormal.raw)")
        }
    }

    // MARK: - 5. No nested encounter

    func testNoNestedEncounter() throws {
        // Slow, harmless volley (hitRadius=0, 2 s between throws) so there
        // is ample mid-encounter time to spam the hook.
        let app = launchApp(volley: "count=4 interval=2.0 zSpeed=300 hitRadius=0")
        startRun(app)
        forceEncounter(app)

        let entered = waitForState(app, timeout: 15, description: "encounter phase begins") {
            $0.phase == "encounter"
        }
        XCTAssertEqual(entered.total, 4,
                       "the launch-config volley count must be in force; state: \(entered.raw)")

        XCTContext.runActivity(named: "Tap the force hook twice mid-encounter") { _ in
            forceEncounter(app)
            forceEncounter(app)
            sleep(1)
        }

        XCTContext.runActivity(named: "Volley accounting stays single") { _ in
            let after = readState(app)
            NSLog("[EncounterUITests] state after double-tap: \(after.raw)")
            XCTAssertNotEqual(after.phase, "intro",
                              "a mid-encounter force tap must not re-enter the intro; state: \(after.raw)")
            XCTAssertEqual(after.phase, "encounter",
                           "the slow volley should still be running; state: \(after.raw)")
            XCTAssertEqual(after.total, entered.total,
                           "progress total must be unchanged — one volley, no nesting; state: \(after.raw)")
        }
    }

    // MARK: - 6. Settings round-trip mid-encounter (dt sentinel smoke)

    func testSettingsDuringEncounter() throws {
        // Long, harmless volley so the encounter comfortably outlasts the
        // settings round-trip and still has balls left to resolve after.
        let app = launchApp(volley: "count=6 interval=2.0 zSpeed=300 hitRadius=0")
        startRun(app)
        forceEncounter(app)

        let entered = waitForState(app, timeout: 15, description: "encounter phase begins") {
            $0.phase == "encounter"
        }
        let resolvedBefore = entered.resolved
        NSLog("[EncounterUITests] entering settings with state: \(entered.raw)")

        XCTContext.runActivity(named: "Open and close settings mid-encounter") { _ in
            // The gear is hidden during game-over ONLY — mid-encounter it
            // must be present and tappable.
            let gear = app.buttons["Settings"]
            XCTAssertTrue(gear.waitForExistence(timeout: 5),
                          "settings gear should be visible mid-encounter (hidden during game-over only); state: \(stateSnapshot(app))")
            gear.tap()

            let close = app.buttons["Close settings"]
            XCTAssertTrue(close.waitForExistence(timeout: 5),
                          "settings sheet should open over the paused encounter")
            NSLog("[EncounterUITests] settings open (state: \(stateSnapshot(app)))")
            close.tap()
        }

        XCTContext.runActivity(named: "State stays valid and progress advances afterward") { _ in
            // readState fails the test if the label no longer parses —
            // the "still valid" half of the assertion.
            let resumed = readState(app)
            NSLog("[EncounterUITests] resumed from settings with state: \(resumed.raw)")
            XCTAssertTrue(["encounter", "outro", "normal"].contains(resumed.phase),
                          "resume must land in a coherent phase (dt sentinel symmetry); state: \(resumed.raw)")

            // The dt == 0 resume sentinel must not have frozen OR fast-
            // forwarded the volley: more balls resolve on the live clock
            // (or the volley finishes into the outro/normal).
            waitForState(app, timeout: 30,
                         description: "volley progress advances past \(resolvedBefore) after the settings round-trip") {
                $0.resolved > resolvedBefore || $0.phase == "outro" || $0.phase == "normal"
            }
        }
    }
}
