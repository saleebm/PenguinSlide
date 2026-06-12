//
//  EncounterHUDTests.swift
//  PenguinSlideTests
//
//  penguinslide-gyu.20: pins the test-targeted encounter copy (the XCUI
//  bead matches these exact strings), the progress-text format, the
//  EncounterHUD show/hide/reset node behavior, and HUDController's
//  encounter mode (score/best/combo hide, hearts stay). Node-level spot
//  asserts follow the EncounterWorldTests style; SKActions never run
//  without a presented SKView, so assertions target the synchronous
//  state (presence, text, isHidden) rather than animation endpoints.
//

import SpriteKit
import XCTest
@testable import PenguinSlide

final class EncounterHUDTests: XCTestCase {

    private func makeHUD() -> (scene: SKScene, hud: EncounterHUD) {
        let scene = SKScene(size: CGSize(width: 852, height: 393))
        let hud = EncounterHUD(scene: scene, sceneSize: scene.size)
        return (scene, hud)
    }

    /// Every SKLabelNode anywhere under the scene (banners nest labels
    /// inside container nodes).
    private func allLabels(in scene: SKScene) -> [SKLabelNode] {
        var labels: [SKLabelNode] = []
        func walk(_ node: SKNode) {
            if let label = node as? SKLabelNode { labels.append(label) }
            node.children.forEach(walk)
        }
        walk(scene)
        return labels
    }

    private func label(in scene: SKScene, text: String) -> SKLabelNode? {
        allLabels(in: scene).first { $0.text == text }
    }

    // MARK: - Copy contract (tests target these exact strings)

    /// Pins the player-facing copy the XCUI suite (gyu.22) queries by
    /// accessibility label. If this test fails you changed test-targeted
    /// copy — update EncounterUITests in the same change (repo convention,
    /// same as "Tap to start").
    func testCopyConstantsAreTheExactTestTargetedStrings() {
        XCTAssertEqual(EncounterHUD.Copy.introHeadline, "PAPI PENGUIN VS. THE SNOW MONSTER")
        XCTAssertEqual(EncounterHUD.Copy.introSubline, "Tilt to dodge!")
        XCTAssertEqual(EncounterHUD.Copy.outcomeWin, "DODGED!")
    }

    func testProgressTextFormat() {
        XCTAssertEqual(EncounterHUD.Copy.progressText(resolved: 3, total: 8), "3 / 8")
        XCTAssertEqual(EncounterHUD.Copy.progressText(resolved: 0, total: 12), "0 / 12")
        XCTAssertEqual(EncounterHUD.Copy.progressText(resolved: 12, total: 12), "12 / 12")
    }

    // MARK: - Intro banner

    func testIntroBannerStartsHiddenAndShowsHeadlineAndSubline() {
        let (scene, hud) = makeHUD()

        // Idle: both copy labels exist but are inside a hidden container.
        guard let headline = label(in: scene, text: EncounterHUD.Copy.introHeadline) else {
            return XCTFail("intro headline label missing")
        }
        XCTAssertTrue(headline.parent?.isHidden ?? false,
                      "intro banner must start hidden")

        hud.showIntroBanner()
        XCTAssertFalse(headline.parent?.isHidden ?? true)
        XCTAssertNotNil(label(in: scene, text: EncounterHUD.Copy.introSubline))
    }

    /// Safe-area sanity half that is unit-assertable: the long headline is
    /// scaled so its rendered width always fits inside the scene with a
    /// margin on both sides (the Dynamic Island sits at a screen edge in
    /// landscape; a centered, margined banner clears it).
    func testIntroHeadlineFitsInsideSceneWidthWithMargin() {
        for size in [CGSize(width: 852, height: 393),   // landscape phone
                     CGSize(width: 393, height: 852)] { // narrow worst case
            let scene = SKScene(size: size)
            _ = EncounterHUD(scene: scene, sceneSize: size)
            let headline = label(in: scene, text: EncounterHUD.Copy.introHeadline)!
            let renderedWidth = headline.frame.width  // frame includes setScale
            XCTAssertLessThanOrEqual(renderedWidth, size.width - 2 * 50,
                                     "headline must clear safe margins at \(size)")
            // And it stays centered.
            XCTAssertEqual(headline.position.x, size.width / 2, accuracy: 0.001)
        }
    }

    func testShowIntroBannerTwiceDoesNotDuplicateNodes() {
        let (scene, hud) = makeHUD()
        hud.showIntroBanner()
        let count = allLabels(in: scene).count
        hud.showIntroBanner()
        XCTAssertEqual(allLabels(in: scene).count, count)
    }

    // MARK: - Volley progress

    func testSetProgressRevealsAndFormatsCounter() {
        let (scene, hud) = makeHUD()
        hud.setProgress(resolved: 0, total: 8)
        let progress = label(in: scene, text: "0 / 8")
        XCTAssertNotNil(progress)
        XCTAssertFalse(progress!.isHidden)

        hud.setProgress(resolved: 3, total: 8)
        XCTAssertNil(label(in: scene, text: "0 / 8"))
        XCTAssertNotNil(label(in: scene, text: "3 / 8"))
    }

