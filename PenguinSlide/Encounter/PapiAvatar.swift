//
//  PapiAvatar.swift
//  PenguinSlide
//
//  The playable rear-view actor for the Snow Monster encounter
//  (penguinslide-gyu.11): Papi Penguin seen from behind, dodging
//  laterally at the camera plane (z = 0). The avatar is a VIEW + MOTION
//  shell only — hp / i-frames are NOT duplicated here. The existing
//  `Penguin` instance (hidden under `worldRoot` during the encounter)
//  remains the single source of truth: hits route through
//  `penguin.tryTakeHit(from:)`, the avatar listens to the same
//  `onHealthChanged` callback for hurt feedback, and i-frame state is
//  read back via `penguin.isInvulnerable` (one clock, one authority).
//
//  ## Motion doctrine (same as Penguin)
//
//  Lateral `worldX` is integrated by the shared `TiltSlideMotion`
//  integrator — the SAME ice-feel math as the normal-mode penguin,
//  reading the live `Tuning.Penguin` knobs every frame, so the settings
//  tilt-intensity slider changes dodge feel identically in both modes.
//  Position is written manually every frame through the DepthProjector
//  (no SKActions ever touch position — they'd race the writes, same
//  doctrine as Penguin); lean is the same spring recipe, bob the same
//  manual sine.
//
//  ## Knockback mapping (bead polish note 1)
//
//  `Penguin.tryTakeHit` applies its knockback impulse to the hidden
//  side-view penguin's own motion using the side-view node position —
//  both meaningless during the encounter. `takeHit(fromWorldX:)` keeps
//  tryTakeHit as the hp/i-frame authority but re-applies the SAME
//  impulse formula (`maxSpeed × knockbackImpulseScale`, direction away
//  from the ball) to the AVATAR's motion. The stray side-view vx side
//  effect is neutralized by the outro bead's penguin recenter.
//
//  ## Orchestrator contract (encounter system, gyu.13/.15)
//
//      begin()                   encounter entry: recenter worldX, reset
//                                motion, scrub visuals/actions.
//      update(dt:, tilt:)        every encounter frame, with the same
//                                `currentTilt()` value GameScene feeds
//                                the penguin in normal mode. Also ticks
//                                the penguin's hit clock (see
//                                Penguin.tickHitClock) — call ONLY while
//                                penguin.update is not running.
//      takeHit(fromWorldX:)      hit path: hp via the real Penguin,
//                                knockback onto the avatar.
//      setActionsPaused(_:)      game-over freeze seam (mirror of
//                                SnowMonster.setActionsPaused).
//      reset()                   restart hygiene: no leftover actions,
//                                tints, mirror, or rotation.
//
//  Construct ONCE, after GameScene wires `penguin.onHealthChanged` to
//  the HUD: the avatar chains onto that callback (calling the existing
//  downstream first), so repeated construction would stack chains.
//

import SpriteKit

final class PapiAvatar {

    /// Playback rate for the rear-slide loop — matches the 8 fps
    /// recorded for papi_penguin_rear_slide in spritecook-assets.json.
    static let animationFps: Double = 8

    /// Draw-order slot inside encounterRoot — the 50..59 band reserved
    /// for the avatar in EncounterWorld's z-stack doc (above monster and
    /// snowballs, below HUD accents).
    static let zPositionInEncounterRoot: CGFloat = 50

    /// Same corridor inset recipe as Penguin (`node.size.width * 0.42`)
    /// so the sprite never visually pokes through the lane edge.
    static let halfWidthFraction: CGFloat = 0.42

    private enum Keys {
        static let frames = "frames"
        static let hurtFlash = "hurtFlash"
        static let hurtSquash = "hurtSquash"
        static let death = "death"
    }

    // MARK: - State

    let node: SKSpriteNode
    private let projector: DepthProjector
    /// The REAL player state authority (hidden during the encounter).
    private let penguin: Penguin

    /// Shared tilt→velocity integrator — identical dynamics to the
    /// normal-mode penguin by construction (penguinslide-gyu.3).
    private var motion: TiltSlideMotion
    var vx: CGFloat { motion.vx }

