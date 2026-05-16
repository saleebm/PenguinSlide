//
//  IcicleSystem.swift
//  PenguinSlide
//
//  Owns the icicle lifecycle: spawn cadence, warning telegraphs, per-icicle
//  gravity, landing detection, shatter shards, and the camera shake that
//  pairs with impact severity. Owns the puff and shard textures.
//

import SpriteKit
import UIKit

final class IcicleSystem {

    private weak var scene: SKScene?
    private weak var camera: SKCameraNode?
    private weak var penguin: Penguin?

    /// Cosmetic top of the ice strip — back/horizon edge in the 2D
    /// side-view. Kept only as a reference for warning-phase placement
    /// and for documentation; gameplay lands at `iceLandingY` instead.
    private let iceTopY: CGFloat
    /// Plane the penguin's feet sit on. Icicles fall down through the
    /// scene until their bottom reaches this y, so the shatter visually
    /// appears on the same surface the penguin is sliding on rather than
    /// at the back of the strip. See plan: the-ice-looks-like-ticklish-reddy.
    private let iceLandingY: CGFloat
    private let iceLeftX: CGFloat
    private let iceRightX: CGFloat
    private let sceneSize: CGSize

    private var timeSinceLastSpawn: TimeInterval = 0
    private var nextSpawnInterval: TimeInterval = Tuning.Icicle.spawnIntervalStart

    /// Falling-phase icicles and live shards. Tracked in arrays so per-frame
    /// gravity integration is a single linear loop with no name-keyed tree
    /// walk and no NSDictionary boxing. Warning-phase icicles are not in
    /// `fallingIcicles` — they're added the moment they detach.
    private struct FallingBody {
        weak var node: SKSpriteNode?
        let gravity: CGFloat
    }
    /// Falling icicles carry their shadow and original spawn-y so the
    /// per-frame integrator can lerp shadow scale/alpha as the icicle
    /// approaches `iceLandingY`. Shards reuse the simpler `FallingBody`.
    private struct FallingIcicle {
        weak var node: SKSpriteNode?
        weak var shadow: SKSpriteNode?
        let gravity: CGFloat
        let spawnY: CGFloat
    }
    private var fallingIcicles: [FallingIcicle] = []
    private var activeShards:   [FallingBody] = []

