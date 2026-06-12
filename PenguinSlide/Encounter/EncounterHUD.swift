//
//  EncounterHUD.swift
//  PenguinSlide
//
//  Encounter-mode presentation (penguinslide-gyu.20): intro banner, volley
//  progress counter, and the win outcome banner. Pure presentation in the
//  HUDController mold — GameScene pushes state via showIntroBanner /
//  setProgress / showOutcomeBanner, this controller reads nothing back.
//
//  Parenting contract: every node here is a DIRECT SCENE CHILD — never under
//  `encounterRoot` (hidden/paused outside the encounter) or `worldRoot`
//  (hidden during it) — so banners keep animating while the intro/outro
//  choreography swaps the roots underneath them.
//
//  Dodge "+N" floats deliberately do NOT live here: GameScene routes them
//  through the existing `HUDController.floatBonus` (one float mechanism,
//  not two).
//
//  Everything player-facing is an SKLabelNode: SpriteKit only surfaces
//  label nodes to XCUITest's accessibility traversal (CLAUDE.md), and the
//  label's text becomes the accessibility label tests match.
//

import SpriteKit
import UIKit

final class EncounterHUD {

    // MARK: - Copy (the single constants block)

    /// All player-facing encounter copy. Tests target these EXACT strings
    /// via XCUITest accessibility queries (`app.otherElements["DODGED!"]`
    /// etc.) — changing any of them means updating EncounterUITests in the
    /// same change. Repo convention, same as "Tap to start" (CLAUDE.md).
    enum Copy {
        /// Intro banner headline (Papi Penguin branding, plan R3).
        static let introHeadline = "PAPI PENGUIN VS. THE SNOW MONSTER"
        /// Intro banner subline — the one-line how-to.
        static let introSubline = "Tilt to dodge!"
        /// Win outcome banner, shown during the outro. Loss has no
        /// encounter-specific banner: it goes through the standard
        /// GameOverView page.
        static let outcomeWin = "DODGED!"
        /// Volley progress format, e.g. "3 / 8" — resolved balls (hit or
        /// dodged) over the volley's planned total. Tests match it with
        /// a `\d+ / \d+` predicate, so the separator is part of the
        /// contract too.
        static func progressText(resolved: Int, total: Int) -> String {
            "\(resolved) / \(total)"
        }
    }

    // MARK: - Layout constants

    /// Above the normal HUD (zPosition 50) and the gameplay floats (60),
    /// below the start prompt (100) and death flash (200).
    private static let zPosition: CGFloat = 80
    /// Side margin the intro headline must fit inside, so the banner is
    /// never clipped by the Dynamic Island / notch in either landscape
    /// orientation (the island sits at a screen EDGE; a centered, margined
    /// banner clears it in both).
    private static let safeMargin: CGFloat = 60

    private weak var scene: SKScene?
    private let sceneSize: CGSize

    /// Intro banner container (headline + subline), persistent + hidden
    /// when idle so repeated encounters never duplicate nodes.
    private let introBanner: SKNode
    private let introHeadline: SKLabelNode
    /// Volley progress counter, persistent + hidden when idle. Lives in
    /// the score label's slot — the score is hidden for the whole
    /// encounter (HUDController.setEncounterMode), so the slot is free
    /// and the eye already looks there for "how much is left".
    private let progressLabel: SKLabelNode
    /// Live outcome banner, if one is playing. Transient + self-removing;
    /// tracked only so `reset()` (restart mid-outro) can kill it early.
    private weak var outcomeBanner: SKLabelNode?

    /// Same fallback as HUDController.safeFont: a missing font face must
    /// degrade to the system font, not silently to Helvetica.
    private static func safeFont(named name: String) -> String {
        UIFont(name: name, size: 12) != nil ? name : UIFont.systemFont(ofSize: 12).fontName
    }

    init(scene: SKScene, sceneSize: CGSize) {
        self.scene = scene
        self.sceneSize = sceneSize

        let banner = SKNode()
        banner.zPosition = Self.zPosition
        banner.isHidden = true
        banner.alpha = 0

        let headline = SKLabelNode(fontNamed: Self.safeFont(named: "AvenirNext-Heavy"))
        headline.text = Copy.introHeadline
        headline.fontSize = 34
        headline.fontColor = .white
        headline.horizontalAlignmentMode = .center
        headline.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height * 0.70)
        // Scale-to-fit: the headline is long, and the scene can be the
        // narrow (portrait-ish test) size — shrink so it always clears the
        // safe margins instead of clipping at the edges.
        let maxWidth = sceneSize.width - Self.safeMargin * 2
        if headline.frame.width > maxWidth {
            headline.setScale(maxWidth / headline.frame.width)
        }
        banner.addChild(headline)
        self.introHeadline = headline

