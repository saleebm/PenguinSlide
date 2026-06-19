//
//  SnowMonster.swift
//  PenguinSlide
//
//  The Snow Monster boss actor for the encounter mode
//  (penguinslide-gyu.12): a snowman-like monster standing at the
//  `Tuning.Encounter.zMonster` depth station, positioned and scaled by
//  the DepthProjector so it agrees with the rest of the encounter
//  geometry. Sprite frames come from EncounterAnimations (SpriteCook
//  sheets); animation swaps use the same keyed startAnimation pattern
//  as Penguin (one "frames" key, removeAction-then-run, loops map).
//
//  ## Cycle contract (volley orchestration seam — penguinslide-gyu.15)
//
//  The monster owns no timing policy: the encounter system DRIVES the
//  cycle by calling the transition methods, and the actor guards
//  illegal sequences (each returns false when rejected):
//
//      roar(completion:)            .idle → .roaring → .idle
//                                   one-shot at encounter intro; cannot
//                                   interrupt the throw cycle.
//      telegraph(duration:completion:)
//                                   .idle → .telegraph
//                                   THE player's reaction cue (same
//                                   gameplay role as the icicle crack
//                                   warning): wind-up pose + warning
//                                   pulse for `duration` (default
//                                   Tuning.Encounter.telegraphDuration).
//                                   `completion` fires when the pulse
//                                   ends; the state HOLDS at .telegraph
//                                   until the orchestrator commits the
//                                   throw.
//      throwSnowball(onRelease:completion:)
//                                   .idle/.telegraph → .throwing → .idle
//                                   `onRelease` fires exactly when the
//                                   ball leaves the hand (see release
//                                   constants below) — the snowball
//                                   system (.13) spawns its projectile
//                                   there, at (snowballSpawnWorldX,
//                                   zMonster), visually anchored at
//                                   snowballSpawnPoint().
//      melt(duration:completion:)   any non-melting state → .melting
//                                   win-outro one-shot (gyu.18): slumps
//                                   slowly into a snow puddle, holds
//                                   the final frame; terminal until
//                                   reset().
//      setLane(worldX:animated:) / shuffleLane(using:)
//                                   optional lateral repositioning
//                                   between throws; shuffleLane is
//                                   gated by the
//                                   Tuning.Encounter.monsterShuffle*
//                                   knobs (DEFAULT OFF for v1).
//      reset()                      any state → .idle, home lane, all
//                                   actions/pending callbacks cancelled.
//      setActionsPaused(_:)         freeze/unfreeze the actor's
//                                   SKActions — the encounter system's
//                                   pauseActions() (game-over freeze,
//                                   mirroring pauseShardActions) routes
//                                   here.
//
//  All node content parents under the SKNode passed to `init` —
//  GameScene's `encounterRoot` in practice — so show/hide of the
//  encounter world carries the monster for free.
//

import SpriteKit

/// Boss-cycle states. Read-only outside the actor; all mutations go
/// through the guarded transition methods so sequencing is auditable.
enum SnowMonsterState: Equatable {
    case idle
    case telegraph
    case throwing
    case roaring
    /// Win-outro terminal state (penguinslide-gyu.18): slumping into the
    /// snow puddle. Only `reset()` leaves it.
    case melting
}

final class SnowMonster {

    // MARK: - Animation/release constants
    //
    // The frame COUNTS live in EncounterAnimations (the manifest
    // contract with spritecook-assets.json); the release timing below
    // is this actor's contract with the snowball system (.13) and must
    // be re-checked against the throw sheet whenever the art is
    // swapped (penguinslide-gyu.24).

    /// Playback rate for every monster clip — matches the 8 fps
    /// recorded for the snow_monster_* sheets in spritecook-assets.json.
    static let animationFps: Double = 8

    /// Throw-clip frame index (0-based) at which the snowball leaves
    /// the hand: `onRelease` fires when this frame begins. Calibrated
    /// against the delivered SpriteCook sheet (penguinslide-gyu.24,
    /// sha12 ddb4e56b4da9): wind-up/gather frames 0–5, ball raised and
    /// cocked in-hand on 6–7, departure smear on 8, follow-through 9.
    /// Art-dependent; recalibrate on art swaps.
    static let throwReleaseFrameIndex = 8

    /// Seconds from throw start to the release moment
    /// (`throwReleaseFrameIndex / animationFps`); exposed so the
    /// snowball system can pre-compute flight schedules without
    /// observing the callback.
    static var throwReleaseTime: TimeInterval {
        Double(throwReleaseFrameIndex) / animationFps
    }

