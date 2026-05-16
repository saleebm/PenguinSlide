//
//  GameScene.swift
//  PenguinSlide
//
//  Orchestrator. Builds the static world (sky + ice field) and the three
//  gameplay subsystems (Penguin, IcicleSystem, HUDController), then routes
//  per-frame updates, input, and contact events.
//

import SpriteKit
import CoreMotion
import UIKit
import GameController

final class GameScene: SKScene, SKPhysicsContactDelegate {

    private let motionManager = CMMotionManager()
    private var gameCamera: SKCameraNode!

    private var penguin: Penguin!
    private var icicles: IcicleSystem!
    private var hud: HUDController!

    private var lastUpdateTime: TimeInterval = 0
    private var elapsed: TimeInterval = 0

    // Cached game-over sound. Paired with the existing .error haptic in
    // triggerGameOver(). IcicleSystem owns the shatter and crack sounds.
    private let gameOverSound = SKAction.playSoundFileNamed("game_over.caf",
                                                             waitForCompletion: false)

    // Looping ambient bed. Volume sits well under the SFX so impacts cut
    // through; the node is pause/resume-controlled on app lifecycle so it
    // doesn't keep playing in the background.
    private var bgMusic: SKAudioNode?

    private var score: Int = 0 {
        didSet { hud?.setScore(score) }
    }
    private var isGameOver = false
    private var isStarted = false

    private var iceTopY: CGFloat = 0
    private var iceFloorY: CGFloat = 0
    private var iceLeftX: CGFloat = 0
    private var iceRightX: CGFloat = 0

    // MARK: - Scene lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = .zero
        backgroundColor = .clear
        // Scene-level gravity stays at zero. SKPhysicsBody has no per-body
        // gravity scaling, so IcicleSystem integrates per-node gravity
        // manually via its `FallingBody` entries.
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        // Camera centered on existing scene midpoint, so positions of HUD,
        // ice field, etc. render identically to the no-camera setup. It
        // exists solely so IcicleSystem can shake the viewport on impact.
        let cam = SKCameraNode()
        cam.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(cam)
        camera = cam
        gameCamera = cam

        buildSky()
        buildIceField()

        penguin = Penguin(scene: self,
                          baseY: iceFloorY + 42,
                          leftBound: iceLeftX,
                          rightBound: iceRightX)
        icicles = IcicleSystem(scene: self,
                               camera: cam,
                               penguin: penguin,
                               iceTopY: iceTopY,
                               iceLeftX: iceLeftX,
                               iceRightX: iceRightX,
                               sceneSize: size)
        hud = HUDController(scene: self,
                            sceneSize: size,
                            initialBest: bestScore())
        hud.showStartPrompt()

        let bg = SKAudioNode(fileNamed: "bg_music.caf")
        bg.autoplayLooped = true
        bg.isPositional = false
        bg.run(SKAction.changeVolume(to: 0.18, duration: 0))
        addChild(bg)
        bgMusic = bg

        // Wire heart HUD to penguin HP so the UI stays in sync without
        // GameScene mediating each change. Initial render covers round start.
        penguin.onHealthChanged = { [weak self] hp in self?.hud.setHealth(hp) }
        hud.setHealth(penguin.hp)

        startMotionUpdates()
        observeAppLifecycle()

