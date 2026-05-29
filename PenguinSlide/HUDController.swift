//
//  HUDController.swift
//  PenguinSlide
//
//  Score, best, hearts, start prompt, and death flash. Pure presentation —
//  doesn't read game state or drive transitions. GameScene calls the
//  setScore / setBest / setHealth / showStartPrompt / triggerDeathFlash APIs
//  to keep the UI in sync. The game-over page itself is SwiftUI
//  (GameOverView), presented by ContentView off GameScene.onGameOver.
//

import SpriteKit
import UIKit

final class HUDController {

    private weak var scene: SKScene?
    private let sceneSize: CGSize

    private let scoreLabel: SKLabelNode
    private let bestLabel: SKLabelNode

    private let heartTexture: SKTexture
    private var hearts: [SKSpriteNode] = []

    /// Resolve a font name, falling back to the system font if the requested
    /// face isn't available on this iOS version. Without this, removing or
    /// renaming a built-in family causes every label to silently render in
    /// the SpriteKit default (Helvetica) — no warning, just a different look.
    private static func safeFont(named name: String) -> String {
        UIFont(name: name, size: 12) != nil ? name : UIFont.systemFont(ofSize: 12).fontName
    }

    init(scene: SKScene, sceneSize: CGSize, initialBest: Int) {
        self.scene = scene
        self.sceneSize = sceneSize

        let s = SKLabelNode(fontNamed: Self.safeFont(named: "AvenirNext-Bold"))
        s.fontSize = 56
        s.fontColor = UIColor(white: 1.0, alpha: 0.85)
        s.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height - 110)
        s.zPosition = 50
        s.text = "0"
        s.horizontalAlignmentMode = .center
        scene.addChild(s)
        self.scoreLabel = s

        let b = SKLabelNode(fontNamed: Self.safeFont(named: "AvenirNext-Medium"))
        b.fontSize = 18
        b.fontColor = UIColor(white: 0.2, alpha: 0.5)
        b.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height - 140)
        b.zPosition = 50
        b.text = "Best: \(initialBest)"
        scene.addChild(b)
        self.bestLabel = b

        self.heartTexture = HUDController.buildHeartTexture()
        for i in 0..<Tuning.Penguin.maxHealth {
            let h = SKSpriteNode(texture: heartTexture)
            h.position = CGPoint(x: 32 + CGFloat(i) * 36, y: sceneSize.height - 80)
            h.zPosition = 50
            scene.addChild(h)
            hearts.append(h)
        }
    }

    func setScore(_ value: Int) { scoreLabel.text = "\(value)" }
    func setBest(_ value: Int)  { bestLabel.text = "Best: \(value)" }

    /// Sync heart row to `hp`. Hearts that just dimmed (alpha drops) get a
    /// quick scale-pulse first so the change reads as "I just took a hit"
    /// rather than a silent fade.
    func setHealth(_ hp: Int) {
        for (i, heart) in hearts.enumerated() {
            let alive = i < hp
            let targetAlpha: CGFloat = alive ? 1.0 : 0.18
            if heart.alpha > targetAlpha {
                heart.removeAction(forKey: "heartFx")
                heart.run(.sequence([
                    .scale(to: 1.3, duration: 0.08),
                    .group([
                        .scale(to: 1.0, duration: 0.15),
                        .fadeAlpha(to: targetAlpha, duration: 0.15)
                    ])
                ]), withKey: "heartFx")
            } else {
                heart.removeAction(forKey: "heartFx")
                heart.alpha = targetAlpha
                heart.setScale(1.0)
            }
        }
    }

    /// One-time procedural heart bitmap. Two arcs + a V — cheap and reads
    /// as a heart at HUD scale without an asset file.
    private static func buildHeartTexture() -> SKTexture {
        let size = CGSize(width: 24, height: 22)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { _ in
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 12, y: 22))
            p.addCurve(to: CGPoint(x: 0, y: 8),
                       controlPoint1: CGPoint(x: 12, y: 18),
                       controlPoint2: CGPoint(x: 0, y: 14))
            p.addArc(withCenter: CGPoint(x: 6, y: 6),  radius: 6,
                     startAngle: .pi, endAngle: 0, clockwise: true)
            p.addArc(withCenter: CGPoint(x: 18, y: 6), radius: 6,
                     startAngle: .pi, endAngle: 0, clockwise: true)
            p.addCurve(to: CGPoint(x: 12, y: 22),
                       controlPoint1: CGPoint(x: 24, y: 14),
                       controlPoint2: CGPoint(x: 12, y: 18))
            p.close()
            UIColor(red: 0.95, green: 0.25, blue: 0.35, alpha: 1).setFill()
            p.fill()
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        return tex
    }

    // MARK: - Start prompt

    func showStartPrompt() {
        guard let scene else { return }
        let dim = SKShapeNode(rect: CGRect(origin: .zero, size: sceneSize))
        dim.fillColor = UIColor(white: 0, alpha: 0.18)
        dim.strokeColor = .clear
        dim.zPosition = 100
        dim.name = "startPrompt"
        scene.addChild(dim)

        let title = SKLabelNode(fontNamed: Self.safeFont(named: "AvenirNext-Heavy"))
        title.text = "PENGUIN SLIDE"
        title.fontSize = 42
        title.fontColor = .white
        title.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2 + 40)
        title.zPosition = 101
        dim.addChild(title)

        let sub = SKLabelNode(fontNamed: Self.safeFont(named: "AvenirNext-Medium"))
        sub.text = "Tilt your phone to slide"
        sub.fontSize = 20
        sub.fontColor = UIColor(white: 1, alpha: 0.9)
        sub.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2 - 6)
        sub.zPosition = 101
        dim.addChild(sub)

        let tap = SKLabelNode(fontNamed: Self.safeFont(named: "AvenirNext-Bold"))
        tap.text = "Tap to start"
        tap.fontSize = 24
        tap.fontColor = .white
        tap.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2 - 50)
        tap.zPosition = 101
        tap.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.4, duration: 0.6),
            .fadeAlpha(to: 1.0, duration: 0.6)
        ])))
        dim.addChild(tap)
    }

    func dismissStartPrompt() {
        scene?.childNode(withName: "startPrompt")?.run(.sequence([
            .fadeOut(withDuration: 0.25),
            .removeFromParent()
        ]))
    }

    // MARK: - Death flash

    func triggerDeathFlash() {
        guard let scene else { return }
        let flash = SKSpriteNode(color: .white, size: sceneSize)
        flash.anchorPoint = .zero
        flash.alpha = 0.6
        flash.zPosition = 200
        scene.addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.35), .removeFromParent()]))
    }
}
