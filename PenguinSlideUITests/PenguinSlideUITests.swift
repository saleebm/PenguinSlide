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

        let tapAgain = app.otherElements["Tap to play again"]
        XCTAssertTrue(tapAgain.waitForExistence(timeout: 2))
    }

    func testRestartReturnsToPlayableState() throws {
        let app = XCUIApplication()
        app.launch()

        app.otherElements["Tap to start"].tap()
        app.otherElements["debugForceGameOver"].tap()

        let tapAgain = app.otherElements["Tap to play again"]
        XCTAssertTrue(tapAgain.waitForExistence(timeout: 2))
        tapAgain.tap()

        // The overlay should clear and a fresh playable scene resume.
        // We can't easily assert a fresh score 0 since play starts immediately,
        // but the game-over overlay should be gone for at least a moment.
        XCTAssertFalse(app.otherElements["Tap to play again"].exists)
    }
}
