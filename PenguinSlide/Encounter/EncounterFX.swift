//
//  EncounterFX.swift
//  PenguinSlide
//
//  Impact + dodge feedback for the Snow Monster encounter
//  (penguinslide-gyu.16) — the encounter mirror of IcicleSystem's
//  established cheap-FX techniques: cached textures (never per-particle
//  SKShapeNode), array-tracked transient nodes so game-over can freeze
//  them per-node (`pauseActions`) and restart can scrub them (`reset`),
//  one-shot SKActions that self-remove, and pre-warmed pooled
//  UIImpactFeedbackGenerators.
//
//  ## What plays when (mirrors onIcicleHitPenguin's accepted handling)
//
//  HIT (a snowball connected with Papi):
//  - Powder puff + gravity snow chunks (penguinslide-bo8): a soft
//    cached puff swells/fades AT the impact screen point, and 6–10
//    small snow-chip sprites launch radially and fall under manual
//    gravity — the icicle-shatter recipe, by Mina's spec. Chunks are
//    integrated in `update(dt:)` (ticked from GameScene's encounter
//    phase bodies), NOT SKAction-driven, so the game-over freeze
//    (ticks stop) leaves them hanging mid-air in the frozen frame and
//    the dt == 0 sentinel adds nothing. Drawn just in front of the
//    PapiAvatar node so the ball reads as going INTO Papi; the system
//    retires the ball node in the same sweep frame, so no ball is ever
//    visible passing through the splash. Plays alongside the avatar's
//    hurt flash/squash (gyu.11) and i-frame flicker.
//    (The original SpriteCook SnowballBurst sheet is RETIRED: its
//    frames carried an opaque white background that rendered as a
//    white box on device — see spritecook-assets.json's retired note.)
//  - accepted == true  (HP lost):    medium haptic + full hit shake.
//  - accepted == false (i-frames):   light haptic, smaller/dimmer
//    burst, NO shake — the icicle path's "softer pop" treatment; the
//    avatar's alpha flicker is the "still invulnerable" cue.
//
//  DODGE (a snowball crossed the camera plane clear of Papi):
//  - Brief speed-line whoosh accent near the crossing point, streaking
//    in the ball's pass direction (away from Papi), intensity scaled
//    by severity. The score float is NOT here — GameScene's
//    registerEncounterDodge already pays it through hud.floatBonus
//    (one float mechanism, not two).
//  - Light haptic ONLY for high-severity shaves
//    (>= Tuning.Encounter.dodgeHapticSeverity) so haptics stay
//    meaningful; wide dodges are haptic-silent, exactly like distant
//    icicle landings.
//
//  GameScene owns the wiring (the accepted flag exists only after
//  PapiAvatar.takeHit consults the real penguin's i-frame clock), the
//  game-over freeze (`pauseActions`, next to icicles.pauseShardActions
//  and encounterSystem.pauseActions), and the teardown (`reset` from
//  endEncounterPresentation, so restart-from-any-phase scrubs FX).
//

import SpriteKit
import UIKit