    /// Hand position as a fraction of the (unscaled) sprite footprint,
    /// measured from the bottom-center anchor: x is lateral offset,
    /// y is height above the feet. Calibrated against the delivered
    /// throw sheet (penguinslide-gyu.24): last in-hand frame (index 7)
    /// holds the ball high in the viewer-left hand, ball center ≈
    /// (13, 74) of the 88×88 frame → x = (13−44)/88, y = 74/88.
    /// Art-dependent; recalibrate on swaps.
    static let handOffsetFraction = CGPoint(x: -0.35, y: 0.84)

    /// Warning-pulse rate during the telegraph wind-up.
    private static let telegraphPulseHz: Double = 3

    /// Draw-order slot inside encounterRoot. Convention for the
    /// encounter z-stack: backdrop/ground (.10) < monster (this) <
    /// snowballs (.13, sorted above this by depth) < Papi (.11) < HUD.
    static let zPositionInEncounterRoot: CGFloat = 10

    private enum Keys {
        static let frames = "frames"
        static let telegraph = "telegraph"
        static let shuffle = "shuffle"
    }

    // MARK: - State

    let node: SKSpriteNode
    private let projector: DepthProjector

    private(set) var state: SnowMonsterState = .idle

    /// Current lane in world units (camera-plane points — the same
    /// coordinate space as Papi's corridor and snowball aim math).
    private(set) var laneWorldX: CGFloat
    private let homeWorldX: CGFloat

    /// Projector scale at the monster's fixed depth station. Depth
    /// never changes, so this is computed once; telegraph's scale
    /// breathe multiplies against it.
    private let baseScale: CGFloat

    // MARK: - Init

    /// Builds the sprite and parents it to `parent` (encounterRoot).
    /// `worldX` defaults to the projector's vanishing-point lane
    /// (screen center) — the canonical home lane.
    init(parent: SKNode, projector: DepthProjector, worldX: CGFloat? = nil) {
        self.projector = projector
        let lane = worldX ?? projector.vanishingX
        self.homeWorldX = lane
        self.laneWorldX = lane

        let projected = projector.project(worldX: lane, z: Tuning.Encounter.zMonster)
        self.baseScale = projected.scale

        let size = Tuning.Encounter.monsterBaseSize
        let sprite = SKSpriteNode(texture: EncounterAnimations.monsterIdleFrames[0],
                                  size: CGSize(width: size, height: size))
        // Bottom-center anchor: the projected point is the monster's
        // ground station, so its feet sit exactly on the projector's
        // ground line and the body rises toward the horizon.
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        sprite.position = projected.point
        sprite.setScale(projected.scale)
        sprite.zPosition = Self.zPositionInEncounterRoot
        parent.addChild(sprite)
        self.node = sprite

        startAnimation(.monsterIdle)
    }

    // MARK: - Cycle transitions (orchestrator-driven)

    /// Intro one-shot: roar clip, then back to the idle loop. Rejected
    /// outside `.idle` so it can never disturb a telegraph/throw in
    /// flight. `completion` fires when the clip ends (cancelled by
    /// `reset()`).
    @discardableResult
    func roar(completion: (() -> Void)? = nil) -> Bool {
        guard state == .idle else { return false }
        state = .roaring

        node.removeAction(forKey: Keys.frames)
        let perFrame = 1.0 / Self.animationFps
        let clip = SKAction.animate(with: EncounterAnimations.monsterRoarFrames,
                                    timePerFrame: perFrame,
                                    resize: false,
                                    restore: false)
        node.run(.sequence([
            clip,
            .run { [weak self] in
                guard let self else { return }
                self.state = .idle
                self.startAnimation(.monsterIdle)
                completion?()
            }
        ]), withKey: Keys.frames)
        return true
    }