        let subline = SKLabelNode(fontNamed: Self.safeFont(named: "AvenirNext-Medium"))
        subline.text = Copy.introSubline
        subline.fontSize = 22
        subline.fontColor = UIColor(white: 1, alpha: 0.92)
        subline.horizontalAlignmentMode = .center
        subline.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height * 0.70 - 40)
        banner.addChild(subline)

        scene.addChild(banner)
        self.introBanner = banner

        let progress = SKLabelNode(fontNamed: Self.safeFont(named: "AvenirNext-Bold"))
        progress.fontSize = 44
        progress.fontColor = UIColor(white: 1.0, alpha: 0.9)
        progress.horizontalAlignmentMode = .center
        progress.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height - 110)
        progress.zPosition = Self.zPosition
        progress.isHidden = true
        progress.text = ""
        scene.addChild(progress)
        self.progressLabel = progress
    }

    // MARK: - Intro banner

    /// Slide/fade the intro banner in. Idempotent per entry: re-showing
    /// restarts the animation on the same persistent nodes.
    func showIntroBanner() {
        introBanner.removeAction(forKey: "introFx")
        introBanner.isHidden = false
        introBanner.alpha = 0
        introBanner.position = CGPoint(x: 0, y: 24)
        let slideIn = SKAction.group([
            .fadeIn(withDuration: 0.35),
            .move(to: .zero, duration: 0.35)
        ])
        slideIn.timingMode = .easeOut
        introBanner.run(slideIn, withKey: "introFx")
    }

    /// Fade/slide the intro banner out (encounter start). Safe to call
    /// when already hidden.
    func hideIntroBanner() {
        guard !introBanner.isHidden else { return }
        introBanner.removeAction(forKey: "introFx")
        let slideOut = SKAction.group([
            .fadeOut(withDuration: 0.3),
            .move(to: CGPoint(x: 0, y: 24), duration: 0.3)
        ])
        slideOut.timingMode = .easeIn
        introBanner.run(.sequence([slideOut, .hide()]), withKey: "introFx")
    }

    // MARK: - Volley progress

    /// Push the resolved-ball count ("3 / 8"). First push of an encounter
    /// reveals the label; each subsequent tick pulses it so the change
    /// reads as "one resolved" rather than a silent text swap.
    func setProgress(resolved: Int, total: Int) {
        let text = Copy.progressText(resolved: resolved, total: total)
        let changed = progressLabel.text != text
        progressLabel.text = text
        if progressLabel.isHidden {
            progressLabel.isHidden = false
            progressLabel.alpha = 0
            progressLabel.removeAction(forKey: "progressFx")
            progressLabel.run(.fadeIn(withDuration: 0.25), withKey: "progressFx")
        } else if changed && resolved > 0 {
            progressLabel.removeAction(forKey: "progressFx")
            progressLabel.run(.sequence([
                .scale(to: 1.2, duration: 0.08),
                .scale(to: 1.0, duration: 0.12)
            ]), withKey: "progressFx")
        }
    }

    /// Fade the progress counter out (outro / teardown). Safe when hidden.
    func hideProgress() {
        guard !progressLabel.isHidden else { return }
        progressLabel.removeAction(forKey: "progressFx")
        progressLabel.run(.sequence([.fadeOut(withDuration: 0.25), .hide()]),
                          withKey: "progressFx")
    }

    // MARK: - Outcome banner

    /// "DODGED!" pop on a survived volley, played during the outro. The
    /// node is transient and self-removing — its lifetime (~1.5 s) may
    /// overlap the first beats of the restored normal world, which is the
    /// point: the celebration carries across the crossfade. Loss shows no
    /// encounter banner (standard GameOverView path).
    func showOutcomeBanner() {
        guard let scene else { return }
        outcomeBanner?.removeFromParent()

        let label = SKLabelNode(fontNamed: Self.safeFont(named: "AvenirNext-Heavy"))
        label.text = Copy.outcomeWin
        label.fontSize = 48
        label.fontColor = UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1)  // HUD combo gold
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height * 0.58)
        label.zPosition = Self.zPosition
        label.alpha = 0
        label.setScale(0.6)
        scene.addChild(label)
        outcomeBanner = label

        label.run(.sequence([
            .group([.fadeIn(withDuration: 0.15), .scale(to: 1.15, duration: 0.15)]),
            .scale(to: 1.0, duration: 0.12),
            .wait(forDuration: 0.85),
            .fadeOut(withDuration: 0.35),
            .removeFromParent()
        ]))
    }

    // MARK: - Lifecycle

    /// Immediate teardown to the idle state — restart()'s path, so a
    /// "Play Again" mid-encounter (or mid-outro) never leaves a frozen
    /// banner over the fresh round. Persistent nodes hide; the transient
    /// outcome banner is removed outright.
    func reset() {
        introBanner.removeAction(forKey: "introFx")
        introBanner.isHidden = true
        introBanner.alpha = 0
        introBanner.position = .zero

        progressLabel.removeAction(forKey: "progressFx")
        progressLabel.isHidden = true
        progressLabel.alpha = 1
        progressLabel.setScale(1.0)
        progressLabel.text = ""

        outcomeBanner?.removeFromParent()
        outcomeBanner = nil
    }
}