    func testProgressTicksReuseOneLabel() {
        let (scene, hud) = makeHUD()
        hud.setProgress(resolved: 0, total: 6)
        let count = allLabels(in: scene).count
        for i in 1...6 { hud.setProgress(resolved: i, total: 6) }
        XCTAssertEqual(allLabels(in: scene).count, count)
        XCTAssertNotNil(label(in: scene, text: "6 / 6"))
    }

    // MARK: - Outcome banner

    func testShowOutcomeBannerAddsWinCopy() {
        let (scene, hud) = makeHUD()
        hud.showOutcomeBanner()
        XCTAssertNotNil(label(in: scene, text: EncounterHUD.Copy.outcomeWin))
    }

    func testShowOutcomeBannerTwiceKeepsOneBanner() {
        let (scene, hud) = makeHUD()
        hud.showOutcomeBanner()
        hud.showOutcomeBanner()
        let banners = allLabels(in: scene).filter { $0.text == EncounterHUD.Copy.outcomeWin }
        XCTAssertEqual(banners.count, 1)
    }

    // MARK: - Reset

    func testResetHidesPersistentNodesAndRemovesOutcomeBanner() {
        let (scene, hud) = makeHUD()
        hud.showIntroBanner()
        hud.setProgress(resolved: 2, total: 9)
        hud.showOutcomeBanner()

        hud.reset()

        let headline = label(in: scene, text: EncounterHUD.Copy.introHeadline)!
        XCTAssertTrue(headline.parent!.isHidden)
        XCTAssertNil(label(in: scene, text: "2 / 9"))
        XCTAssertNil(label(in: scene, text: EncounterHUD.Copy.outcomeWin))
    }

    func testRepeatedShowResetCyclesLeakNoNodes() {
        let (scene, hud) = makeHUD()
        hud.showIntroBanner()
        hud.setProgress(resolved: 1, total: 5)
        hud.showOutcomeBanner()
        hud.reset()
        let baseline = allLabels(in: scene).count
        for i in 0..<10 {
            hud.showIntroBanner()
            hud.setProgress(resolved: i, total: 5)
            hud.showOutcomeBanner()
            hud.reset()
        }
        XCTAssertEqual(allLabels(in: scene).count, baseline)
    }

    // MARK: - HUDController.setEncounterMode

    private func makeNormalHUD() -> (scene: SKScene, hud: HUDController) {
        let scene = SKScene(size: CGSize(width: 852, height: 393))
        let hud = HUDController(scene: scene, sceneSize: scene.size, initialBest: 7)
        return (scene, hud)
    }

    /// Acceptance: score/best (and combo) hide during the encounter while
    /// every heart sprite stays visible.
    func testEncounterModeHidesScoreBestComboAndKeepsHearts() {
        let (scene, hud) = makeNormalHUD()
        hud.setEncounterMode(true)
        XCTAssertTrue(hud.isEncounterMode)

        // HUDController's only direct-label children are score, combo, best.
        let labels = scene.children.compactMap { $0 as? SKLabelNode }
        XCTAssertEqual(labels.count, 3)
        for label in labels {
            XCTAssertTrue(label.isHidden, "'\(label.text ?? "")' must hide in encounter mode")
        }

        let hearts = scene.children.compactMap { $0 as? SKSpriteNode }
        XCTAssertEqual(hearts.count, Tuning.Penguin.maxHealth)
        for heart in hearts {
            XCTAssertFalse(heart.isHidden, "hearts must stay visible in encounter mode")
        }
    }

    func testEncounterModeRestoresScoreAndBest() {
        let (scene, hud) = makeNormalHUD()
        hud.setEncounterMode(true)
        // Score keeps updating while hidden, so restore needs no re-push.
        hud.setScore(123)
        hud.setEncounterMode(false)
        XCTAssertFalse(hud.isEncounterMode)

        let score = scene.children
            .compactMap { $0 as? SKLabelNode }
            .first { $0.text == "123" }
        XCTAssertNotNil(score)
        XCTAssertFalse(score!.isHidden)
        let best = scene.children
            .compactMap { $0 as? SKLabelNode }
            .first { $0.text == "Best: 7" }
        XCTAssertNotNil(best)
        XCTAssertFalse(best!.isHidden)
    }

    func testEncounterModeIsIdempotent() {
        let (scene, hud) = makeNormalHUD()
        hud.setEncounterMode(true)
        hud.setEncounterMode(true)
        hud.setEncounterMode(false)
        hud.setEncounterMode(false)
        let labels = scene.children.compactMap { $0 as? SKLabelNode }
        for label in labels { XCTAssertFalse(label.isHidden) }
    }
}