    /// Wind-up the player reads before every throw — duration defaults
    /// to the `Tuning.Encounter.telegraphDuration` knob (overridable
    /// for future volley variants). Holds the first throw frame and
    /// pulses a warning tint + slight scale breathe. `completion`
    /// fires when the pulse finishes; the actor then HOLDS `.telegraph`
    /// (steady tint) until the orchestrator calls `throwSnowball`.
    @discardableResult
    func telegraph(duration: TimeInterval = Tuning.Encounter.telegraphDuration,
                   completion: (() -> Void)? = nil) -> Bool {
        guard state == .idle else { return false }
        state = .telegraph

        node.removeAction(forKey: Keys.frames)
        // Wind-up pose: first frame of the throw clip, held for the
        // whole telegraph so the silhouette change itself is a cue.
        node.texture = EncounterAnimations.monsterThrowFrames[0]
        node.color = .red

        let baseScale = self.baseScale
        let pulse = SKAction.customAction(withDuration: duration) { node, t in
            guard let sprite = node as? SKSpriteNode else { return }
            // Half-rectified sine: tint and size surge together at
            // telegraphPulseHz, dropping back to the floor in between —
            // reads as "inhaling" even at the far-depth 0.25 scale.
            let phase = max(0, sin(Double(t) * 2 * .pi * Self.telegraphPulseHz))
            sprite.colorBlendFactor = 0.25 + 0.20 * CGFloat(phase)
            sprite.setScale(baseScale * (1 + 0.06 * CGFloat(phase)))
        }
        node.run(.sequence([
            pulse,
            .run { [weak self] in
                guard let self else { return }
                // Hold a steady warning tint while waiting for the
                // throw commit so there's no pop between the pulse
                // ending and the orchestrator's throw call.
                self.node.colorBlendFactor = 0.25
                self.node.setScale(baseScale)
                completion?()
            }
        ]), withKey: Keys.telegraph)
        return true
    }

    /// Commit the throw. Legal from `.telegraph` (the normal cycle) or
    /// straight from `.idle` (orchestrator variants that skip the
    /// wind-up). `onRelease` fires exactly when frame
    /// `throwReleaseFrameIndex` begins — the moment the ball should
    /// appear at the hands; the snowball system spawns its projectile
    /// at `(snowballSpawnWorldX, zMonster)` / `snowballSpawnPoint()`.
    /// `completion` fires when the follow-through ends and the monster
    /// is back in the idle loop. Both are cancelled by `reset()`.
    @discardableResult
    func throwSnowball(onRelease: @escaping () -> Void,
                       completion: (() -> Void)? = nil) -> Bool {
        guard state == .idle || state == .telegraph else { return false }
        state = .throwing

        // Clear telegraph leftovers (tint / scale breathe / hold).
        node.removeAction(forKey: Keys.telegraph)
        node.colorBlendFactor = 0
        node.setScale(baseScale)

        node.removeAction(forKey: Keys.frames)
        let frames = EncounterAnimations.monsterThrowFrames
        let perFrame = 1.0 / Self.animationFps
        let windUp = SKAction.animate(with: Array(frames[0..<Self.throwReleaseFrameIndex]),
                                      timePerFrame: perFrame,
                                      resize: false,
                                      restore: false)
        let followThrough = SKAction.animate(with: Array(frames[Self.throwReleaseFrameIndex...]),
                                             timePerFrame: perFrame,
                                             resize: false,
                                             restore: false)
        // Splitting the clip at the release frame makes the callback
        // frame-exact by construction — no wait-timer drift against
        // the animation.
        node.run(.sequence([
            windUp,
            .run(onRelease),
            followThrough,
            .run { [weak self] in
                guard let self else { return }
                self.state = .idle
                self.startAnimation(.monsterIdle)
                completion?()
            }
        ]), withKey: Keys.frames)
        return true
    }

    /// Win-outro one-shot (penguinslide-gyu.18 amendment): the defeated
    /// monster melts SLOWLY into a snow puddle — the outro's exit back to
    /// the side view waits for this beat. Legal from ANY non-melting
    /// state (the volley is already over; whatever clip is mid-flight —
    /// idle loop, a stale telegraph hold, a follow-through — is cancelled
    /// outright). Terminal until `reset()`: every other transition guard
    /// rejects `.melting`, so a melted monster can never telegraph or
    /// throw again before the per-entry scrub.
    ///
    /// The SnowMonsterMelt sheet is STRETCHED across `duration`
    /// (timePerFrame = duration / frameCount) instead of running at the
    /// fixed `animationFps` — the melt length is the
    /// `Tuning.Encounter.meltDuration` knob's contract, independent of
    /// the sheet's frame count, so the SpriteCook swap-in
    /// (penguinslide-6m5) is a pure asset swap. The clip HOLDS its final
    /// puddle frame (restore: false; no idle restart) until `reset()`.
    /// `completion` fires when the clip ends — a visuals-only seam
    /// (cancelled by `reset()`); GameScene's outro timeline is dt-driven
    /// and never waits on it.
    @discardableResult
    func melt(duration: TimeInterval = Tuning.Encounter.meltDuration,
              completion: (() -> Void)? = nil) -> Bool {
        guard state != .melting else { return false }
        state = .melting

        // Scrub telegraph leftovers (tint / scale breathe / hold) so the
        // melt plays clean from the base silhouette.
        node.removeAction(forKey: Keys.telegraph)
        node.colorBlendFactor = 0
        node.setScale(baseScale)

        node.removeAction(forKey: Keys.frames)
        let frames = EncounterAnimations.monsterMeltFrames
        let perFrame = duration / Double(frames.count)
        let clip = SKAction.animate(with: frames,
                                    timePerFrame: perFrame,
                                    resize: false,
                                    restore: false)
        node.run(.sequence([
            clip,
            .run { completion?() }
        ]), withKey: Keys.frames)
        return true
    }