    /// Lateral position in world units (≡ screen points at z = 0 — the
    /// projection is the lateral identity at the camera plane). The
    /// snowball system's aim/hit math reads this.
    private(set) var worldX: CGFloat

    /// The projector's depth scale at the avatar's station — exactly
    /// 1.0 at today's z = 0 plane. The FX bead (gyu.16) sizes the
    /// snow-splat burst by this so the splat stays proportioned to the
    /// avatar if it ever moves off the camera plane.
    var depthScale: CGFloat {
        projector.project(worldX: worldX, z: 0).scale
    }

    private var bobPhase: TimeInterval = 0
    private var leanVelocity: CGFloat = 0
    /// Local clock for the i-frame flicker phase only — the i-frame
    /// *window* itself is the penguin's clock (penguin.isInvulnerable).
    private var elapsed: TimeInterval = 0
    /// Dodge-accent mirror: +1 faces the unmirrored sheet, −1 mirrors
    /// via xScale (per the asset decision: lean frames are baked into
    /// the loop, no separate dodge sheet). +1 = dodging right;
    /// recalibrate on art swaps if the sheet's baked lean flips.
    private var facing: CGFloat = 1
    /// Last hp seen through onHealthChanged, so hurt feedback fires only
    /// on decreases (reset() pushes hp back UP through the same callback).
    private var lastKnownHp: Int

    // MARK: - Init

    /// Builds the sprite and parents it to `parent` (encounterRoot).
    /// Spawns centered on the corridor (the projector's vanishing lane).
    init(parent: SKNode, projector: DepthProjector, penguin: Penguin) {
        self.projector = projector
        self.penguin = penguin
        self.lastKnownHp = penguin.hp
        self.worldX = projector.vanishingX
        self.motion = TiltSlideMotion(
            leftBound: projector.vanishingX - Tuning.Encounter.papiLateralRange,
            rightBound: projector.vanishingX + Tuning.Encounter.papiLateralRange
        )

        let size = Tuning.Encounter.papiBaseSize
        let sprite = SKSpriteNode(texture: EncounterAnimations.papiSlideFrames[0],
                                  size: CGSize(width: size, height: size))
        // Bottom-center anchor, same convention as SnowMonster: the
        // projected point is the ground station, feet sit on it. Also
        // keeps the hurt squash planted and pivots the lean at the feet.
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        sprite.position = projector.project(worldX: projector.vanishingX, z: 0).point
        sprite.zPosition = Self.zPositionInEncounterRoot
        parent.addChild(sprite)
        self.node = sprite

        // HP proxy: chain onto the penguin's health callback (GameScene
        // already wired the HUD — keep it firing first) so an accepted
        // hit plays hurt feedback here no matter who called tryTakeHit.
        let downstream = penguin.onHealthChanged
        penguin.onHealthChanged = { [weak self] hp in
            downstream?(hp)
            self?.noteHealthChanged(hp)
        }

        startAnimation(.papiSlide)
    }

    // MARK: - Per-frame tick

