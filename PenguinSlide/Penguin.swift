//
//  Penguin.swift
//  PenguinSlide
//
//  The player's penguin: visual sprite, physics body, and per-frame
//  motion/lean logic driven by tilt input. Manually positioned each
//  frame — no SKActions touch the sprite during gameplay, since those
//  would race with our position writes and produce visible jitter.
//

import SpriteKit

final class Penguin {

    let node: SKSpriteNode
    private(set) var vx: CGFloat = 0
    private(set) var hp: Int = Tuning.Penguin.maxHealth

    /// Called whenever `hp` changes (hit accepted, or `reset()`). GameScene
    /// wires this to the HUD's heart row so the UI stays in sync without
    /// the penguin knowing about the HUD.
    var onHealthChanged: ((Int) -> Void)?

    private let baseY: CGFloat
    private let leftBound: CGFloat
    private let rightBound: CGFloat

    private var bobPhase: TimeInterval = 0
    private var leanVelocity: CGFloat = 0
    /// Local clock used to gate i-frames and drive the flicker animation.
    /// Independent of GameScene's clock so the penguin's hit logic stays
    /// self-contained.
    private var elapsed: TimeInterval = 0
    private var invulnerableUntil: TimeInterval = 0
    /// Cyan halo parented to the body sprite. Visible only during
    /// i-frames; pulsed via SKAction so the player reads "protected"
    /// distinctly from the red damage flash.
    private let shieldRing: SKShapeNode
    /// Tracks whether the previous frame was inside i-frames, so we can
    /// fire the show/hide cloak transitions exactly once.
    private var wasInvulnerable: Bool = false

    /// Currently-playing sprite-sheet animation. `setState` is the only
    /// path that swaps this — read-only everywhere else.
    private var animState: PenguinAnimState = .idle
    /// One-shot animations (hurt / victory) latch the state for their
    /// natural duration so a player still holding tilt mid-recoil doesn't
    /// snap the sprite back to slide before the recoil reads. Sentinel
    /// `0` means "no one-shot active."
    private var oneShotUntil: TimeInterval = 0

    /// Builds the sprite + physics body and parents it to the given scene.
    /// `leftBound` / `rightBound` are the inside edges of the ice strip
    /// the penguin is clamped to.
    init(scene: SKScene, baseY: CGFloat, leftBound: CGFloat, rightBound: CGFloat) {
        // Initial texture is the first frame of the idle loop so there's
        // no single-frame flicker between sprite creation and the first
        // `update()` tick (which is where `setState` runs).
        let body = SKSpriteNode(texture: PenguinAnimations.idleFrames[0],
                                size: CGSize(width: 70, height: 84))
        body.position = CGPoint(x: (leftBound + rightBound) / 2, y: baseY)
        body.zPosition = 10

        // Hitbox is intentionally positioned high on the sprite (offset y=14)
        // so it extends *above* the kinematic landing line iceTopY. Without
        // this, falling icicles' physics bodies are removed by the landing
        // check before they can overlap the penguin's contact region.
        let pb = SKPhysicsBody(circleOfRadius: body.size.width * Tuning.Penguin.collisionRadiusFraction,
                               center: CGPoint(x: 0, y: 14))
        // Dynamic body for reliable contact tests, but driven entirely by
        // manual position writes. We zero velocity each frame so any stray
        // impulses can't accumulate into drift / jitter. Knockback is
        // applied to `vx` directly (see `tryTakeHit`) — collisionBitMask=0
        // prevents physics-driven displacement from fighting that.
        pb.isDynamic = true
        pb.affectedByGravity = false
        pb.allowsRotation = false
        pb.linearDamping = 0
        pb.friction = 0
        pb.restitution = 0
        pb.mass = Tuning.Penguin.massKg
        pb.categoryBitMask = Category.penguin
        pb.contactTestBitMask = Category.icicle
        pb.collisionBitMask = 0
        body.physicsBody = pb

        // Shield ring: parented to the body so it inherits position, lean,
        // and bob without extra bookkeeping. Centred on the hitbox (y=14)
        // rather than the sprite centre so the halo wraps the actual
        // damage zone. Additive blend gives it a soft "energy" feel
        // against the icy background.
        let ringRadius = body.size.width * Tuning.Penguin.collisionRadiusFraction + 6
        let ring = SKShapeNode(circleOfRadius: ringRadius)
        ring.strokeColor = Tuning.Penguin.shieldRingColor
        ring.lineWidth = Tuning.Penguin.shieldRingLineWidth
        ring.fillColor = .clear
        ring.alpha = 0
        ring.zPosition = -0.1
        ring.position = CGPoint(x: 0, y: 14)
        ring.blendMode = .add
        body.addChild(ring)

        scene.addChild(body)

        self.node = body
        self.shieldRing = ring
        self.baseY = baseY
        self.leftBound = leftBound
        self.rightBound = rightBound

        startAnimation(for: .idle)
    }

