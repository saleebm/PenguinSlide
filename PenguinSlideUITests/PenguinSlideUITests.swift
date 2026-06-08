import XCTest

final class PenguinSlideUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTitleScreenAppears() throws {
        let app = XCUIApplication()
        app.launch()

        let tapToStart = app.otherElements["Tap to start"]
        XCTAssertTrue(tapToStart.waitForExistence(timeout: 5))

        XCTAssertTrue(app.otherElements["PENGUIN SLIDE"].exists)
        XCTAssertTrue(app.otherElements["Tilt your phone to slide"].exists)
    }

    func testStartTriggersGameAndShowsGameOver() throws {
        let app = XCUIApplication()
        app.launch()

        let tapToStart = app.otherElements["Tap to start"]
        XCTAssertTrue(tapToStart.waitForExistence(timeout: 5))
        tapToStart.tap()

        // Drive game-over via the #if DEBUG accessibility hook installed by
        // GameScene (penguinslide-ei0). Removes the 30 s physics-dependent
        // wait and decouples the test from icicle timing.
        app.otherElements["debugForceGameOver"].tap()

        // Game-over is now the SwiftUI GameOverView page (presented by
        // ContentView), so the restart control is a button, not an SK label.
        let playAgain = app.buttons["Play Again"]
        XCTAssertTrue(playAgain.waitForExistence(timeout: 2))
    }

    func testRestartReturnsToPlayableState() throws {
        let app = XCUIApplication()
        app.launch()

        app.otherElements["Tap to start"].tap()
        app.otherElements["debugForceGameOver"].tap()

        let playAgain = app.buttons["Play Again"]
        XCTAssertTrue(playAgain.waitForExistence(timeout: 2))
        playAgain.tap()

        // The page should dismiss and a fresh playable scene resume.
        // We can't easily assert a fresh score 0 since play starts immediately,
        // but the game-over page should be gone shortly after.
        XCTAssertTrue(playAgain.waitForNonExistence(timeout: 2))
    }

    func testScoreIncrementsDuringRound() throws {
        let app = XCUIApplication()
        app.launch()

        let tapToStart = app.otherElements["Tap to start"]
        XCTAssertTrue(tapToStart.waitForExistence(timeout: 5))
        tapToStart.tap()

        // Score climbs from elapsed time alone (score = Int(elapsed *
        // survivalRate) + bonusPoints), so it grows on the simulator with no
        // gyro/tilt input. Wait a few seconds, then read the HUD score label.
        sleep(3)

        // The score SKLabelNode surfaces its text ("0", "26", "184", ...) via
        // SpriteKit accessibility — no hook needed (see CLAUDE.md). It's the
        // only bare positive integer in the tree ("Best: N" has letters), so we
        // match it with a digits-only predicate and read firstMatch.
        //
        // Do NOT enumerate allElementsBoundByIndex here: the HUD mutates every
        // frame (the score relabels, combo/+N nodes come and go), so resolving
        // each cached index lazily throws "No matches found for Element at
        // index N" mid-read. firstMatch resolves a single element in one shot.
        let scoreLabel = app.otherElements
            .matching(NSPredicate(format: "label MATCHES %@", "^[1-9][0-9]*$"))
            .firstMatch
        XCTAssertTrue(scoreLabel.waitForExistence(timeout: 5),
                      "Expected a numeric score SKLabelNode to climb above 0")
        let score = Int(scoreLabel.label)

        XCTAssertNotNil(score, "Score label should parse as an Int")
        XCTAssertGreaterThan(score ?? 0, 10, "Score should climb past 10 after ~3s of play")
    }
}