    // Pre-warmed haptic generators. Medium for accepted hits (HP loss);
    // light for i-frame-blocked saves and for shake-radius ground landings.
    // Near-miss (severity == 0) landings stay haptic-silent — deferred to
    // penguinslide-y7f, where close-call becomes a scored mechanic.
    // Game-over haptic stays in GameScene (UINotificationFeedbackGenerator.error).
    private let hapticHit = UIImpactFeedbackGenerator(style: .medium)
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)

    // Cached shatter action. Pre-built once so each invocation is a cheap
    // run() call rather than a fresh disk lookup. `waitForCompletion: false`
    // so the action returns immediately and overlapping calls stack cleanly
    // at peak spawn rate.
    private let shatterSound = SKAction.playSoundFileNamed("icicle_shatter.caf",
                                                            waitForCompletion: false)
    // Crack uses SKAudioNode so we can attenuate it (the raw clip is loud
    // enough to grate when icicles spawn 2-3×/s). stop+play on each spawn
    // restarts the clip, which also naturally rate-limits the SFX so it
    // doesn't pile up at peak.
    private var crackAudioNode: SKAudioNode?
    private let crackRestart = SKAction.sequence([.stop(), .play()])

    // Penguin yelp on damaging hit (HP loss). Skipped on i-frame saves so
    // the cry stays meaningful as "ouch, that hurt". stop+play restarts so
    // back-to-back hits don't queue up a chorus.
    private var cryAudioNode: SKAudioNode?
    private let cryRestart = SKAction.sequence([.stop(), .play()])

    /// Cached white-dot texture for snow particles. Building once and reusing
    /// is dramatically cheaper than emitting an SKShapeNode per particle.
    private lazy var puffTexture: SKTexture = {
        let r: CGFloat = 3
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: r * 2, height: r * 2))
        let img = renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: r * 2, height: r * 2))
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        return tex
    }()

    /// Soft dark ellipse used as the under-icicle shadow. Cached once and
    /// shared via SKSpriteNode so spawning a shadow per icicle is a single
    /// texture reference, not a path rebuild.
    private lazy var shadowTexture: SKTexture = {
        let w: CGFloat = 64
        let h: CGFloat = 18
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
        let img = renderer.image { ctx in
            // Radial-ish soft falloff: solid center, fades to transparent edge.
            // A real CGGradient would be sharper but more code; this two-pass
            // ellipse stack reads fine at the small scales the shadow runs at.
            let cg = ctx.cgContext
            cg.saveGState()
            cg.setFillColor(UIColor(white: 0, alpha: 0.45).cgColor)
            cg.fillEllipse(in: CGRect(x: w * 0.10, y: h * 0.20,
                                       width: w * 0.80, height: h * 0.60))
            cg.setFillColor(UIColor(white: 0, alpha: 0.55).cgColor)
            cg.fillEllipse(in: CGRect(x: w * 0.25, y: h * 0.30,
                                       width: w * 0.50, height: h * 0.40))
            cg.restoreGState()
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        return tex
    }()

    /// Small triangular icy-blue chip used for shatter shards.
    private lazy var shardTexture: SKTexture = {
        let s: CGFloat = 8
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: s, height: s))
        let img = renderer.image { _ in
            let color = UIColor(red: 0.78, green: 0.92, blue: 1.0, alpha: 1)
            color.setFill()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: s / 2, y: 0))
            path.addLine(to: CGPoint(x: s, y: s))
            path.addLine(to: CGPoint(x: 0, y: s))
            path.close()
            path.fill()
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        return tex
    }()

    init(scene: SKScene, camera: SKCameraNode, penguin: Penguin,
         iceTopY: CGFloat, iceLandingY: CGFloat,
         iceLeftX: CGFloat, iceRightX: CGFloat,
         sceneSize: CGSize) {
        self.scene = scene
        self.camera = camera
        self.penguin = penguin
        self.iceTopY = iceTopY
        self.iceLandingY = iceLandingY
        self.iceLeftX = iceLeftX
        self.iceRightX = iceRightX
        self.sceneSize = sceneSize
        hapticHit.prepare()
        hapticLight.prepare()

        let crack = SKAudioNode(fileNamed: "icicle_crack.caf")
        crack.autoplayLooped = false
        crack.isPositional = false
        crack.run(SKAction.changeVolume(to: 0.25, duration: 0))
        scene.addChild(crack)
        crackAudioNode = crack

        let cry = SKAudioNode(fileNamed: "penguin_cry.caf")
        cry.autoplayLooped = false
        cry.isPositional = false
        cry.run(SKAction.changeVolume(to: 0.9, duration: 0))
        scene.addChild(cry)
        cryAudioNode = cry
    }

    /// Per-frame tick. Spawns icicles on cadence, integrates per-body
    /// gravity, and checks landings.
    func update(dt: TimeInterval, elapsed: TimeInterval) {
        timeSinceLastSpawn += dt
        if elapsed > Tuning.Run.gracePeriod, timeSinceLastSpawn >= nextSpawnInterval {
            spawnIcicle(elapsed: elapsed)
            timeSinceLastSpawn = 0
            nextSpawnInterval = currentSpawnInterval(elapsed: elapsed)
        }
        integrateAndCheckLandings(dt: dt)
    }

    /// Remove all icicles and shards. Called by GameScene.restart().
    func reset() {
        guard let scene else { return }
        // Tracked arrays only cover falling icicles; warning-phase icicles
        // still live as named children, so enumerate covers both paths.
        scene.enumerateChildNodes(withName: "icicle") { node, _ in node.removeFromParent() }
        scene.enumerateChildNodes(withName: "icicleShadow") { node, _ in node.removeFromParent() }
        for entry in activeShards { entry.node?.removeFromParent() }
        for entry in fallingIcicles { entry.shadow?.removeFromParent() }
        fallingIcicles.removeAll(keepingCapacity: true)
        activeShards.removeAll(keepingCapacity: true)
        timeSinceLastSpawn = 0
        nextSpawnInterval = Tuning.Icicle.spawnIntervalStart
    }

    /// Pause shard fade actions on game over. `physicsWorld.speed = 0` halts
    /// physics-driven motion, but SKActions (the shard fadeOut) run
    /// independently — without this, shards keep fading while icicles freeze
    /// and the world looks half-paused.
    func pauseShardActions() {
        for entry in activeShards { entry.node?.isPaused = true }
    }

    /// Called by GameScene when an icicle's physics body contacts the penguin.
    /// `accepted` reports whether the penguin actually took damage (false
    /// when i-frames absorbed the hit). Either way the icicle is consumed —
    /// a hit is a hit. We just dial the FX volume by the `accepted` flag.
    func onIcicleHitPenguin(icicle: SKSpriteNode, at contactPoint: CGPoint, accepted: Bool) {
        guard let body = icicle.physicsBody else { return }

        // Drop the icicle from the manual gravity loop — we're about to
        // override its velocity for the recoil and let it fade out. Also
        // fade out the shadow now: with the icicle ricocheting up/sideways
        // it no longer represents an incoming impact, so leaving the shadow
        // on the ice would read as a stale "still about to land" cue.
        if let idx = fallingIcicles.firstIndex(where: { $0.node === icicle }) {
            let shadow = fallingIcicles[idx].shadow
            fallingIcicles.remove(at: idx)
            shadow?.run(.sequence([.fadeOut(withDuration: 0.12), .removeFromParent()]))
        }

        // Recoil away from the penguin. Mirrors the knockback direction
        // applied to the penguin in `tryTakeHit`.
        let awayX: CGFloat = icicle.position.x >= (penguin?.node.position.x ?? icicle.position.x) ? 1 : -1
        body.velocity = CGVector(dx: awayX * 220, dy: 360)
        body.angularVelocity = CGFloat.random(in: -8...8)

        if accepted {
            hapticHit.impactOccurred()
            scene?.run(shatterSound)
            cryAudioNode?.run(cryRestart)
            shatterIcicle(at: contactPoint, severity: 1.0,
                          countOverride: Tuning.Feel.crackBurstShards,
                          speedScaleOverride: Tuning.Feel.crackBurstSpeedScale)
            screenShake(near: contactPoint.x)
        } else {
            // Blocked by i-frames: softer pop, no shake. The penguin's
            // alpha flicker is the feedback for "still invulnerable".
            hapticLight.impactOccurred()
            scene?.run(shatterSound)
            shatterIcicle(at: contactPoint, severity: 0.6,
                          countOverride: Tuning.Feel.shardCountMax,
                          speedScaleOverride: 1.2)
        }

        icicle.run(.sequence([
            .wait(forDuration: 0.15),
            .group([
                .fadeOut(withDuration: 0.2),
                .scale(to: 0.6, duration: 0.2)
            ]),
            .removeFromParent()
        ]))
    }

    // MARK: - Difficulty curve

    private func progress(elapsed: TimeInterval) -> CGFloat {
        let p = (elapsed - Tuning.Run.gracePeriod) / Tuning.Run.rampDuration
        return CGFloat(max(0, min(1, p)))
    }

    private func currentSpawnInterval(elapsed: TimeInterval) -> TimeInterval {
        let p = TimeInterval(progress(elapsed: elapsed))
        return Tuning.Icicle.spawnIntervalStart + (Tuning.Icicle.spawnIntervalEnd - Tuning.Icicle.spawnIntervalStart) * p
    }

    /// Mean gravity scale lerps with progress; each spawn is jittered ±variance.
    /// The returned scale multiplies `Tuning.Icicle.sceneGravity` to produce the
    /// effective per-icicle gravity stored in the icicle's `FallingBody` entry.
    private func computedIcicleGravityScale(elapsed: TimeInterval) -> CGFloat {
        let p = progress(elapsed: elapsed)
        let mean = Tuning.Icicle.gravityScaleStart
            + (Tuning.Icicle.gravityScaleEnd - Tuning.Icicle.gravityScaleStart) * p
        let jitter = Tuning.Icicle.gravityScaleVariance
        let factor = CGFloat.random(in: (1 - jitter)...(1 + jitter))
        return mean * factor
    }

    /// Lead-the-target spawn x: predicts where the penguin will be when the
    /// icicle actually lands (not just at end of warning), then adds jitter
    /// that tightens as the difficulty ramp progresses. A fraction of spawns
    /// are pure-random for variety so the field never feels 100% deterministic.
    ///
    /// `predictedFallTime` is the kinematically-computed seconds from detach
    /// to ice-surface contact for this specific icicle. Slow icicles get a
    /// longer prediction window (lead more), fast icicles a shorter one.
    private func targetedSpawnX(iconHalfWidth halfW: CGFloat,
                                predictedFallTime: TimeInterval,
                                elapsed: TimeInterval) -> CGFloat {
        let minX = iceLeftX + halfW
        let maxX = iceRightX - halfW

        if Double.random(in: 0...1) < Tuning.Chase.randomChance {
            return CGFloat.random(in: minX...maxX)
        }

        guard let penguin else { return CGFloat.random(in: minX...maxX) }
        let leadTime = CGFloat(Tuning.Icicle.warningDuration + predictedFallTime)
        let predicted = penguin.node.position.x
            + penguin.vx * leadTime * Tuning.Chase.leadFactor

        let p = progress(elapsed: elapsed)
        let jitterFrac = Tuning.Chase.jitterStart
            + (Tuning.Chase.jitterEnd - Tuning.Chase.jitterStart) * p
        let jitter = jitterFrac * (iceRightX - iceLeftX)
        let raw = predicted + CGFloat.random(in: -jitter...jitter)
        return min(maxX, max(minX, raw))
    }

    // MARK: - Spawn

    private func spawnIcicle(elapsed: TimeInterval) {
        guard let scene else { return }
        let width = CGFloat.random(in: 36...54)
        let height = width * CGFloat.random(in: 2.4...3.4)

        // Per-spawn gravity decided up front so we can give the aim algorithm
        // a real ballistic prediction. Fall distance is from spawn-y down to
        // the moment the icicle's bottom touches the ice. Solving
        //     h = v₀·t + ½·g·t²    for t (with t > 0):
        //     t = (-v₀ + √(v₀² + 2·g·h)) / g
        let perIcicleGravity = Tuning.Icicle.sceneGravity * computedIcicleGravityScale(elapsed: elapsed)
        let spawnY = sceneSize.height - height / 2 - 4
        // `iceLandingY` is the penguin's foot plane — the surface the icicle
        // visually crashes onto. Targeting solves the ballistic equation
        // against this y so `targetedSpawnX` leads the penguin to the real
        // landing point, not the cosmetic horizon line (`iceTopY`).
        let h = spawnY - (iceLandingY + height / 2)
        let v0 = Tuning.Icicle.initialDownVelocity
        let g = perIcicleGravity
        let predictedFallTime: TimeInterval = h > 0 && g > 0
            ? TimeInterval((-v0 + sqrt(v0 * v0 + 2 * g * h)) / g)
            : 0

        let icicle = SKSpriteNode(texture: SpriteCatalog.texture(for: .icicle),
                                  size: CGSize(width: width, height: height))
        // Aim at where the penguin will be, not a random column — this is the
        // "chasing" behavior. See `targetedSpawnX` for the full algorithm.
        let spawnX = targetedSpawnX(iconHalfWidth: width / 2,
                                    predictedFallTime: predictedFallTime,
                                    elapsed: elapsed)
        icicle.position = CGPoint(x: spawnX, y: spawnY)
        icicle.zPosition = 5
        icicle.name = "icicle"
        scene.addChild(icicle)
        crackAudioNode?.run(crackRestart)

        // Telegraph: shake + crack overlay growing.
        let shake = SKAction.sequence([
            .moveBy(x:  2, y: 0, duration: 0.04),
            .moveBy(x: -4, y: 0, duration: 0.08),
            .moveBy(x:  2, y: 0, duration: 0.04)
        ])
        let warning = SKAction.repeat(shake, count: max(1, Int(Tuning.Icicle.warningDuration / 0.16)))

        // Warning tint: cheap color-blend toward dark (one GPU op per frame)
        // instead of overlaying a path-based SKShapeNode every spawn.
        icicle.color = UIColor(white: 0.25, alpha: 1)
        icicle.colorBlendFactor = 0
        icicle.run(.customAction(withDuration: Tuning.Icicle.warningDuration) { node, t in
            (node as? SKSpriteNode)?.colorBlendFactor = (t / CGFloat(Tuning.Icicle.warningDuration)) * 0.45
        })

        // Snow puff as it detaches.
        let puff = SKAction.run { [weak self, weak icicle] in
            guard let self, let icicle else { return }
            self.spawnSnowPuff(at: icicle.position)
        }

        // Fall — gravity is integrated manually each frame via the
        // `fallingIcicles` entry below. `perIcicleGravity` (computed above
        // for the ballistic-aim prediction) is reused as the integration value.
        let landingY = iceLandingY   // captured so the closure doesn't reach for `self.iceLandingY`
        let fall = SKAction.run { [weak self, weak icicle] in
            guard let self, let icicle else { return }
            let pb = SKPhysicsBody(rectangleOf: CGSize(width: width * 0.6, height: height * 0.85))
            pb.isDynamic = true
            pb.affectedByGravity = false
            pb.linearDamping = 0.1
            pb.angularDamping = 0.4
            pb.allowsRotation = true
            pb.mass = Tuning.Icicle.massKg
            pb.restitution = Tuning.Icicle.restitution
            // Belt-and-braces against tunneling at peak fall speeds (~15 pt
            // per frame at 60 fps under late-game gravity). Without this,
            // SpriteKit can step the icicle past a thin hitbox between two
            // physics ticks and never fire `didBegin`.
            pb.usesPreciseCollisionDetection = true
            pb.categoryBitMask = Category.icicle
            pb.contactTestBitMask = Category.penguin
            pb.collisionBitMask = 0
            pb.velocity = CGVector(dx: 0, dy: -Tuning.Icicle.initialDownVelocity)
            icicle.physicsBody = pb

            // Shadow on the ice surface, directly under the icicle. Z sits
            // just under the penguin (10) so it reads as ground decoration
            // without ever covering the player sprite. Starts at min
            // scale/alpha; the per-frame integrator lerps it up as the
            // icicle approaches `iceLandingY`.
            let shadow = SKSpriteNode(texture: self.shadowTexture)
            shadow.name = "icicleShadow"
            shadow.position = CGPoint(x: icicle.position.x, y: landingY)
            shadow.zPosition = 9.5
            shadow.setScale(Tuning.Feel.shadowMinScale)
            shadow.alpha = Tuning.Feel.shadowMinAlpha
            self.scene?.addChild(shadow)

            self.fallingIcicles.append(FallingIcicle(node: icicle,
                                                    shadow: shadow,
                                                    gravity: perIcicleGravity,
                                                    spawnY: icicle.position.y))
        }

        icicle.run(.sequence([warning, puff, fall]))
    }

    private func spawnSnowPuff(at p: CGPoint) {
        guard let scene else { return }
        for _ in 0..<5 {
            // SKSpriteNode + cached texture is ~an order of magnitude cheaper
            // than a per-particle SKShapeNode with a fresh circle path.
            let f = SKSpriteNode(texture: puffTexture)
            f.setScale(CGFloat.random(in: 0.5...1.0))
            f.position = p
            f.zPosition = 4
            scene.addChild(f)
            let dx = CGFloat.random(in: -20...20)
            let dy = CGFloat.random(in: -10...10)
            f.run(.sequence([
                .group([
                    .move(by: CGVector(dx: dx, dy: dy), duration: 0.4),
                    .fadeOut(withDuration: 0.4)
                ]),
                .removeFromParent()
            ]))
        }
    }

    // MARK: - Landing, shatter, shake

    /// Integrate per-body gravity (SpriteKit has no gravityScale per body)
    /// and check icicle landings in a single pass. Dead entries are filtered
    /// out so the arrays stay compact.
    private func integrateAndCheckLandings(dt: TimeInterval) {
        let dtF = CGFloat(dt)
        guard let penguin else { return }

        // Icicles: apply gravity, update under-icicle shadow, then check
        // for landing or fall-through.
        fallingIcicles = fallingIcicles.compactMap { entry in
            guard let icicle = entry.node, let body = icicle.physicsBody else {
                entry.shadow?.removeFromParent()
                return nil
            }
            body.velocity.dy -= entry.gravity * dtF

            // Shadow tracks the icicle's x on the landing plane, and lerps
            // its scale/alpha by how far through the fall the icicle is.
            // Without a positive (spawnY - landingY) span the lerp would
            // divide by zero on degenerate scenes; clamp to 0 in that case.
            if let shadow = entry.shadow {
                let span = entry.spawnY - iceLandingY
                let p: CGFloat = span > 0
                    ? 1 - max(0, min(1, (icicle.position.y - iceLandingY) / span))
                    : 0
                shadow.position = CGPoint(x: icicle.position.x, y: iceLandingY)
                shadow.setScale(Tuning.Feel.shadowMinScale
                    + (Tuning.Feel.shadowMaxScale - Tuning.Feel.shadowMinScale) * p)
                shadow.alpha = Tuning.Feel.shadowMinAlpha
                    + (Tuning.Feel.shadowMaxAlpha - Tuning.Feel.shadowMinAlpha) * p
            }

            let bottom = icicle.position.y - icicle.size.height / 2
            if bottom <= iceLandingY {
                let landingPoint = CGPoint(x: icicle.position.x, y: iceLandingY)
                // Every landing reaching the ice is a survived landing —
                // the penguin-contact path consumes icicles before they get
                // here. Severity is pure x-distance falloff to the camera
                // shake radius; no special-case zone needed now that
                // collisions resolve reliably.
                let dx = abs(landingPoint.x - penguin.node.position.x)
                let severity = max(0, 1 - dx / Tuning.Feel.shakeRadius)
                shatterIcicle(at: landingPoint, severity: severity)
                if severity > 0 {
                    hapticLight.impactOccurred()
                    scene?.run(shatterSound)
                    screenShake(near: landingPoint.x)
                }
                icicle.removeFromParent()
                entry.shadow?.removeFromParent()
                return nil
            }
            if icicle.position.y < -icicle.size.height {
                // Safety net — somehow fell past the floor with no shatter.
                icicle.removeFromParent()
                entry.shadow?.removeFromParent()
                return nil
            }
            return entry
        }

        // Shards: only gravity. Drop entries whose nodes have been removed
        // (the fadeOut sequence ends in `.removeFromParent()`).
        activeShards = activeShards.compactMap { entry in
            guard let shard = entry.node, shard.parent != nil,
                  let body = shard.physicsBody else { return nil }
            body.velocity.dy -= entry.gravity * dtF
            return entry
        }
    }

    /// Spawn a burst of physics-bodied shards that arc out from the landing
    /// point and fade. Shards have no contact tests — purely visual.
    /// `severity` ∈ [0, 1] scales shard count and launch speed for landings;
    /// the `countOverride` / `speedScaleOverride` params let the penguin-hit
    /// path pump up the burst beyond what severity alone would produce.
    private func shatterIcicle(at p: CGPoint, severity: CGFloat,
                               countOverride: Int? = nil,
                               speedScaleOverride: CGFloat? = nil) {
        guard let scene else { return }
        let s = max(0, min(1, severity))
        let count = countOverride
            ?? (Tuning.Feel.shardCountMin
                + Int(round(CGFloat(Tuning.Feel.shardCountMax - Tuning.Feel.shardCountMin) * s)))
        let speedScale = speedScaleOverride ?? (1.0 + Tuning.Feel.shardSeverityBoost * s)
        for _ in 0..<count {
            let shard = SKSpriteNode(texture: shardTexture)
            shard.setScale(CGFloat.random(in: 0.7...1.4))
            shard.position = p
            shard.zPosition = 6
            shard.zRotation = CGFloat.random(in: 0...(.pi * 2))
            shard.name = "shard"
            scene.addChild(shard)

            let pb = SKPhysicsBody(circleOfRadius: 2)
            pb.isDynamic = true
            pb.affectedByGravity = false
            pb.allowsRotation = true
            pb.categoryBitMask = Category.shard
            pb.contactTestBitMask = 0
            pb.collisionBitMask = 0
            pb.linearDamping = 0.2
            shard.physicsBody = pb

            // Outward fan biased upward so shards "pop" off the surface.
            let angle = CGFloat.random(in: (.pi * 0.15)...(.pi * 0.85))
            let speed = Tuning.Feel.shardLaunchSpeed * speedScale * CGFloat.random(in: 0.6...1.2)
            pb.velocity = CGVector(dx: cos(angle) * speed * (Bool.random() ? 1 : -1),
                                   dy: sin(angle) * speed)
            pb.angularVelocity = CGFloat.random(in: -8...8)

            // Shards fall at a fixed gravity, integrated manually each frame.
            activeShards.append(FallingBody(node: shard, gravity: Tuning.Icicle.sceneGravity))

            shard.run(.sequence([
                .fadeOut(withDuration: Tuning.Feel.shardLifetime),
                .removeFromParent()
            ]))
        }

        // Shockwave ring: a quick expanding/fading circle stamped at the
        // landing point. Reinforces "the icicle hit *this* spot on the
        // surface the penguin is on." Gated on severity so distant landings
        // (which already get only a small shard burst and no shake) don't
        // strobe a ring every frame at peak spawn rate.
        if s >= Tuning.Feel.shockwaveMinSeverity {
            let ring = SKShapeNode(circleOfRadius: 6)
            ring.position = p
            ring.zPosition = 6
            ring.strokeColor = UIColor(white: 1.0, alpha: 0.9)
            ring.fillColor = .clear
            ring.lineWidth = 2
            scene.addChild(ring)
            ring.run(.sequence([
                .group([
                    .scale(to: Tuning.Feel.shockwaveMaxScale,
                           duration: Tuning.Feel.shockwaveDuration),
                    .fadeOut(withDuration: Tuning.Feel.shockwaveDuration)
                ]),
                .removeFromParent()
            ]))
        }
    }

    /// Brief camera shake. Amplitude falls off linearly with x-distance from
    /// the penguin so distant landings don't shake the world.
    private func screenShake(near landingX: CGFloat) {
        guard let camera, let penguin else { return }
        let dx = abs(landingX - penguin.node.position.x)
        let t = max(0, 1 - dx / Tuning.Feel.shakeRadius)
        guard t > 0 else { return }
        let amp = Tuning.Feel.shakePeakAmplitude * t
        let center = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)

        // Snap back to dead center before starting a new shake. Without this,
        // a rapid second landing cancels the prior shake's final `move(to: center)`
        // mid-flight and the new sequence's `moveBy` starts from an off-center
        // camera — drift accumulates across consecutive impacts.
        camera.removeAction(forKey: "shake")
        camera.position = center
        // `randSign()` is evaluated 6 times here at *construction* time, not on
        // each playback frame — the SKAction sequence holds the resulting
        // ±offsets as fixed values. So each call to screenShake() builds a
        // fresh random wobble pattern, but that pattern plays back identically
        // for the duration of the action.
        let randSign: () -> CGFloat = { Bool.random() ? 1 : -1 }
        let shake = SKAction.sequence([
            .moveBy(x:  amp * randSign(), y: -amp * 0.5 * randSign(), duration: 0.04),
            .moveBy(x: -amp * 1.5 * randSign(), y:  amp * 0.7 * randSign(), duration: 0.05),
            .moveBy(x:  amp * 0.5 * randSign(), y: -amp * 0.2 * randSign(), duration: 0.04),
            .move(to: center, duration: 0.05)
        ])
        camera.run(shake, withKey: "shake")
    }
}