    // MARK: - Lane control (optional variety; knob-gated)

    /// Slide to a new lane (world units). Legal only from `.idle` so a
    /// telegraph always happens from a settled position the player can
    /// read. `animated: false` snaps (used by reset).
    @discardableResult
    func setLane(worldX: CGFloat, animated: Bool = true) -> Bool {
        guard state == .idle else { return false }
        laneWorldX = worldX
        let target = projector.project(worldX: worldX, z: Tuning.Encounter.zMonster).point
        node.removeAction(forKey: Keys.shuffle)
        if animated {
            let move = SKAction.move(to: target,
                                     duration: Tuning.Encounter.monsterShuffleDuration)
            move.timingMode = .easeInEaseOut
            node.run(move, withKey: Keys.shuffle)
        } else {
            node.position = target
        }
        return true
    }

    /// Random lane shuffle within ±`monsterShuffleRange` of the home
    /// lane. No-ops (returns false) while the
    /// `Tuning.Encounter.monsterShuffleEnabled` knob is off — the v1
    /// fairness-tuning default.
    @discardableResult
    func shuffleLane(using rng: inout any RandomNumberGenerator) -> Bool {
        guard Tuning.Encounter.monsterShuffleEnabled else { return false }
        let range = Tuning.Encounter.monsterShuffleRange
        let offset = CGFloat.random(in: -range...range, using: &rng)
        return setLane(worldX: homeWorldX + offset)
    }

    // MARK: - Snowball spawn seam (.13)

    /// World-space lateral coordinate of the throwing hand — where the
    /// snowball model should begin its flight (z = `snowballSpawnZ`).
    var snowballSpawnWorldX: CGFloat {
        laneWorldX + Self.handOffsetFraction.x * Tuning.Encounter.monsterBaseSize
    }

    /// Depth station the snowball spawns at (the monster's plane).
    var snowballSpawnZ: CGFloat { Tuning.Encounter.zMonster }

    /// Screen-space point (in the monster's parent — encounterRoot —
    /// coordinates) where the ball should visually appear at release:
    /// the hand, offset from the feet anchor by the scaled hand
    /// fraction. Note the projector's own y for (spawnWorldX, zMonster)
    /// is the GROUND line at that depth; the hand rides above it, so
    /// the snowball system should anchor its visual spawn here and let
    /// the projected trajectory take over as z integrates.
    func snowballSpawnPoint() -> CGPoint {
        let onScreenSize = Tuning.Encounter.monsterBaseSize * baseScale
        return CGPoint(x: node.position.x + Self.handOffsetFraction.x * onScreenSize,
                       y: node.position.y + Self.handOffsetFraction.y * onScreenSize)
    }

    // MARK: - Lifecycle

    /// Freeze/unfreeze every running clip and pulse — the encounter
    /// system's game-over `pauseActions()` (mirror of
    /// `pauseShardActions`) and settings-pause handling route here.
    func setActionsPaused(_ paused: Bool) {
        node.isPaused = paused
    }

    /// Back to a clean idle: home lane, no tint, base scale, idle loop
    /// from frame zero. Cancels all keyed actions, which also cancels
    /// any pending onRelease/completion callbacks — safe to call from
    /// any state (encounter exit, restart after death).
    func reset() {
        node.removeAllActions()
        node.isPaused = false
        state = .idle
        laneWorldX = homeWorldX
        node.position = projector.project(worldX: homeWorldX,
                                          z: Tuning.Encounter.zMonster).point
        node.colorBlendFactor = 0
        node.setScale(baseScale)
        startAnimation(.monsterIdle)
    }

    // MARK: - Private

    /// Keyed clip swap — Penguin's startAnimation pattern: one
    /// "frames" key, remove-then-run, loop decided by the
    /// EncounterAnimations loops map. One-shot sequencing (state
    /// restore, completions) is owned by the callers above because
    /// each one-shot carries its own callback contract.
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