    /// Per-frame tick. `tilt` is the input value in [-1, 1] (0 = no input).
    func update(dt: TimeInterval, tilt: CGFloat) {
        elapsed += dt

        // Ice-feel: tilt sets a target velocity, actual velocity glides toward
        // it. Exponential approach so dt-independent — same feel at any frame rate.
        // Curve preserves sign but rewards aggressive tilts non-linearly.
        let curvedTilt = (tilt < 0 ? -1 : 1) * pow(abs(tilt), Tuning.Penguin.tiltCurve)
        let targetVx = curvedTilt * Tuning.Penguin.maxSpeed
        // Asymmetric friction: snappy when pressing, glidey when released.
        let rate: CGFloat = (tilt == 0) ? Tuning.Penguin.iceDecayRate : Tuning.Penguin.tiltResponseRate
        let alpha = 1 - exp(-rate * CGFloat(dt))
        vx += (targetVx - vx) * alpha

        let halfW = node.size.width * 0.42
        let minX = leftBound + halfW
        let maxX = rightBound - halfW
        var newX = node.position.x + vx * CGFloat(dt)
        if newX < minX { newX = minX; vx = 0 }
        if newX > maxX { newX = maxX; vx = 0 }

        // Bob is computed here instead of via SKAction.moveBy — running the
        // action concurrently would race with this position write.
        bobPhase += dt
        let bobY = sin(bobPhase * 5.2) * 3.0
        node.position = CGPoint(x: newX, y: baseY + bobY)
        node.physicsBody?.velocity = .zero

        // Spring-damped lean: target tracks velocity, but a critically-tuned
        // spring produces a brief overshoot when the penguin reverses direction
        // — much more "physical" than a linear lerp. Standard form:
        //     a = ω₀²·error − 2·ω₀·ζ·v
        // where ω₀ = sqrt(stiffness) and ζ is the damping ratio. Explicit
        // Euler is stable here because stiffness * dt² ≪ 1 at any sane fps.
        let leanTarget = -(vx / Tuning.Penguin.maxSpeed) * Tuning.Penguin.leanMaxAngle
        let leanError = leanTarget - node.zRotation
        let leanOmega = sqrt(Tuning.Penguin.leanStiffness)
        let leanAccel = Tuning.Penguin.leanStiffness * leanError
            - 2 * leanOmega * Tuning.Penguin.leanDampingRatio * leanVelocity
        leanVelocity += leanAccel * CGFloat(dt)
        node.zRotation += leanVelocity * CGFloat(dt)

        // Sprite-sheet animation state. Hurt / victory latch for their
        // natural duration (`oneShotUntil`) so a player still holding tilt
        // can't snap the recoil back to slide before it reads. Otherwise:
        // |vx| under the threshold = idle, faster = slide.
        let desiredState: PenguinAnimState
        if elapsed < oneShotUntil {
            desiredState = animState   // keep current one-shot running
        } else if abs(vx) < Tuning.Penguin.idleSlideThresholdPtPerSec {
            desiredState = .idle
        } else {
            desiredState = .slide
        }
        if desiredState != animState {
            startAnimation(for: desiredState)
        }

        // I-frame visuals: a softer alpha pulse on the body (so the
        // penguin stays readable under pressure) plus a cyan shield ring
        // that fires on the rising edge and fades on the falling edge.
        // The ring is the primary "protected" tell; the alpha pulse is a
        // secondary cue for accessibility / motion-sensitive readouts.
        let isInvulnerable = elapsed < invulnerableUntil
        if isInvulnerable {
            if !wasInvulnerable { showShieldRing() }
            let lit = sin(elapsed * 2 * .pi * TimeInterval(Tuning.Penguin.iFrameFlashHz)) > 0
            node.alpha = lit ? 1.0 : Tuning.Penguin.iFrameDimAlpha
        } else {
            if wasInvulnerable { hideShieldRing() }
            if node.alpha != 1.0 && node.action(forKey: "death") == nil {
                node.alpha = 1.0
            }
        }
        wasInvulnerable = isInvulnerable
    }