    /// `tilt` is the same `currentTilt()` value in [-1, 1] that drives
    /// the penguin in normal mode — MotionInjector / keyboard fallbacks
    /// flow through untouched, so sim tilt injection works identically.
    func update(dt: TimeInterval, tilt: CGFloat) {
        elapsed += dt
        // Keep the penguin's hit/i-frame clock real-time while its own
        // update isn't running (it's hidden) — i-frames armed by a
        // snowball hit must expire on the same schedule as normal mode.
        penguin.tickHitClock(dt: dt)

        // Shared ice-feel velocity step + corridor clamp (zeroing vx at
        // the wall so full tilt holds the edge without jitter). worldX
        // stays owned here; the integrator returns the new value.
        motion.update(dt: dt, tilt: tilt)
        worldX = motion.integrate(x: worldX,
                                  dt: dt,
                                  halfWidth: node.size.width * Self.halfWidthFraction)

        // Manual bob (Penguin's recipe — no SKAction may touch position)
        // layered on the projected ground station.
        bobPhase += dt
        let bobY = sin(bobPhase * 5.2) * 3.0
        let projected = projector.project(worldX: worldX, z: 0)
        node.position = CGPoint(x: projected.point.x, y: projected.point.y + bobY)

        // Spring-damped lean — Penguin's exact recipe and knobs. The
        // sign convention (top tips toward the movement direction)
        // reads correctly from behind too: dodging right leans right.
        // The target amplitude is trimmed by Tuning.Encounter.papiLeanScale
        // (gyu.26): the final rear-slide sheet bakes subtle lean frames
        // into the loop, so the full side-view angle on top of the baked
        // lean over-rotates. Same spring, scaled target — never forked.
        let leanTarget = -(vx / Tuning.Penguin.maxSpeed)
            * Tuning.Penguin.leanMaxAngle
            * Tuning.Encounter.papiLeanScale
        let leanError = leanTarget - node.zRotation
        let leanOmega = sqrt(Tuning.Penguin.leanStiffness)
        let leanAccel = Tuning.Penguin.leanStiffness * leanError
            - 2 * leanOmega * Tuning.Penguin.leanDampingRatio * leanVelocity
        leanVelocity += leanAccel * CGFloat(dt)
        node.zRotation += leanVelocity * CGFloat(dt)

        // Dodge accent: mirror the rear-slide sheet toward the dodge
        // direction once |vx| reads as deliberate motion (same threshold
        // that separates idle from slide in normal mode). The sign write
        // preserves the current magnitude so it composes with the hurt
        // squash; it pauses while the squash action owns the scale so
        // the two never fight within a frame.
        if abs(vx) >= Tuning.Penguin.idleSlideThresholdPtPerSec {
            facing = vx >= 0 ? 1 : -1
        }
        if node.action(forKey: Keys.hurtSquash) == nil {
            node.xScale = facing * abs(node.xScale)
        }

        // I-frame visuals: alpha flicker on the avatar reading the SAME
        // live knobs as the penguin's flicker. The window is the
        // penguin's authoritative clock; only the flicker phase is local.
        if penguin.isInvulnerable {
            let lit = sin(elapsed * 2 * .pi * TimeInterval(Tuning.Penguin.iFrameFlashHz)) > 0
            node.alpha = lit ? 1.0 : Tuning.Penguin.iFrameDimAlpha
        } else if node.alpha != 1.0 {
            node.alpha = 1.0
        }
    }

    // MARK: - Hit path (encounter system seam)

    /// Land a snowball hit. hp / i-frame gating is fully delegated to
    /// the REAL penguin's `tryTakeHit` (single authority — a hit during
    /// active i-frames is absorbed there: no HP change, no callback, no
    /// double hurt anim). `ballWorldX` is the ball's lateral world
    /// coordinate, which at z = 0 IS the projected scene x, satisfying
    /// tryTakeHit's impactX contract directly.
    ///
    /// On an accepted hit the knockback impulse is re-applied to the
    /// avatar's own motion — same formula as Penguin's, direction away
    /// from the ball — because tryTakeHit's impulse landed on the hidden
    /// side-view motion (see header: knockback mapping).
    /// Returns whether HP was actually decremented.
    @discardableResult
    func takeHit(fromWorldX ballWorldX: CGFloat) -> Bool {
        guard penguin.tryTakeHit(from: ballWorldX) else { return false }
        let dir: CGFloat = worldX >= ballWorldX ? 1 : -1
        motion.applyImpulse(direction: dir)
        return true
    }

    /// Hurt feedback on hp DECREASE only — `onHealthChanged` also fires
    /// on `Penguin.reset()` (hp restored to max), which must not flash.
    private func noteHealthChanged(_ hp: Int) {
        if hp < lastKnownHp {
            playHurtFeedback()
        }
        lastKnownHp = hp
    }

    /// Red flash + squash — Penguin.triggerHurtAnimation's recipe,
    /// copied (not shared: the avatar is a separate node and the bead
    /// spec calls for the recipe, not the class). The squash is
    /// sign-aware so it preserves the dodge mirror instead of snapping
    /// the sprite to unmirrored mid-recoil.
    private func playHurtFeedback() {
        node.removeAction(forKey: Keys.hurtFlash)
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
        node.run(.sequence([flashIn, flashOut, clear]), withKey: Keys.hurtFlash)

        node.removeAction(forKey: Keys.hurtSquash)
        let sign = facing
        node.run(.sequence([
            .group([.scaleX(to: 0.92 * sign, duration: 0.05),
                    .scaleY(to: 0.92, duration: 0.05)]),
            .wait(forDuration: 0.05),
            .group([.scaleX(to: 1.0 * sign, duration: 0.12),
                    .scaleY(to: 1.0, duration: 0.12)])
        ]), withKey: Keys.hurtSquash)
    }