// FX knobs — Tuning.Encounter's Feel group; living here as an extension
// per the EncounterWorld/PapiAvatar precedent (fold into Tuning.swift
// whenever convenient).
extension Tuning.Encounter {
    /// Powder-puff core footprint (pt) at avatar depth scale 1.0 — the
    /// soft white pop under the chunk burst. It should swallow the
    /// ~64 pt ball without covering the whole 180 pt avatar. Raise for
    /// a beefier impact read; lower for a subtler one.
    static let impactPuffBaseSize: CGFloat = 96
    /// Puff one-shot lifetime (s): swells to ~1.25× while fading out.
    static let impactPuffDuration: TimeInterval = 0.32
    /// Snow chunks launched by an accepted hit (HP lost); the i-frame
    /// absorbed branch spawns the smaller count. Per-hit node creation
    /// only — never per-frame.
    static let impactChunkCount: Int = 10
    static let impactChunkCountAbsorbed: Int = 6
    /// Chunk radial launch speed range (pt/s at depth scale 1.0).
    static let impactChunkSpeedMin: CGFloat = 150
    static let impactChunkSpeedMax: CGFloat = 330
    /// Manual gravity on chunks (pt/s² at depth scale 1.0) — the
    /// integrate-it-yourself doctrine shared with IcicleSystem's shards.
    static let impactChunkGravity: CGFloat = 1050
    /// Chunk lifetime (s); alpha ramps to 0 across it, then the node is
    /// removed by the integration tick.
    static let impactChunkLifetime: TimeInterval = 0.6
    /// Chunk sprite size range (pt at depth scale 1.0).
    static let impactChunkSizeMin: CGFloat = 7
    static let impactChunkSizeMax: CGFloat = 15
    /// Softer-pop multiplier for i-frame-absorbed hits — scales chunk
    /// count/speed and puff size/alpha, mirroring onIcicleHitPenguin's
    /// accepted == false branch. Raise toward 1 to make absorbed hits
    /// read as loud as real ones. (Named distinctly from the AUDIO
    /// `impactAbsorbedScale`, which ducks the impact sample's volume.)
    static let impactFXSoftenScale: CGFloat = 0.65
    /// Minimum dodge severity (∈ [0, 1]) that earns the light haptic
    /// tick. Raise so only hair's-breadth shaves buzz; lower for more
    /// generous physical feedback (1.0 silences dodge haptics).
    static let dodgeHapticSeverity: CGFloat = 0.5
    /// Speed-line whoosh accent: lines per dodge at severity 1 (lerps
    /// down to 1 line at severity 0). Per-dodge node creation only —
    /// never per-frame.
    static let dodgeAccentLineCountMax: Int = 4
    /// Lifetime (s) of one speed-line accent before it self-removes.
    static let dodgeAccentDuration: TimeInterval = 0.28
}

final class EncounterFX {

    /// Burst draw-order slot: JUST in front of the avatar (whose
    /// reserved band is 50..59 — EncounterWorld's z-stack doc), so the
    /// splat reads as the snowball going INTO Papi, never behind him
    /// and never over the encounter HUD accents.
    static let burstZPosition: CGFloat = PapiAvatar.zPositionInEncounterRoot + 1

    /// Speed-line accents sit at the snowball band's near edge — the
    /// dodged ball just crossed the camera plane there.
    static let dodgeAccentZPosition: CGFloat = Tuning.Encounter.snowballZPositionNear

    // MARK: - Haptic mapping (pure — unit-tested)

    /// Which pooled generator a cue fires. Pure mapping functions so the
    /// accepted/absorbed and severity-threshold contracts are
    /// assertable without UIKit side effects.
    enum HapticCue: Equatable {
        case medium
        case light
        case none
    }

    /// Hit mapping — EXACTLY the icicle path's distinction
    /// (onIcicleHitPenguin): accepted (HP lost) → medium, i-frame
    /// absorbed → light.
    static func hitHaptic(accepted: Bool) -> HapticCue {
        accepted ? .medium : .light
    }

    /// Dodge mapping: light only for high-severity shaves, silent
    /// otherwise so haptics stay meaningful.
    static func dodgeHaptic(severity: CGFloat) -> HapticCue {
        severity >= Tuning.Encounter.dodgeHapticSeverity ? .light : .none
    }

    // MARK: - State

    /// Visual parent (GameScene's encounterRoot — FX shows/hides with
    /// the encounter world as one toggle). Weak: the scene owns the
    /// node tree (IcicleSystem's convention).
    private weak var parent: SKNode?
    /// The shared scene camera — hit shake targets it with the same
    /// "shake" action key IcicleSystem uses, so restart()'s
    /// removeAction(forKey: "shake") + recenter covers both worlds.
    private weak var camera: SKCameraNode?
    private let sceneSize: CGSize