    /// `true` if HP is still positive. GameScene checks this after every
    /// accepted hit to decide whether to trigger game over.
    func isAlive() -> Bool { hp > 0 }

    /// Attempt to land a hit on the penguin. Returns `true` if HP was
    /// decremented, `false` if the hit was absorbed by active i-frames.
    /// The icicle still recoils visually either way — the caller decides
    /// how loud the FX get based on the return value.
    func tryTakeHit(from impactX: CGFloat) -> Bool {
        if elapsed < invulnerableUntil { return false }
        hp = max(0, hp - 1)
        // Arm i-frames only if the penguin survives. Skipping this on the
        // killing blow means the shield-ring cloak never appears on the
        // fatal hit — death feedback gets to read uncontested.
        if hp > 0 {
            invulnerableUntil = elapsed + Tuning.Penguin.iFrameDuration
        }
        // Pushed *away* from impact: if penguin is to the right of impact,
        // shove further right (positive vx).
        let dir: CGFloat = node.position.x >= impactX ? 1 : -1
        vx += dir * Tuning.Penguin.maxSpeed * Tuning.Penguin.knockbackImpulseScale
        triggerHurtAnimation()
        startAnimation(for: .hurt)
        onHealthChanged?(hp)
        return true
    }

    /// Play the victory cheer (10-frame one-shot, ~1.25 s at 8 fps). The
    /// animation layers on top of the procedural lean/bob the same way
    /// `hurt` does. Intended for high-score moments — `update()` will
    /// fall back to idle/slide once `oneShotUntil` elapses. Safe to call
    /// at any time; the call is ignored while not alive (so it can't
    /// override the death pose).
    func playVictory() {
        guard isAlive() else { return }
        startAnimation(for: .victory)
    }

    /// Brief red tint + squash on every hit. Split into two keyed actions
    /// so the death animation can cancel the squash (which fights the
    /// death scale-down) without cancelling the red flash — we want the
    /// flash to play even on the killing blow.
    private func triggerHurtAnimation() {
        node.removeAction(forKey: "hurtFlash")
        let flashIn = SKAction.run { [weak self] in
            self?.node.color = .red
            self?.node.colorBlendFactor = 0.7
        }
        let flashOut = SKAction.customAction(withDuration: 0.25) { node, t in
            (node as? SKSpriteNode)?.colorBlendFactor = 0.7 * (1 - t / 0.25)
        }
        let clear = SKAction.run { [weak self] in
            self?.node.colorBlendFactor = 0.0
        }
        node.run(.sequence([flashIn, flashOut, clear]), withKey: "hurtFlash")

        node.removeAction(forKey: "hurtSquash")
        node.run(.sequence([
            .scale(to: 0.92, duration: 0.05),
            .wait(forDuration: 0.05),
            .scale(to: 1.0, duration: 0.12)
        ]), withKey: "hurtSquash")
    }