    /// Death visuals for an encounter death (penguinslide-gyu.19) —
    /// `Penguin.triggerDeathAnimation`'s exact recipe (scale-down, fade,
    /// tip) replayed on the REAR-VIEW node, because the side-view penguin
    /// is hidden mid-encounter and its own death anim would play
    /// invisibly. GameScene's game-over freeze deliberately leaves this
    /// node UNPAUSED (`encounterSystem.pauseActions()` covers the monster
    /// and balls, never the avatar), so the tip plays over the frozen
    /// encounter world exactly like the side-view death plays over the
    /// frozen icicle field. GameScene stops calling `update()` after
    /// game-over, so nothing restarts "frames" or fights the alpha/scale
    /// until `reset()` (restart) scrubs everything.
    ///
    /// The scale step is sign-aware (Penguin uses `.scale(to:)`, but the
    /// avatar mirrors its dodge lean via xScale) so a death mid-dodge
    /// keeps facing its last direction instead of snapping unmirrored.
    func triggerDeathAnimation() {
        node.removeAction(forKey: Keys.hurtSquash)
        // Freeze the rear-slide loop so the death pose isn't undercut by
        // a flipper still waving (Penguin's comment, same rationale).
        node.removeAction(forKey: Keys.frames)
        let sign = facing
        node.run(.sequence([
            .group([
                .scaleX(to: 0.9 * sign, duration: 0.1),
                .scaleY(to: 0.9, duration: 0.1),
                .fadeAlpha(to: 0.6, duration: 0.1)
            ]),
            .rotate(byAngle: .pi / 6, duration: 0.2)
        ]), withKey: Keys.death)
    }

    // MARK: - Lifecycle

    /// Encounter-entry seam: recenter worldX on the corridor, zero the
    /// motion, and scrub any leftover visual state from a previous
    /// encounter (tints, mirror, rotation, pending actions).
    func begin() {
        reset()
    }

    /// Freeze/unfreeze the avatar's SKActions (hurt flash/squash, the
    /// slide loop) — the encounter system's game-over `pauseActions()`
    /// routes here, mirroring SnowMonster.setActionsPaused.
    func setActionsPaused(_ paused: Bool) {
        node.isPaused = paused
    }

    /// Back to a clean centered slide: no leftover actions, tints,
    /// mirror, rotation, or alpha dim. Safe from any state (encounter
    /// exit, restart after death). Does NOT touch the penguin — hp
    /// restoration is GameScene.restart()'s `penguin.reset()` business.
    func reset() {
        node.removeAllActions()
        node.isPaused = false
        worldX = projector.vanishingX
        motion.reset()
        bobPhase = 0
        leanVelocity = 0
        elapsed = 0
        facing = 1
        node.position = projector.project(worldX: worldX, z: 0).point
        node.alpha = 1
        node.xScale = 1
        node.yScale = 1
        node.zRotation = 0
        node.colorBlendFactor = 0
        lastKnownHp = penguin.hp
        // removeAllActions killed the "frames" loop — restart it so a
        // fresh encounter animates from frame zero (Penguin.reset's
        // pattern).
        startAnimation(.papiSlide)
    }

    // MARK: - Private

    /// Keyed clip swap — Penguin's startAnimation pattern: one "frames"
    /// key, remove-then-run, loop decided by EncounterAnimations.loops.
    private func startAnimation(_ animState: EncounterAnimState) {
        node.removeAction(forKey: Keys.frames)
        let frames = EncounterAnimations.frames(for: animState)
        let perFrame = 1.0 / Self.animationFps
        let animate = SKAction.animate(with: frames,
                                       timePerFrame: perFrame,
                                       resize: false,
                                       restore: false)
        if EncounterAnimations.loops(animState) {
            node.run(.repeatForever(animate), withKey: Keys.frames)
        } else {
            node.run(animate, withKey: Keys.frames)
        }
    }
}