        #if DEBUG
        installDebugForceGameOver()
        #endif
    }

    override func willMove(from view: SKView) {
        motionManager.stopDeviceMotionUpdates()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - App lifecycle

    private func observeAppLifecycle() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleWillResignActive),
                       name: UIApplication.willResignActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleDidBecomeActive),
                       name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func handleWillResignActive() {
        view?.isPaused = true
        // SKAudioNode runs on the audio engine, not the scene clock, so it
        // keeps playing through view.isPaused. Explicit pause here.
        bgMusic?.run(SKAction.pause())
    }

    @objc private func handleDidBecomeActive() {
        // The dt-skip sentinel in update(_:) treats lastUpdateTime == 0 as
        // "first frame, dt = 0". Without this reset, the first post-resume
        // update sees a multi-second dt (the lock duration), `elapsed`
        // jumps, score balloons, and Penguin/IcicleSystem integrate one
        // giant step. Same sentinel pattern as restart()/start (penguinslide-jj2).
        lastUpdateTime = 0
        view?.isPaused = false
        bgMusic?.run(SKAction.play())
    }

    // MARK: - World construction

    private func buildSky() {
        // Backdrop art has sky + distant mountains baked in.
        let backdrop = SKSpriteNode(texture: SpriteCatalog.texture(for: .skyBackdrop))
        backdrop.anchorPoint = .zero
        backdrop.position = .zero
        backdrop.size = size
        backdrop.zPosition = -100
        addChild(backdrop)
    }

    private func buildIceField() {
        iceTopY = size.height * 0.28
        iceFloorY = iceTopY * 0.55

        let strip = size.width * Tuning.Run.playWidthFraction
        iceLeftX = (size.width - strip) / 2
        iceRightX = iceLeftX + strip

        // Dark water flanking the ice strip — purely visual, but it sells the
        // squeeze and gives players a clear "stay on the ice" read.
        let water = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: iceTopY))
        water.fillColor = UIColor(red: 0.20, green: 0.42, blue: 0.62, alpha: 1)
        water.strokeColor = .clear
        water.zPosition = -11
        addChild(water)

        let iceSize = CGSize(width: strip, height: iceTopY)
        let ice = SKSpriteNode(texture: SpriteCatalog.tiled(.iceTile, size: iceSize),
                               size: iceSize)
        ice.anchorPoint = .zero
        ice.position = CGPoint(x: iceLeftX, y: 0)
        ice.zPosition = -10
        addChild(ice)

        // Top edge of the ice (shoreline highlight).
        let topLine = SKShapeNode(rect: CGRect(x: iceLeftX, y: iceTopY - 2, width: strip, height: 2))
        topLine.fillColor = UIColor(white: 1.0, alpha: 0.9)
        topLine.strokeColor = .clear
        topLine.zPosition = -9
        addChild(topLine)

        // Vertical shore edges so the ice reads as a platform, not a band.
        for x in [iceLeftX, iceRightX - 2] {
            let edge = SKShapeNode(rect: CGRect(x: x, y: 0, width: 2, height: iceTopY))
            edge.fillColor = UIColor(red: 0.55, green: 0.75, blue: 0.88, alpha: 0.8)
            edge.strokeColor = .clear
            edge.zPosition = -9
            addChild(edge)
        }

        for _ in 0..<6 {
            let crack = SKShapeNode()
            let cp = CGMutablePath()
            let sx = CGFloat.random(in: (iceLeftX + 12)...(iceRightX - 12))
            let sy = CGFloat.random(in: 10...(iceTopY - 20))
            cp.move(to: CGPoint(x: sx, y: sy))
            var cx = sx, cy = sy
            for _ in 0..<3 {
                cx += CGFloat.random(in: -25...25)
                cy += CGFloat.random(in: -15...15)
                cp.addLine(to: CGPoint(x: cx, y: cy))
            }
            crack.path = cp
            crack.strokeColor = UIColor(white: 0.55, alpha: 0.25)
            crack.lineWidth = 1
            crack.zPosition = -8
            addChild(crack)
        }
    }

    // MARK: - Motion

    private func startMotionUpdates() {
        // startDeviceMotionUpdates yields fused, low-noise gravity which is
        // better for tilt control than raw gyro/accelerometer.
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates()
    }

    /// Read current tilt: CoreMotion gravity.y for the device, GCKeyboard
    /// fallback for the simulator. Output is in [-1, 1] with a small
    /// dead zone to suppress flat-phone drift.
    private func currentTilt() -> CGFloat {
        var tilt: CGFloat = 0
        if let gravity = motionManager.deviceMotion?.gravity {
            tilt = CGFloat(gravity.y)
            if abs(tilt) < 0.04 { tilt = 0 }
        }
        if tilt == 0, let kb = GCKeyboard.coalesced?.keyboardInput {
            let left  = kb.button(forKeyCode: .leftArrow)?.isPressed  == true || kb.button(forKeyCode: .keyA)?.isPressed == true
            let right = kb.button(forKeyCode: .rightArrow)?.isPressed == true || kb.button(forKeyCode: .keyD)?.isPressed == true
            if left  { tilt = -1 }
            if right { tilt =  1 }
        }
        return max(-1, min(1, tilt))
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        #if DEBUG
        if let t = touches.first,
           nodes(at: t.location(in: self)).contains(where: { $0.name == Self.debugForceGameOverLabel }) {
            // Keep state coherent if the test taps the debug hook before the
            // start prompt is dismissed, so the standard restart-on-tap path
            // still works.
            if !isStarted {
                isStarted = true
                lastUpdateTime = 0
                hud.dismissStartPrompt()
            }
            triggerGameOver()
            return
        }
        #endif

        if !isStarted {
            isStarted = true
            // See restart()'s comment for rationale — keep the frame-time
            // anchor reset symmetric across start and restart transitions.
            lastUpdateTime = 0
            hud.dismissStartPrompt()
            return
        }
        if isGameOver {
            restart()
        }
    }

    // MARK: - Update loop

    /// Per-frame tick.
    ///
    /// IMPORTANT ordering contract: **all per-frame physics work — penguin
    /// movement, spawning, gravity integration, landing checks — must stay
    /// BEHIND the `isStarted/!isGameOver` guard.** `didBegin(_:)` is invoked
    /// from inside SpriteKit's physics step, which runs AFTER `update(_:)`
    /// in the same frame. So on the death frame, this method has already
    /// executed; we rely on the NEXT frame's guard plus `physicsWorld.speed
    /// = 0` (set in `triggerGameOver`) to halt motion. If you move any of
    /// the integration calls outside the guard you'll get one frame of
    /// post-death physics — visible as a teleporting shard.
    override func update(_ currentTime: TimeInterval) {
        let dt: TimeInterval = lastUpdateTime == 0 ? 0 : (currentTime - lastUpdateTime)
        lastUpdateTime = currentTime

        guard isStarted, !isGameOver else { return }

        elapsed += dt

        penguin.update(dt: dt, tilt: currentTilt())
        icicles.update(dt: dt, elapsed: elapsed)

        // Score grows steadily so survival is rewarded even without dodges.
        // Bead penguinslide-y7f will add a close-call bonus on top of this.
        score = Int(elapsed * 10)
    }

    // MARK: - Contact

    func didBegin(_ contact: SKPhysicsContact) {
        let mask = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        guard mask == (Category.penguin | Category.icicle) else { return }
        let icicleBody = contact.bodyA.categoryBitMask == Category.icicle ? contact.bodyA : contact.bodyB
        guard let icicleNode = icicleBody.node as? SKSpriteNode else { return }

        // Hand the contact to the penguin: if i-frames are active, no damage
        // is taken (`accepted = false`) — but the icicle is consumed either
        // way. IcicleSystem owns the recoil + shatter FX, and tunes their
        // volume by `accepted`.
        let accepted = penguin.tryTakeHit(from: icicleNode.position.x)
        icicles.onIcicleHitPenguin(icicle: icicleNode, at: contact.contactPoint, accepted: accepted)

        if !penguin.isAlive() { triggerGameOver() }
    }

    // MARK: - Game over / restart

    private func triggerGameOver() {
        guard !isGameOver else { return }
        isGameOver = true

        let best = bestScore()
        if score > best {
            UserDefaults.standard.set(score, forKey: "best_score")
            // Keep the top-of-screen HUD in sync with the new record; without
            // this, the player sees a stale "Best" until they tap to restart.
            hud.setBest(score)
        }

        penguin.triggerDeathAnimation()
        hud.triggerDeathFlash()

        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.error)
        run(gameOverSound)

        hud.showGameOver(score: score, best: best)

        // Freeze in-flight icicles AND pause shard fade actions per-node.
        // physicsWorld.speed = 0 halts physics-driven motion, but SKActions
        // (the shard fadeOut) run independently — pausing them keeps the
        // world consistently frozen.
        physicsWorld.speed = 0
        icicles.pauseShardActions()
    }

    private func restart() {
        icicles.reset()
        hud.dismissGameOver()

        physicsWorld.speed = 1
        gameCamera.removeAction(forKey: "shake")
        gameCamera.position = CGPoint(x: size.width / 2, y: size.height / 2)

        elapsed = 0
        score = 0
        isGameOver = false
        // Reset the frame-time anchor. The `dt == 0` sentinel branch handles
        // first-frame correctly; without this, a future refactor that moves
        // the `lastUpdateTime = currentTime` write inside the isStarted guard
        // would compute a huge dt on the first post-restart frame and teleport
        // the penguin.
        lastUpdateTime = 0

        penguin.reset()
        hud.setBest(bestScore())
    }

    private func bestScore() -> Int {
        UserDefaults.standard.integer(forKey: "best_score")
    }

    #if DEBUG
    // MARK: - Debug hooks

    // Mechanism: hidden accessibility node — only option XCUITest can drive mid-round without touching ContentView.
    private static let debugForceGameOverLabel = "debugForceGameOver"

    private func installDebugForceGameOver() {
        // Must be an SKLabelNode — SpriteKit's automatic accessibility
        // traversal only surfaces SKLabelNodes to XCUITest; SKSpriteNode
        // with isAccessibilityElement set is silently pruned. The label's
        // text becomes the accessibility label that XCUITest matches.
        let node = SKLabelNode(text: Self.debugForceGameOverLabel)
        node.name = Self.debugForceGameOverLabel
        node.fontSize = 10
        node.fontColor = UIColor(red: 1, green: 0, blue: 0, alpha: 0.55)
        node.horizontalAlignmentMode = .left
        node.verticalAlignmentMode = .top
        node.position = CGPoint(x: 4, y: size.height - 4)
        node.zPosition = 10_000
        addChild(node)
    }
    #endif
}