    /// Swap to a different sprite-sheet animation. Keyed `"frames"` so
    /// the next `startAnimation` call cleanly cancels the previous one
    /// without touching the procedural channels (lean / bob / shield /
    /// hurt squash all live on the node or its children under different
    /// keys). One-shots arm `oneShotUntil` so the player can't snap out
    /// of a hurt/victory mid-pose by tilting.
    private func startAnimation(for state: PenguinAnimState) {
        animState = state
        node.removeAction(forKey: "frames")
        let frames = PenguinAnimations.frames(for: state)
        let perFrame = 1.0 / Tuning.Penguin.animationFps
        let animate = SKAction.animate(with: frames,
                                       timePerFrame: perFrame,
                                       resize: false,
                                       restore: false)
        if PenguinAnimations.loops(state) {
            oneShotUntil = 0
            node.run(.repeatForever(animate), withKey: "frames")
        } else {
            oneShotUntil = elapsed + perFrame * Double(frames.count)
            node.run(animate, withKey: "frames")
        }
    }

    /// Pulse the shield ring while i-frames are active. Fades in from
    /// alpha 0 and breathes between 0.4 and 0.8 with a matching scale
    /// pulse so the player can read "protected" without the body sprite
    /// being obscured.
    private func showShieldRing() {
        shieldRing.removeAction(forKey: "cloak")
        shieldRing.setScale(1.0)
        shieldRing.alpha = 0.4
        let period = Tuning.Penguin.shieldRingPulsePeriod
        let up = SKAction.group([
            .scale(to: 1.15, duration: period),
            .fadeAlpha(to: 0.8, duration: period)
        ])
        let down = SKAction.group([
            .scale(to: 1.0, duration: period),
            .fadeAlpha(to: 0.4, duration: period)
        ])
        shieldRing.run(.repeatForever(.sequence([up, down])), withKey: "cloak")
    }

    /// Stop the pulse and quickly fade the ring out so the i-frame end is
    /// crisp without a hard pop.
    private func hideShieldRing() {
        shieldRing.removeAction(forKey: "cloak")
        shieldRing.run(.sequence([
            .fadeAlpha(to: 0, duration: 0.15),
            .scale(to: 1.0, duration: 0)
        ]))
    }

    func reset() {
        node.removeAllActions()
        // `removeAllActions` does not cascade to children — clear the
        // ring's pulse explicitly and snap its alpha/scale back so a
        // restarted round starts with a clean cloak state.
        shieldRing.removeAllActions()
        shieldRing.alpha = 0
        shieldRing.setScale(1)
        wasInvulnerable = false
        node.position = CGPoint(x: (leftBound + rightBound) / 2, y: baseY)
        node.alpha = 1
        node.setScale(1)
        node.zRotation = 0
        node.colorBlendFactor = 0
        node.physicsBody?.velocity = .zero
        vx = 0
        bobPhase = 0
        leanVelocity = 0
        elapsed = 0
        invulnerableUntil = 0
        hp = Tuning.Penguin.maxHealth
        // `removeAllActions` killed the "frames" loop too — restart it so
        // a freshly-reset penguin is animated from frame zero, not stuck
        // on whichever frame the previous round ended on.
        oneShotUntil = 0
        animState = .idle
        startAnimation(for: .idle)
        onHealthChanged?(hp)
    }

    /// Play the death feedback (called only when HP reaches 0). Cancels
    /// the squash (which fights the death scale-down) but deliberately
    /// leaves "hurtFlash" running — that's the red-on-killing-blow tell.
    /// Also hides the shield ring instantly, since i-frames are no
    /// longer armed for the fatal hit and any stale cloak from a prior
    /// hit (e.g. force-game-over debug path) should disappear cleanly.
    func triggerDeathAnimation() {
        node.removeAction(forKey: "hurtSquash")
        // Freeze the sprite-sheet loop so the death pose isn't undercut
        // by a flipper still waving or a blink still cycling. GameScene
        // stops calling `update()` after game-over, so nothing will
        // restart "frames" until `reset()`.
        node.removeAction(forKey: "frames")
        shieldRing.removeAction(forKey: "cloak")
        shieldRing.alpha = 0
        node.run(.sequence([
            .group([
                .scale(to: 0.9, duration: 0.1),
                .fadeAlpha(to: 0.6, duration: 0.1)
            ]),
            .rotate(byAngle: .pi / 6, duration: 0.2)
        ]), withKey: "death")
    }
}
