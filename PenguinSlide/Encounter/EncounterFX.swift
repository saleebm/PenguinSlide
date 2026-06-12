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
//  - Snow-splat burst: the SpriteCook one-shot sheet (SnowballBurst,
//    8 frames @ 8 fps — see spritecook-assets.json) anchored AT the
//    impact screen point on the avatar, scaled by the avatar's depth
//    scale, drawn JUST in front of the PapiAvatar node so the ball
//    reads as going INTO Papi. The encounter system retires the ball
//    node inside the same sweep frame that fires the hit callback, so
//    no ball is ever visible passing through the splat. The burst
//    plays alongside the avatar's own hurt flash/squash (gyu.11) and
//    i-frame flicker.
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
    /// Snow-splat burst footprint (pt) at avatar depth scale 1.0 — the
    /// splat should swallow the ~64 pt ball and visibly slap the 180 pt
    /// avatar without covering the whole sprite. Raise for a beefier
    /// impact read; lower for a subtler puff.
    static let burstBaseSize: CGFloat = 120
    /// Burst size multiplier for i-frame-absorbed hits — the "softer
    /// pop" treatment mirroring onIcicleHitPenguin's accepted == false
    /// branch. Raise toward 1 to make absorbed hits read as loud as
    /// real ones; lower for a fainter blocked-hit cue.
    static let burstAbsorbedScale: CGFloat = 0.65
    /// Burst clip playback rate — matches the 8 fps recorded for
    /// snowball_impact_burst in spritecook-assets.json.
    static let burstAnimFps: Double = 8
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

    /// Live transient FX nodes (bursts, speed lines). Array-tracked —
    /// the activeBursts pattern — so `pauseActions()` can freeze each
    /// node's one-shot mid-flight for a coherent game-over frame and
    /// `reset()` can scrub them all. Entries self-evict when their
    /// action completes. `private(set)` for test assertions.
    private(set) var activeFX: [SKNode] = []

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
        let size = Tuning.Encounter.burstBaseSize * depthScale
            * (accepted ? 1.0 : Tuning.Encounter.burstAbsorbedScale)
        let burst = SKSpriteNode(texture: EncounterAnimations.snowballBurstFrames.first)
        burst.size = CGSize(width: size, height: size)
        burst.position = point
        burst.zPosition = Self.burstZPosition
        burst.name = "snowballBurst"
        if !accepted {
            // Softer pop for the blocked hit — the avatar's i-frame
            // flicker carries the "still invulnerable" message.
            burst.alpha = 0.8
        }
        parent.addChild(burst)
        let anim = SKAction.animate(
            with: EncounterAnimations.snowballBurstFrames,
            timePerFrame: 1.0 / Tuning.Encounter.burstAnimFps,
            resize: false, restore: false)
        runTracked(burst, .sequence([anim, .removeFromParent()]))
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