    // Pre-warmed pooled haptic generators — IcicleSystem's exact pair:
    // medium for accepted hits (HP loss), light for i-frame saves and
    // high-severity dodges.
    private let hapticHit = UIImpactFeedbackGenerator(style: .medium)
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)

    /// Live transient FX nodes (puffs, speed lines). Array-tracked —
    /// the activeBursts pattern — so `pauseActions()` can freeze each
    /// node's one-shot mid-flight for a coherent game-over frame and
    /// `reset()` can scrub them all. Entries self-evict when their
    /// action completes. `private(set)` for test assertions.
    private(set) var activeFX: [SKNode] = []

    /// One launched snow chunk — manually integrated (no physics body:
    /// nothing to collide). Internal fields are readable so tests can
    /// assert the gravity/lifetime contract without ticking SKActions.
    struct SnowChunk {
        weak var node: SKSpriteNode?
        var vx: CGFloat
        var vy: CGFloat
        var spin: CGFloat
        var age: TimeInterval
        let lifetime: TimeInterval
        let gravity: CGFloat
        let baseAlpha: CGFloat
    }

    /// Live impact chunks. Not in `activeFX`: chunks are tick-driven,
    /// not SKAction-driven, so the game-over freeze comes from the
    /// update guard (ticks stop), not from `isPaused`.
    private(set) var activeChunks: [SnowChunk] = []

    // MARK: - Cached textures

    /// Thin white streak for the dodge whoosh — rendered ONCE and
    /// shared (the puffTexture doctrine: a cached texture per sprite,
    /// never a per-particle SKShapeNode).
    static let speedLineTexture: SKTexture = {
        let w: CGFloat = 36
        let h: CGFloat = 4
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            // Solid core with a softer full-length underlay so the
            // streak reads as motion, not a bar.
            cg.setFillColor(UIColor(white: 1, alpha: 0.55).cgColor)
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                         cornerRadius: h / 2).fill()
            cg.setFillColor(UIColor.white.cgColor)
            UIBezierPath(roundedRect: CGRect(x: w * 0.25, y: h * 0.25,
                                             width: w * 0.5, height: h * 0.5),
                         cornerRadius: h / 4).fill()
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        return tex
    }()

    /// Small rounded snow chip for impact chunks — cached once (the
    /// puffTexture doctrine). Irregular blob, white core over an
    /// icy-blue shade so chips read against both sky and snow.
    static let snowChunkTexture: SKTexture = {
        let size = CGSize(width: 14, height: 12)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 3, y: 0.5))
            path.addLine(to: CGPoint(x: 11.5, y: 1.5))
            path.addLine(to: CGPoint(x: 13.5, y: 7))
            path.addLine(to: CGPoint(x: 8, y: 11.5))
            path.addLine(to: CGPoint(x: 1, y: 8.5))
            path.close()
            cg.setFillColor(UIColor(red: 0.78, green: 0.88, blue: 0.97, alpha: 1).cgColor)
            path.fill()
            cg.translateBy(x: 2.5, y: 1.5)
            cg.scaleBy(x: 0.65, y: 0.65)
            cg.setFillColor(UIColor.white.cgColor)
            path.fill()
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .nearest   // matches the pixel-art world
        return tex
    }()

    /// Soft radial powder puff — three stacked alpha circles rendered
    /// once, never a per-hit SKShapeNode.
    static let puffTexture: SKTexture = {
        let d: CGFloat = 64
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: d, height: d))
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            for (radius, alpha): (CGFloat, CGFloat) in [(32, 0.25), (24, 0.45), (15, 0.85)] {
                cg.setFillColor(UIColor(white: 1, alpha: alpha).cgColor)
                cg.fillEllipse(in: CGRect(x: d / 2 - radius, y: d / 2 - radius,
                                          width: radius * 2, height: radius * 2))
            }
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        return tex
    }()

    // MARK: - Init

    init(parent: SKNode, camera: SKCameraNode?, sceneSize: CGSize) {
        self.parent = parent
        self.camera = camera
        self.sceneSize = sceneSize
        hapticHit.prepare()
        hapticLight.prepare()
    }

    // MARK: - Hit

    /// Snowball connected with Papi. `point` is the ball's projected
    /// screen position at the hit frame (already on the avatar — the
    /// resolver guarantees it's inside the depth window and lateral hit
    /// radius); `depthScale` is the avatar's projector scale (exactly
    /// 1.0 at today's z = 0 station — passed live so burst sizing stays
    /// correct if the avatar ever moves off the camera plane);
    /// `accepted` is `tryTakeHit`'s verdict (false = i-frames absorbed
    /// the hit).
    func playHitBurst(at point: CGPoint, depthScale: CGFloat, accepted: Bool) {
        fire(Self.hitHaptic(accepted: accepted))
        if accepted {
            // Keyed ON THE HIT, not on distance: a connecting ball is
            // by definition at the player, so the icicle recipe's
            // distance falloff evaluates to full amplitude here.
            hitShake()
        }

        guard let parent else { return }
        let soften: CGFloat = accepted ? 1.0 : Tuning.Encounter.impactFXSoftenScale

        // Powder-puff core: a tracked one-shot (pause-registered via
        // activeFX) that swells and fades at the impact point.
        let puffSize = Tuning.Encounter.impactPuffBaseSize * depthScale * soften
        let puff = SKSpriteNode(texture: Self.puffTexture)
        puff.size = CGSize(width: puffSize, height: puffSize)
        puff.position = point
        puff.zPosition = Self.burstZPosition
        puff.name = "snowballPuff"
        if !accepted {
            // Softer pop for the blocked hit — the avatar's i-frame
            // flicker carries the "still invulnerable" message.
            puff.alpha = 0.8
        }
        parent.addChild(puff)
        let dur = Tuning.Encounter.impactPuffDuration
        runTracked(puff, .sequence([
            .group([
                .scale(to: 1.25, duration: dur),
                .fadeOut(withDuration: dur)
            ]),
            .removeFromParent()
        ]))

        spawnChunks(at: point, depthScale: depthScale, soften: soften)
    }

    /// Launch the gravity snow chunks for one impact. Radial directions
    /// with an upward lift so the spray arcs like the icicle shatter,
    /// then `update(dt:)` owns them.
    private func spawnChunks(at point: CGPoint, depthScale: CGFloat, soften: CGFloat) {
        guard let parent else { return }
        let count = soften >= 1
            ? Tuning.Encounter.impactChunkCount
            : Tuning.Encounter.impactChunkCountAbsorbed
        for _ in 0..<count {
            let chunk = SKSpriteNode(texture: Self.snowChunkTexture)
            let side = CGFloat.random(
                in: Tuning.Encounter.impactChunkSizeMin...Tuning.Encounter.impactChunkSizeMax
            ) * depthScale
            chunk.size = CGSize(width: side, height: side * 0.85)
            chunk.position = point
            chunk.zPosition = Self.burstZPosition + 1
            chunk.zRotation = CGFloat.random(in: 0...(2 * .pi))
            chunk.name = "snowChunk"
            chunk.alpha = soften >= 1 ? 1.0 : 0.8
            parent.addChild(chunk)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(
                in: Tuning.Encounter.impactChunkSpeedMin...Tuning.Encounter.impactChunkSpeedMax
            ) * depthScale * soften
            activeChunks.append(SnowChunk(
                node: chunk,
                vx: cos(angle) * speed,
                // Vertical component is folded upward (+ a flat lift) so
                // every chunk pops before gravity pulls it down — the
                // splash read, not a uniform sphere.
                vy: abs(sin(angle)) * speed * 0.9 + 70 * depthScale,
                spin: CGFloat.random(in: -7...7),
                age: 0,
                lifetime: Tuning.Encounter.impactChunkLifetime,
                gravity: Tuning.Encounter.impactChunkGravity * depthScale,
                baseAlpha: soften >= 1 ? 1.0 : 0.8
            ))
        }
    }

    /// Manual chunk integration — called from GameScene's encounter
    /// phase bodies (the same place the encounter system ticks), so the
    /// update-loop guard freezes chunks on game over and the dt == 0
    /// sentinel is a free no-op (the repo's manual-physics doctrine —
    /// see GameScene.update's ordering contract).
    func update(dt: TimeInterval) {
        guard dt > 0, !activeChunks.isEmpty else { return }
        let dtF = CGFloat(dt)
        activeChunks = activeChunks.compactMap { entry in
            var c = entry
            guard let node = c.node, node.parent != nil else { return nil }
            c.age += dt
            if c.age >= c.lifetime {
                node.removeFromParent()
                return nil
            }
            c.vy -= c.gravity * dtF
            node.position = CGPoint(x: node.position.x + c.vx * dtF,
                                    y: node.position.y + c.vy * dtF)
            node.zRotation += c.spin * dtF
            node.alpha = c.baseAlpha * (1 - CGFloat(c.age / c.lifetime))
            return c
        }
    }

    // MARK: - Dodge

    /// Snowball dodged. `point` is the ball's projected position at the
    /// camera-plane crossing; `direction` is the lateral pass side
    /// (+1 = the ball passed to Papi's right), so the whoosh streaks
    /// away from the avatar; `severity` ∈ [0, 1] scales line count and
    /// punch. The score float is GameScene's registerEncounterDodge.
    func playDodgeAccent(at point: CGPoint, severity: CGFloat, direction: CGFloat) {
        fire(Self.dodgeHaptic(severity: severity))

        guard let parent else { return }
        let s = max(0, min(1, severity))
        let dir: CGFloat = direction >= 0 ? 1 : -1
        let count = 1 + Int((CGFloat(Tuning.Encounter.dodgeAccentLineCountMax - 1) * s).rounded())
        let duration = Tuning.Encounter.dodgeAccentDuration
        for i in 0..<count {
            let line = SKSpriteNode(texture: Self.speedLineTexture)
            line.name = "dodgeSpeedLine"
            // Small vertical fan around the crossing point; the first
            // line sits on it so even a severity-0 accent registers.
            let spread = CGFloat(i) - CGFloat(count - 1) / 2
            line.position = CGPoint(x: point.x, y: point.y + spread * 14)
            line.zPosition = Self.dodgeAccentZPosition
            line.alpha = 0.35 + 0.55 * s
            // Scale-pop start: stretches out along the streak direction
            // as it travels.
            line.xScale = 0.4 * dir
            line.yScale = 0.8
            parent.addChild(line)
            let travel = dir * (70 + 90 * s)
            runTracked(line, .group([
                .moveBy(x: travel, y: 0, duration: duration),
                .scaleX(to: 1.3 * dir, duration: duration),
                .fadeOut(withDuration: duration)
            ]))
        }
    }

    // MARK: - Lifecycle (GameScene seams)

    /// One-way freeze for `triggerGameOver()` — sits beside
    /// `icicles.pauseShardActions()` and `encounterSystem.pauseActions()`
    /// so a death mid-burst/mid-whoosh leaves a coherent frozen frame
    /// instead of FX animating over a stopped world.
    func pauseActions() {
        setActionsPaused(true)
    }

    func setActionsPaused(_ paused: Bool) {
        for node in activeFX { node.isPaused = paused }
    }

    /// Scrub every transient FX node — called from
    /// endEncounterPresentation() (outro teardown AND restart from any
    /// phase), so no burst/whoosh can leak into the side view or the
    /// next encounter.
    func reset() {
        for node in activeFX { node.removeFromParent() }
        activeFX.removeAll(keepingCapacity: true)
        for entry in activeChunks { entry.node?.removeFromParent() }
        activeChunks.removeAll(keepingCapacity: true)
    }

    // MARK: - Private

    private func fire(_ cue: HapticCue) {
        switch cue {
        case .medium: hapticHit.impactOccurred()
        case .light:  hapticLight.impactOccurred()
        case .none:   break
        }
    }

    /// Track a transient node and run its one-shot. The completion
    /// self-evicts the entry (the activeBursts pattern) — and also
    /// sweeps any nodes already detached, so the array can't grow
    /// across a long volley.
    private func runTracked(_ node: SKNode, _ action: SKAction) {
        activeFX.append(node)
        node.run(action) { [weak self, weak node] in
            self?.activeFX.removeAll { $0 === node || $0.parent == nil }
        }
    }

    /// IcicleSystem.screenShake's exact wobble recipe, keyed on the hit
    /// (t = 1 — the falloff envelope's value at distance 0) instead of
    /// landing distance. Same "shake" action key + snap-to-center
    /// preamble, so rapid hits can't accumulate camera drift and
    /// restart()'s camera recenter covers this path too.
    private func hitShake() {
        guard let camera else { return }
        let amp = Tuning.Feel.shakePeakAmplitude
        let center = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
        camera.removeAction(forKey: "shake")
        camera.position = center
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
