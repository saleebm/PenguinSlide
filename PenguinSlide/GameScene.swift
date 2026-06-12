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

/// Outcome of a finished round, handed to the SwiftUI game-over page.
struct GameResult {
    let score: Int
    /// True when this run beat the previously stored best, so the page can
    /// celebrate it. Computed against `best_score` before it's overwritten.
    let isNewBest: Bool
}

final class GameScene: SKScene, SKPhysicsContactDelegate {

    /// Fired once per round when the penguin dies. ContentView listens and
    /// presents the game-over page; the scene stays frozen underneath until
    /// `playAgain()` is called. Set by ContentView right after construction.
    var onGameOver: ((GameResult) -> Void)?

    private let motionManager = CMMotionManager()
    private var gameCamera: SKCameraNode!

    private var penguin: Penguin!
    private var icicles: IcicleSystem!
    private var hud: HUDController!
    /// Encounter-mode presentation (penguinslide-gyu.20): intro banner,
    /// volley progress, win outcome banner. Scene-level like `hud` — its
    /// nodes are direct scene children (never under worldRoot or
    /// encounterRoot) so banners keep playing while the roots swap.
    private var encounterHUD: EncounterHUD!
    /// Balls RESOLVED (hit or dodged) in the current volley — feeds the
    /// EncounterHUD progress counter. Reset on .encounter entry.
    private var encounterResolvedCount = 0

    // MARK: - World containers (penguinslide-gyu.9)

    /// Parent of the ENTIRE side-view world: sky backdrop, water, ice strip,
    /// cracks, the penguin, and every icicle/shadow/shard/burst/puff
    /// IcicleSystem spawns. Entering the encounter hides this as ONE toggle
    /// (and the outro shows it again) — never a node-by-node scavenger hunt.
    /// HUD, camera, audio nodes, and the #if DEBUG labels stay at scene level:
    /// HUD/debug labels must be visible in every phase, the camera is
    /// mode-agnostic, and audio nodes must not inherit a container's
    /// isPaused (SKAudioNode actions would freeze mid-clip).
    private let worldRoot = SKNode()
    /// Parent of all encounter content — the encounter world-builder and
    /// actor beads (gyu.10 EncounterWorld, .11 PapiAvatar, .12 SnowMonster)
    /// parent into this. Starts hidden AND paused so zero encounter work
    /// (rendering or SKActions) runs while in .normal; the intro/outro
    /// choreography owns the show/hide + pause flips. Both containers sit at
    /// zPosition 0, so children keep the same effective draw order they had
    /// as direct scene children.
    private let encounterRoot = SKNode()
    // Encounter subsystem seam — the real orchestrator lives in
    // PenguinSlide/Encounter/SnowMonsterEncounterSystem.swift (gyu.13);
    // the intro wiring (gyu.17) attaches world/actor seams via
    // `ensureEncounterContent`.
    private let encounterSystem = SnowMonsterEncounterSystem()

    // MARK: - Encounter content (penguinslide-gyu.17)

    // Built ONCE, lazily, at the first intro's midpoint swap
    // (`ensureEncounterContent`), then recycled across encounters via
    // reset()/begin(): EncounterWorld pools its band/speed-line nodes, and
    // PapiAvatar chains onto `penguin.onHealthChanged` at construction —
    // re-constructing it would stack the chain (its header contract).
    private var encounterWorld: EncounterWorld?
    private var papiAvatar: PapiAvatar?
    private var snowMonster: SnowMonster?
    /// Impact/dodge FX helper (penguinslide-gyu.16): snow-splat burst,
    /// dodge whoosh accent, pooled haptics, hit shake. Built alongside
    /// the other encounter content; transient nodes are pause-registered
    /// in triggerGameOver and scrubbed by endEncounterPresentation.
    private var encounterFX: EncounterFX?

    /// Random-encounter scheduler (penguinslide-gyu.5/.17). Fed once per
    /// `.normal` frame with the eligibility predicate + live score;
    /// `restart()` re-arms it. The settings-armed entry and the
    /// debugForceEncounter hook never touch it (they bypass the random
    /// cadence AND its score-bracket gate by construction).
    private var encounterTrigger = EncounterTrigger()

    /// One-shot guard for the intro timeline's midpoint world swap, so a
    /// frame hitch that jumps the timeline past 0.5 progress still swaps
    /// exactly once (and before the same frame's completion check).
    private var introSwapDone = false

    /// One-shot guard for the OUTRO crossfade's midpoint world restore
    /// (penguinslide-gyu.18) — introSwapDone's mirror, with the same
    /// giant-dt-frame guarantee. Re-armed by beginOutroPresentation()
    /// and scrubbed by endEncounterPresentation() (restart mid-outro).
    private var outroSwapDone = false

    /// Fullscreen white snow-flash for the intro crossfade — the
    /// triggerDeathFlash recipe as a PERSISTENT, manually-driven sprite
    /// (deliberately NOT the death flash itself, and no SKAction: alpha is
    /// written from the dt-accumulated intro timeline each frame, so the
    /// crossfade is interrupt-safe — settings/app-background mid-intro
    /// freeze it and resume exactly where it left off). Scene-level child:
    /// it must cover BOTH roots while they swap underneath it.
    private var introFlash: SKSpriteNode?

    private var lastUpdateTime: TimeInterval = 0
    /// Wall-clock-ish scene time: advances every started frame regardless of
    /// phase. Animation/FX may key off it, but it must NOT drive difficulty
    /// or income — that's `gameplayElapsed`'s job.
    private var elapsed: TimeInterval = 0
    /// The gameplay clock (plan A6, penguinslide-gyu.2): advances ONLY while
    /// `phase == .normal`. Both the survival-score drip and the icicle
    /// difficulty ramp (`IcicleSystem.progress`) read this clock, so an
    /// encounter freezes them in place — the player returns to exactly the
    /// cadence/gravity/income they left, and encounter income comes solely
    /// from dodge/volley bonuses (`bonusPoints`).
    private var gameplayElapsed: TimeInterval = 0

    // Cached game-over sound. Paired with the existing .error haptic in
    // triggerGameOver(). IcicleSystem owns the shatter and crack sounds.
    private let gameOverSound = SKAction.playSoundFileNamed("game_over.caf",
                                                             waitForCompletion: false)

    // Looping ambient bed. Volume sits well under the SFX so impacts cut
    // through; the node is pause/resume-controlled on app lifecycle so it
    // doesn't keep playing in the background.
    private var bgMusic: SKAudioNode?
    /// The bed's baseline volume — shared by the didMove setup and the
    /// outro's restore seam (penguinslide-gyu.18/.28: the audio bead ducks
    /// at intro; the outro restores to this baseline).
    private static let bgMusicVolume: Float = 0.18
    /// The bed's INTENDED volume right now — the baseline in normal play,
    /// `Tuning.Encounter.bgDuckVolume` from intro start until the outro /
    /// death / restart restore (penguinslide-gyu.28). Lifecycle pause and
    /// resume must preserve the duck (a settings sheet opened mid-encounter
    /// resumes at the DUCKED level), so the resume paths re-assert THIS
    /// value instead of blindly restoring the baseline. Written only by
    /// `setBgMusicVolume(_:ramp:)`.
    private var bgMusicTargetVolume: Float = GameScene.bgMusicVolume
    /// `run(_:withKey:)` key for every bed/ambience volume ramp, so a new
    /// ramp REPLACES any in-flight one — two concurrent changeVolume
    /// actions on one node fight each other frame-by-frame.
    private static let volumeActionKey = "volumeRamp"

    /// Encounter ambience loop (penguinslide-gyu.28): plays under the
    /// encounter from intro start until the outro restore / encounter
    /// death / restart, filling the room the ducked bed vacates. nil when
    /// encounter_ambience.caf isn't bundled (silent-but-safe, same guard
    /// discipline as the stings below).
    private var encounterAmbience: SKAudioNode?
    /// Whether the ambience SHOULD be audible right now. The lifecycle
    /// resume paths re-play the loop only while this is set, so an
    /// app-background mid-encounter comes back with ambience, and a
    /// settings cycle in normal play never wakes it.
    private var encounterAmbienceActive = false

    // Encounter boundary stings (penguinslide-gyu.28), cached like
    // gameOverSound. File-presence-guarded: SKAction.playSoundFileNamed
    // traps at action-creation time when the resource is missing, and the
    // staged ElevenLabs audio may not be delivered on every checkout —
    // an absent file means a nil action and a silent-but-safe build (the
    // gyu.27 SFX discipline).
    private let encounterStingSound = GameScene.guardedOneShot("encounter_sting.caf")
    private let encounterWinSound = GameScene.guardedOneShot("encounter_win.caf")
    /// Monster roar one-shot (penguinslide-gyu.27): fire-and-forget at
    /// the intro's performEncounterWorldSwap roar slot, layered on the
    /// visual `snowMonster?.roar()` beat. Same guard discipline as the
    /// stings; the four per-event encounter SFX (throw whoosh, impact,
    /// dodge whoosh, flyby) live on SnowMonsterEncounterSystem's
    /// SKAudioNodes instead because they need per-play volume.
    private let snowmanRoarSound = GameScene.guardedOneShot("snowman_roar.caf")

    /// nil when `file` is not in the main bundle, else a fire-and-forget
    /// playSoundFileNamed action. Internal (not private) so the unit
    /// suite can pin the guard contract against the host bundle
    /// (EncounterAudioTests).
    static func guardedOneShot(_ file: String) -> SKAction? {
        guard Bundle.main.url(forResource: file, withExtension: nil) != nil else { return nil }
        return SKAction.playSoundFileNamed(file, waitForCompletion: false)
    }

    private var score: Int = 0 {
        didSet { hud?.setScore(score) }
    }
    // Skill scoring (penguinslide-y7f). `bonusPoints` accumulates close-call
    // rewards on top of survival time; `combo` is the live streak length;
    // `lastCloseCallTime` is the `elapsed` stamp of the last dodge.
    private var bonusPoints: Int = 0
    private var combo: Int = 0
    private var lastCloseCallTime: TimeInterval = 0
    #if DEBUG
    // Reflects the most recent close-call so tests can assert the y7f scoring
    // hook fired without depending on physics timing (penguinslide-ga8).
    private var debugLastCloseCall: SKLabelNode?
    // Mirrors `phase` plus volley/HP state to the accessibility tree
    // ("encounterState:encounter volley=3/8 hp=2 w=.. e=..") so tests and
    // agent-device can observe phase traversal synchronously, with zero
    // timing dependence (penguinslide-gyu.21; the matching tap hook is
    // debugForceEncounter below). Rewritten on every phase change, ball
    // resolution, and HP change by refreshDebugEncounterState().
    private var debugEncounterState: SKLabelNode?
    #endif
    private var isGameOver = false
    private var isStarted = false

    // MARK: - Game phase

    /// Which per-frame body `update(_:)` runs. The Snow Monster encounter is a
    /// phase inside this scene — not a presented second SKScene — so the
    /// CMMotionManager, lifecycle observers, audio nodes, camera, and
    /// ContentView's single-GameScene-@State contract all stay intact.
    private enum GamePhase {
        case normal          // side-view icicle run (today's gameplay)
        case encounterIntro  // transition choreography into the encounter
        case encounter       // pseudo-3D snowball dodge volley
        case encounterOutro  // transition choreography back to the run
    }

    private var phase: GamePhase = .normal
    /// Seconds spent in the current phase (dt-accumulated, so the dt == 0
    /// sentinel and pauses can never inject time). Drives the intro/outro
    /// timelines; reset by `transition(to:)`.
    private var phaseTime: TimeInterval = 0

    /// Armed by `queueEncounterStart()` (settings "Snow Monster Mode" button,
    /// penguinslide-gyu.30); consumed at the top of the next `.normal` frame
    /// so the encounter always enters through `transition(to:)` on the
    /// update loop, never from a SwiftUI callback mid-frame.
    private var pendingEncounterStart = false

    /// Called by ContentView when the settings 'Snow Monster Mode' button was
    /// armed and the sheet dismisses. Auto-starts the run if pre-start.
    func queueEncounterStart() {
        if !isStarted {
            isStarted = true
            lastUpdateTime = 0
            hud.dismissStartPrompt()
        }
        pendingEncounterStart = true
    }

    /// The ONLY way to change `phase`. Always resets the frame-time anchor so
    /// the next frame computes `dt == 0`, keeping the dt sentinel symmetric
    /// across phase changes the same way start/restart/settings-resume/
    /// app-foreground already do (see restart(); penguinslide-jj2 lineage).
    /// Never write `phase` directly.
    private func transition(to newPhase: GamePhase) {
        // Encounter entry breaks the close-call streak (penguinslide-gyu.2).
        // The combo clock is gameplayElapsed, which freezes for the whole
        // encounter — without this clear, a streak would sit frozen across a
        // ~20 s boss fight and still be "live" on return, which reads as a
        // bug either way (stale multiplier, or a surprise expiry one frame
        // after re-entry). Cleared on *leaving* .normal so any encounter
        // phase (intro, or a debug jump straight to .encounter) is covered.
        if phase == .normal && newPhase != .normal {
            combo = 0
            hud.hideCombo()
        }
        // Normal-HUD encounter treatment (penguinslide-gyu.20): score/best/
        // combo hide while any encounter phase is live (the drip is frozen
        // with the gameplay clock; a stuck score reads as broken), hearts
        // stay visible — HP is shared, and the heart row is the damage
        // feedback in both modes. Idempotent inside setEncounterMode.
        hud.setEncounterMode(newPhase != .normal)
        // EncounterHUD push site (penguinslide-gyu.20). Keyed off the phase
        // ENTRY — the one seam the interim-bridge replacement beads
        // (gyu.17/.18) keep — so the banner sequencing survives the real
        // choreography landing: intro banner in on intro entry, out (plus
        // the progress counter arming off the volley plan begun by the
        // intro hand-off) on encounter entry, outcome beat + progress
        // fade on outro entry. The outro is reachable only by SURVIVING
        // the volley (a loss exits through triggerGameOver instead), so
        // outro entry ⇒ the win banner; a loss shows no encounter banner
        // (standard GameOverView page).
        switch newPhase {
        case .normal:
            break
        case .encounterIntro:
            encounterHUD.showIntroBanner()
        case .encounter:
            encounterHUD.hideIntroBanner()
            encounterResolvedCount = 0
            encounterHUD.setProgress(resolved: 0,
                                     total: encounterSystem.plan?.count ?? 0)
        case .encounterOutro:
            encounterHUD.hideProgress()
            encounterHUD.showOutcomeBanner()
        }
        phase = newPhase
        phaseTime = 0
        lastUpdateTime = 0
        #if DEBUG
        refreshDebugEncounterState()
        #endif
    }

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

        worldRoot.zPosition = 0
        addChild(worldRoot)
        encounterRoot.zPosition = 0
        encounterRoot.isHidden = true
        encounterRoot.isPaused = true
        addChild(encounterRoot)

        buildSky()
        buildIceField()

        penguin = Penguin(parent: worldRoot,
                          baseY: iceFloorY + 42,
                          leftBound: iceLeftX,
                          rightBound: iceRightX)
        icicles = IcicleSystem(scene: self,
                               parent: worldRoot,
                               camera: cam,
                               penguin: penguin,
                               iceTopY: iceTopY,
                               iceLandingY: iceFloorY,
                               iceLeftX: iceLeftX,
                               iceRightX: iceRightX,
                               sceneSize: size)
        hud = HUDController(scene: self,
                            sceneSize: size,
                            initialBest: bestScore())
        hud.showStartPrompt()
        encounterHUD = EncounterHUD(scene: self, sceneSize: size)

        // Intro snow-flash (gyu.17): persistent and hidden when idle so
        // repeated encounters never allocate. zPosition sits ABOVE the
        // normal HUD (50) and gameplay floats (60) — the whole world must
        // white out — but BELOW the EncounterHUD banner (80), which keeps
        // playing through the crossfade by contract.
        let flash = SKSpriteNode(color: .white, size: size)
        flash.anchorPoint = .zero
        flash.alpha = 0
        flash.isHidden = true
        flash.zPosition = 75
        addChild(flash)
        introFlash = flash

        let bg = SKAudioNode(fileNamed: "bg_music.caf")
        bg.autoplayLooped = true
        bg.isPositional = false
        bg.run(SKAction.changeVolume(to: Self.bgMusicVolume, duration: 0))
        addChild(bg)
        bgMusic = bg

        // Encounter ambience loop (gyu.28), built once next to the bed.
        // Guarded: SKAudioNode(fileNamed:) with a missing resource is a
        // crash risk, so no file means no node and silent encounters —
        // no other behavior change. Starts paused at volume 0;
        // startEncounterAmbience() un-pauses and ramps it at intro entry.
        if Bundle.main.url(forResource: "encounter_ambience.caf",
                           withExtension: nil) != nil {
            let amb = SKAudioNode(fileNamed: "encounter_ambience.caf")
            amb.autoplayLooped = true
            amb.isPositional = false
            amb.run(SKAction.changeVolume(to: 0, duration: 0))
            amb.run(SKAction.pause())
            addChild(amb)
            encounterAmbience = amb
        }

        // Wire heart HUD to penguin HP so the UI stays in sync without
        // GameScene mediating each change. Initial render covers round start.
        penguin.onHealthChanged = { [weak self] hp in
            self?.hud.setHealth(hp)
            #if DEBUG
            // Keep the encounterState mirror's hp field accurate the moment
            // a hit lands (snowball OR icicle) instead of waiting for the
            // next ball resolution / phase change (penguinslide-gyu.21).
            self?.refreshDebugEncounterState()
            #endif
        }
        // Close-call dodges flow in from IcicleSystem; GameScene owns the
        // scoring state and HUD push (penguinslide-y7f).
        icicles.onCloseCall = { [weak self] severity, point in
            self?.registerCloseCall(severity: severity, at: point)
        }

        // Encounter outcome wiring (penguinslide-gyu.15). The system
        // DETECTS (hits, dodges, volley completion); the scene DECIDES —
        // the same separation as IcicleSystem/Penguin/HUD.
        //
        // A snowball connected: route to the SHARED penguin HP pool.
        // `ballWorldX` is encounter world units ≡ scene x at z = 0, so it
        // satisfies `tryTakeHit(from:)`'s impactX contract directly. A hit
        // during i-frames still consumed the ball (`tryTakeHit` returns
        // false: no HP change, no knockback) — the FX bead (gyu.16) dials
        // the impact treatment by that flag; the avatar-side knockback
        // hop is the avatar wiring bead's job. HP exhausted mid-volley
        // ends the run through the STANDARD game-over flow (the loss
        // outcome — encounter freeze semantics finish in gyu.19).
        encounterSystem.onSnowballHit = { [weak self] ballWorldX, screenPoint in
            guard let self else { return }
            // A connecting ball is a RESOLVED ball — tick the volley
            // progress counter even on a hit (penguinslide-gyu.20), and
            // even on the lethal one (the frozen frame should show the
            // full tally).
            self.registerEncounterBallResolved()
            // Route through the avatar (gyu.17 wiring): PapiAvatar.takeHit
            // delegates hp / i-frames to the SAME penguin.tryTakeHit and
            // re-applies the knockback impulse to the avatar's own motion
            // (tryTakeHit's impulse lands on the hidden side-view body —
            // meaningless mid-encounter). The fallback covers the
            // can't-happen window before the first midpoint swap builds
            // the avatar.
            let accepted: Bool
            if let avatar = self.papiAvatar {
                accepted = avatar.takeHit(fromWorldX: ballWorldX)
            } else {
                accepted = self.penguin.tryTakeHit(from: ballWorldX)
            }
            // Impact FX (penguinslide-gyu.16): snow-splat burst INTO Papi
            // at the impact screen point, sized by the avatar's depth
            // scale, dialed soft + shake-free when i-frames absorbed the
            // hit (the icicle path's accepted handling). The system
            // retired the ball node in this same sweep frame, so the
            // splat replaces the ball with no visible pass-through; it
            // plays over the avatar's gyu.11 hurt/i-frame visuals.
            self.encounterFX?.playHitBurst(at: screenPoint,
                                           depthScale: self.papiAvatar?.depthScale ?? 1,
                                           accepted: accepted)
            // Impact SFX (gyu.27): volume scaled by the same verdict —
            // full punch on an HP-losing hit, soft on an i-frame absorb
            // (the audio mirror of the soft-FX treatment above). Fired
            // from here because `accepted` is born here, not in the
            // system's sweep.
            self.encounterSystem.playImpactAudio(accepted: accepted)
            if !self.penguin.isAlive() { self.triggerGameOver() }
        }
        // A dodged ball (penguinslide-gyu.20): tick the progress counter
        // and pay the severity-scaled dodge bonus through the EXISTING
        // float pipeline — hud.floatBonus, the same display the icicle
        // close-call path uses (one float mechanism, not two). Encounter
        // income lands in bonusPoints, the only score source while the
        // survival drip is frozen; gyu.16 layers whoosh/haptic FX on top
        // and gyu.18 pays the volley-completion bonus at the outro.
        encounterSystem.onDodge = { [weak self] severity, screenPoint in
            guard let self else { return }
            self.registerEncounterBallResolved()
            self.registerEncounterDodge(severity: severity, at: screenPoint)
            // Dodge whoosh accent (penguinslide-gyu.16): speed lines
            // streaking the ball's pass direction (away from Papi),
            // light haptic only for high-severity shaves. The score
            // float above stays the one float mechanism.
            let papiX = self.papiAvatar?.node.position.x ?? screenPoint.x
            self.encounterFX?.playDodgeAccent(
                at: screenPoint,
                severity: severity,
                direction: screenPoint.x >= papiX ? 1 : -1)
        }
        // The volley survived (every throw made AND the last ball
        // resolved — never fires at the last throw): head back through
        // the outro. The phase guard makes a late/no-op completion (e.g.
        // after a same-frame death already left .encounter) harmless.
        //
        // DEATH-ON-THE-FINAL-BALL (penguinslide-gyu.19): the system's
        // sweep resolves hits BEFORE its completion check within the
        // same update call (asserted by EncounterDeathAccountingTests),
        // so a lethal final ball runs onSnowballHit → triggerGameOver
        // (isGameOver = true) first, and the completion that follows
        // microseconds later in the same frame lands HERE with the run
        // already over. The !isGameOver guard makes that frame resolve
        // as GAME OVER, not outro: no volley bonus, no melt beat, no
        // "DODGED!" banner over the death freeze — phase stays
        // .encounter under the GameOverView until restart().
        encounterSystem.onVolleyComplete = { [weak self] in
            guard let self, self.phase == .encounter, !self.isGameOver else { return }
            // Same entry pair as the intro (one-shot presentation arm,
            // then the phase change): payout + melt + flash arm precede
            // the transition's HUD beat (penguinslide-gyu.18).
            self.beginOutroPresentation()
            self.transition(to: .encounterOutro)
        }
        hud.setHealth(penguin.hp)

        startMotionUpdates()
        observeAppLifecycle()

        #if DEBUG
        installDebugForceGameOver()
        installDebugLastCloseCall()
        installDebugEncounterState()
        installDebugForceEncounter()
        // Hermetic test-volley config (penguinslide-gyu.22): EncounterUITests
        // launches the app with
        //   -encounterTestVolley "count=3 interval=0.8 zSpeed=1200 hitRadius=0"
        // to script deterministic win/loss volleys (the simulator has no
        // gyro, so outcomes can't be steered by tilt). nil — i.e. every
        // normal run — leaves the Tuning-lerped plan untouched. See
        // SnowMonsterEncounterSystem.TestVolleyOverrides for the grammar.
        encounterSystem.testVolleyOverrides =
            SnowMonsterEncounterSystem.TestVolleyOverrides.parse(
                arguments: ProcessInfo.processInfo.arguments)
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
        pauseSceneAudio()
    }

    @objc private func handleDidBecomeActive() {
        // The dt-skip sentinel in update(_:) treats lastUpdateTime == 0 as
        // "first frame, dt = 0". Without this reset, the first post-resume
        // update sees a multi-second dt (the lock duration), `elapsed`
        // jumps, score balloons, and Penguin/IcicleSystem integrate one
        // giant step. Same sentinel pattern as restart()/start (penguinslide-jj2).
        lastUpdateTime = 0
        view?.isPaused = false
        resumeSceneAudio()
    }

    // MARK: - Settings sheet pause hooks

    // ContentView calls these when the settings sheet opens/closes. Same
    // mechanics as the app-lifecycle handlers, kept as separate entry
    // points so they can diverge later (e.g., dim the scene).
    func pauseForSettings() {
        view?.isPaused = true
        pauseSceneAudio()
    }

    func resumeFromSettings() {
        lastUpdateTime = 0
        view?.isPaused = false
        resumeSceneAudio()
    }

    // MARK: - Audio duck/restore (penguinslide-gyu.28)

    /// Shared by handleWillResignActive and pauseForSettings (the entry
    /// points stay separate per the comment above; the AUDIO half is one
    /// contract). Pauses every long-running audio node — one-shot stings
    /// ride playSoundFileNamed and just finish.
    private func pauseSceneAudio() {
        bgMusic?.run(SKAction.pause())
        encounterAmbience?.run(SKAction.pause())
        // Encounter SFX (gyu.27): STOPPED, not paused — backgrounding
        // mid-encounter must silence everything, and the resume path
        // must not re-play() a one-shot that wasn't sounding (that
        // would fire a spurious whoosh). Stopped clips just end;
        // resumeSceneAudio leaves them alone.
        encounterSystem.stopAudio()
    }

    /// Mirror of pauseSceneAudio for the two resume paths. Re-asserts the
    /// INTENDED bed level rather than the 0.18 baseline: a pause lands
    /// mid-duck-ramp freezes the changeVolume action, and a resume inside
    /// an encounter must come back at the DUCKED level (gyu.28
    /// acceptance), so the tracked target is snapped, replacing any
    /// frozen ramp via the shared action key. The ambience re-plays only
    /// while its active flag says the encounter still owns the mix.
    private func resumeSceneAudio() {
        bgMusic?.run(SKAction.play())
        bgMusic?.run(SKAction.changeVolume(to: bgMusicTargetVolume, duration: 0),
                     withKey: Self.volumeActionKey)
        if encounterAmbienceActive {
            encounterAmbience?.run(SKAction.play())
        }
    }

    /// The ONLY writer of the bed's volume (and its tracked target).
    /// Ramps replace each other via the shared key so a quick
    /// duck-then-restore (e.g. intro straight into a death) never has two
    /// changeVolume actions fighting.
    private func setBgMusicVolume(_ volume: Float, ramp: TimeInterval) {
        bgMusicTargetVolume = volume
        bgMusic?.run(SKAction.changeVolume(to: volume, duration: ramp),
                     withKey: Self.volumeActionKey)
    }

    /// Un-pause the ambience loop and ramp it in. No-op when the .caf
    /// wasn't bundled (encounterAmbience == nil).
    private func startEncounterAmbience() {
        guard let amb = encounterAmbience else { return }
        encounterAmbienceActive = true
        amb.run(SKAction.play())
        amb.run(SKAction.changeVolume(to: Tuning.Encounter.ambienceVolume,
                                      duration: Tuning.Encounter.bgDuckRamp),
                withKey: Self.volumeActionKey)
    }

    /// Fade the ambience to silence, then pause playback so the loop
    /// doesn't burn the audio engine between encounters. `fade: 0` (the
    /// restart path) silences on the next action pass. Clearing the
    /// active flag first means a lifecycle resume during the fade leaves
    /// the loop down, as intended.
    private func stopEncounterAmbience(fade: TimeInterval) {
        guard let amb = encounterAmbience else { return }
        encounterAmbienceActive = false
        amb.run(SKAction.sequence([SKAction.changeVolume(to: 0, duration: fade),
                                   SKAction.pause()]),
                withKey: Self.volumeActionKey)
    }

    // MARK: - World construction

    private func buildSky() {
        // Backdrop art has sky + distant mountains baked in.
        let backdrop = SKSpriteNode(texture: SpriteCatalog.texture(for: .skyBackdrop))
        backdrop.anchorPoint = .zero
        backdrop.position = .zero
        backdrop.size = size
        backdrop.zPosition = -100
        worldRoot.addChild(backdrop)
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
        worldRoot.addChild(water)

        let iceSize = CGSize(width: strip, height: iceTopY)
        let ice = SKSpriteNode(texture: SpriteCatalog.tiled(.iceTile, size: iceSize),
                               size: iceSize)
        ice.anchorPoint = .zero
        ice.position = CGPoint(x: iceLeftX, y: 0)
        ice.zPosition = -10
        worldRoot.addChild(ice)

        // Top edge of the ice (shoreline highlight).
        let topLine = SKShapeNode(rect: CGRect(x: iceLeftX, y: iceTopY - 2, width: strip, height: 2))
        topLine.fillColor = UIColor(white: 1.0, alpha: 0.9)
        topLine.strokeColor = .clear
        topLine.zPosition = -9
        worldRoot.addChild(topLine)

        // Vertical shore edges so the ice reads as a platform, not a band.
        for x in [iceLeftX, iceRightX - 2] {
            let edge = SKShapeNode(rect: CGRect(x: x, y: 0, width: 2, height: iceTopY))
            edge.fillColor = UIColor(red: 0.55, green: 0.75, blue: 0.88, alpha: 0.8)
            edge.strokeColor = .clear
            edge.zPosition = -9
            worldRoot.addChild(edge)
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
            worldRoot.addChild(crack)
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

    /// Rotate CoreMotion's device-frame gravity into interface (screen) space.
    /// Device frame: +x device-right, +y device-top (when held in portrait).
    /// Interface frame: +x screen-right, +y screen-up. The mapping depends on
    /// how UIKit has rotated the interface relative to the device.
    private func screenGravity(_ gravity: CMAcceleration) -> CGVector {
        let interface = view?.window?.windowScene?.interfaceOrientation ?? .landscapeLeft
        let gx = CGFloat(gravity.x)
        let gy = CGFloat(gravity.y)
        switch interface {
        case .landscapeLeft:      return CGVector(dx:  gy, dy: -gx)
        case .landscapeRight:     return CGVector(dx: -gy, dy:  gx)
        case .portraitUpsideDown: return CGVector(dx: -gx, dy: -gy)
        case .portrait:           return CGVector(dx:  gx, dy:  gy)
        case .unknown:            return CGVector(dx:  gy, dy: -gx)
        @unknown default:         return CGVector(dx:  gy, dy: -gx)
        }
    }

    /// Read current tilt: CoreMotion gravity projected onto the screen's
    /// horizontal axis, with a GCKeyboard fallback for the simulator.
    /// Output is in [-1, 1] with a small dead zone to suppress flat-phone drift.
    private func currentTilt() -> CGFloat {
        #if DEBUG && targetEnvironment(simulator)
        // Sim-only injection takes precedence so manual scripts can
        // drive the penguin without fighting the keyboard fallback.
        // Stale samples (>0.5 s) are ignored so a disconnected injector
        // can't pin the penguin.
        if let s = MotionInjector.shared.latestTilt,
           Date().timeIntervalSince(s.at) < 0.5 {
            return max(-1, min(1, s.value))
        }
        #endif
        var tilt: CGFloat = 0
        if let gravity = motionManager.deviceMotion?.gravity {
            // CoreMotion reports gravity in the device-fixed frame. Rotate it
            // into interface coordinates so `screenGravity.dx` is always
            // "tilt-right is positive," regardless of orientation.
            tilt = screenGravity(gravity).dx
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
        if let t = touches.first,
           nodes(at: t.location(in: self)).contains(where: { $0.name == Self.debugForceEncounterLabel }) {
            // Only a live, .normal-phase round may be forced into the intro:
            // no nested encounters (tap during .encounterIntro/.encounter/
            // .encounterOutro is a no-op) and no post-death encounters.
            guard phase == .normal, !isGameOver else { return }
            // Same pre-start coherence dance as the debugForceGameOver hook
            // above, so a cold-start tap enters the intro from a started run.
            if !isStarted {
                isStarted = true
                lastUpdateTime = 0
                hud.dismissStartPrompt()
            }
            // Enter through the SAME pair the pendingEncounterStart consume
            // in update(_:) uses — the entry one-shot (icicle sweep + flash
            // arm) must precede the phase change; the world swap itself
            // happens at the intro timeline's midpoint (gyu.17). This path
            // deliberately bypasses EncounterTrigger AND its score-bracket
            // gate (debug/manual entries are exempt by the bead amendment).
            // Consume any settings-armed flag so a queued entry can't fire
            // a second encounter after this forced one finishes.
            pendingEncounterStart = false
            beginEncounterPresentation()
            transition(to: .encounterIntro)
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
        // Restart is no longer a tap-on-scene action: while game-over, the
        // SwiftUI page sits on top (and captures taps) and its "Play Again"
        // button calls `playAgain()`.
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
    ///
    /// Phase routing: inside the guard, `phase` selects this frame's body —
    /// `.normal` runs the icicle-run body unchanged, `.encounter` runs only
    /// the encounter system (icicle spawn timers do not advance), and the
    /// intro/outro phases tick their transition timelines. The dt computation
    /// and the guard are phase-independent and stay above the switch; every
    /// phase change goes through `transition(to:)`, which resets the dt
    /// sentinel.
    override func update(_ currentTime: TimeInterval) {
        let dt: TimeInterval = lastUpdateTime == 0 ? 0 : (currentTime - lastUpdateTime)
        lastUpdateTime = currentTime

        guard isStarted, !isGameOver else { return }

        // Both clocks add 0 on a sentinel frame (dt == 0), so phase
        // transitions / resumes can never inject time into either.
        elapsed += dt

        switch phase {
        case .normal:
            // Settings-armed encounter (penguinslide-gyu.30): consume the
            // flag before any of this frame's normal-phase work runs.
            // Single-shot by construction: the flag is cleared BEFORE the
            // transition, and `transition(to:)` is the only phase writer.
            if pendingEncounterStart {
                pendingEncounterStart = false
                beginEncounterPresentation()
                transition(to: .encounterIntro)
                return
            }

            // Gameplay clock advances only here — encounters freeze the
            // drip/ramp/combo timeline (see gameplayElapsed declaration).
            gameplayElapsed += dt

            // Expire a lapsed combo BEFORE this frame's landings are evaluated,
            // so a dodge this frame can never be decayed in the same frame.
            if combo > 0 && gameplayElapsed - lastCloseCallTime > Tuning.Score.comboWindow {
                combo = 0
                hud.hideCombo()
            }

            penguin.update(dt: dt, tilt: currentTilt())
            icicles.update(dt: dt, elapsed: gameplayElapsed)  // may fire onCloseCall

            // Survival drip (unchanged rate) plus accumulated close-call bonus.
            // Driven by the gameplay clock so encounter time pays nothing.
            score = Int(gameplayElapsed * Tuning.Score.survivalRate) + bonusPoints

            // Random-encounter roll (penguinslide-gyu.17), AFTER this
            // frame's integration so the danger-window read sees the
            // freshest icicle positions and the bracket gate the freshest
            // score. Eligibility (the fairness rule): the run is live
            // (isStarted/!isGameOver hold inside the guard; .normal holds
            // by case), the penguin is alive and OUTSIDE i-frames (a
            // trigger mid-flicker would hide the hurt feedback beat), and
            // no falling icicle is inside the danger window (the intro
            // sweep would erase a deserved hit). The gameplay clock feeds
            // arming/spacing so encounter time never counts.
            let eligible = penguin.isAlive()
                && !penguin.isInvulnerable
                && !icicles.hasIcicleNear(x: penguin.node.position.x,
                                          window: Tuning.Encounter.triggerDangerWindow)
            if encounterTrigger.update(dt: dt, gameplayElapsed: gameplayElapsed,
                                       score: score, eligible: eligible) {
                beginEncounterPresentation()
                transition(to: .encounterIntro)
            }

        case .encounter:
            // The encounter system is this frame's ONLY integration work:
            // icicles.update is deliberately not called (no spawn-timer
            // advancement, no falling icicles) and the survival drip pauses.
            // Tilt is read once here and injected — the identical value
            // penguin.update gets in .normal (KTD4: input stays owned by
            // GameScene, subsystems receive it as a parameter).
            //
            // Phase exit is callback-driven (penguinslide-gyu.15): the
            // system's onVolleyComplete (wired in didMove) fires the outro
            // when the last ball resolves; a hit that exhausts HP routes
            // through onSnowballHit → triggerGameOver inside this same
            // update call.
            //
            // DEATH-FRAME ORDERING (penguinslide-gyu.19, the encounter
            // analog of the didBegin contract above): the lethal hit is
            // detected MID-SWEEP inside encounterSystem.update, so balls
            // later in that same sweep still finish this frame's
            // integration/layout after triggerGameOver returns — that is
            // same-frame motion (their dt was already committed when the
            // sweep began), not post-death motion. The NEXT frame's
            // isGameOver guard plus physicsWorld.speed = 0 and
            // encounterSystem.pauseActions() (both set in triggerGameOver)
            // freeze everything: balls/spin are manually integrated and
            // stop with this guard; monster clips are SKActions and stop
            // with pauseActions. The score recompute below also still
            // runs on the death frame — harmless: onGameOver already
            // captured its GameResult, and the value is unchanged (a hit
            // adds no income; the drip is frozen with the gameplay clock).
            //
            // Tick order (gyu.17 wiring): avatar BEFORE the system, so the
            // papiWorldX/Vx providers read this frame's post-input position
            // when the flight sweep resolves hits/dodges; the world's
            // forward-scroll bands are pure decoration and tick alongside.
            let tilt = currentTilt()
            papiAvatar?.update(dt: dt, tilt: tilt)
            encounterWorld?.update(dt: CGFloat(dt))
            encounterSystem.update(dt: dt, tilt: tilt)
            // Impact snow chunks integrate on this same tick — and freeze
            // with this same guard on game over (penguinslide-bo8).
            encounterFX?.update(dt: dt)

            // Keep the score current with encounter income (dodge/volley
            // bonuses land in bonusPoints; the drip is frozen with the
            // gameplay clock) so a mid-volley death reports everything
            // earned in the encounter.
            score = Int(gameplayElapsed * Tuning.Score.survivalRate) + bonusPoints

        case .encounterIntro:
            updateEncounterIntro(dt: dt)

        case .encounterOutro:
            updateEncounterOutro(dt: dt)
        }
    }

    // MARK: - Encounter presentation (intro: penguinslide-gyu.17)

    // ------------------------------------------------------------------
    // INTRO CHOREOGRAPHY (gyu.17). True camera rotation is impossible in
    // 2D — "the camera swings behind the penguin" is sold by sequence:
    //
    //   trigger frame   beginEncounterPresentation(): every live icicle
    //                   pops in a low-severity shatter sweep (fairness:
    //                   nothing may linger frozen or detach mid-intro),
    //                   the snow-flash arms, transition(.encounterIntro)
    //                   resets the dt sentinel.
    //   first half      the side view holds still (penguin/icicle
    //                   integration stopped = the slow-down beat) while
    //                   the white flash ramps up.
    //   midpoint        performEncounterWorldSwap(), fully masked by the
    //                   peak flash: worldRoot hides+pauses, the side-view
    //                   penguin sprite hides, encounterRoot shows+
    //                   unpauses with the real world/actors (built once,
    //                   recycled), the monster roars, and the volley arms
    //                   (encounterSystem.begin) with the run's difficulty
    //                   progress AT TRIGGER TIME (gameplayElapsed froze on
    //                   leaving .normal, so reading it here is identical).
    //   second half     the flash fades off the already-running encounter
    //                   world — Papi reads as the penguin having turned
    //                   away from the camera — then transition(.encounter)
    //                   resets the dt sentinel again.
    //
    // The whole timeline is `phaseTime`-driven (dt-accumulated, no
    // SKActions, no wall clock), so settings/app-background mid-intro
    // freeze it and resume without skipping the swap. The OUTRO
    // (gyu.18, below updateEncounterIntro) mirrors this choreography in
    // reverse, stretched around the monster's melt beat.
    // ------------------------------------------------------------------

    /// One-shot intro entry. Called exactly once per entry (random
    /// trigger, settings-armed consume, or debugForceEncounter), always
    /// immediately before `transition(to: .encounterIntro)`. The world
    /// stays VISIBLE here — the swap happens at the timeline midpoint.
    private func beginEncounterPresentation() {
        // Visible icicle sweep: every live icicle (falling AND warning
        // phase) pops with a small shatter at its current position. The
        // pop debris self-cleans; the midpoint swap's icicles.reset()
        // scrubs any stragglers behind the peak flash.
        icicles.sweepClear()

        // Audio boundary (gyu.28): duck the bed under the encounter, land
        // the intro sting on top, and bring the ambience loop in. The
        // restore lives on all three exits — outro win
        // (beginOutroPresentation), encounter death (triggerGameOver),
        // and restart() — so the side view / game-over page always sound
        // the same regardless of which world you came from.
        setBgMusicVolume(Tuning.Encounter.bgDuckVolume,
                         ramp: Tuning.Encounter.bgDuckRamp)
        if let sting = encounterStingSound { run(sting) }
        startEncounterAmbience()

        introSwapDone = false
        introFlash?.alpha = 0
        introFlash?.isHidden = false
    }

    /// The intro midpoint: the actual world swap, fully masked by the
    /// peak snow-flash. One-shot per entry via `introSwapDone`.
    private func performEncounterWorldSwap() {
        // Scrub any sweep debris (shards/bursts mid-fade) along with the
        // spawn cadence — invisible behind the flash, and the guarantee
        // that ZERO icicle-system nodes exist anywhere after the intro.
        icicles.reset()
        // One toggle hides the entire side-view world (penguinslide-gyu.9);
        // pausing it freezes any remaining decorative SKActions (penguin
        // idle animation) without touching scene-level audio/HUD/camera.
        worldRoot.isHidden = true
        worldRoot.isPaused = true
        // The penguin "turns away from the camera": the side-view sprite
        // disappears and PapiAvatar appears center-near. Explicit on top
        // of the (already hiding) worldRoot so outro/restart restores are
        // symmetric and self-documenting.
        penguin.node.isHidden = true

        ensureEncounterContent()
        // Per-entry scrubs of the recycled content: Papi recenters, the
        // band field re-seats, then the forward-slide scroll begins.
        papiAvatar?.begin()
        encounterWorld?.reset()
        encounterWorld?.startScroll()
        encounterRoot.alpha = 1
        encounterRoot.isHidden = false
        encounterRoot.isPaused = false

        // Monster roar one-shot — visual + the gyu.27 roar SFX on the
        // same beat (guarded: nil when snowman_roar.caf isn't bundled).
        snowMonster?.roar()
        if let roar = snowmanRoarSound { run(roar) }

        // Arm the volley (penguinslide-gyu.15). It only TICKS from
        // .encounter frames (encounterSystem.update isn't called during
        // the intro), so the first telegraph fires once the flash clears.
        encounterSystem.begin(difficultyProgress: runDifficultyProgress())

        #if DEBUG
        // Both root child counts just changed — keep the mirror honest.
        refreshDebugEncounterState()
        #endif
    }

    /// Lazily build the persistent encounter content under encounterRoot
    /// and attach the system's actor seams, on the FIRST midpoint swap
    /// only. Once per scene by contract: PapiAvatar chains onto
    /// `penguin.onHealthChanged` at construction (re-construction stacks
    /// chains), and EncounterWorld/SnowMonster pool their nodes for
    /// recycling. Per-entry state hygiene lives in reset()/begin() calls
    /// at the swap, not in re-construction.
    private func ensureEncounterContent() {
        guard encounterWorld == nil else { return }
        let projector = DepthProjector(sceneSize: size)

        encounterWorld = EncounterWorld(parent: encounterRoot, sceneSize: size)
        let monster = SnowMonster(parent: encounterRoot, projector: projector)
        snowMonster = monster
        let avatar = PapiAvatar(parent: encounterRoot, projector: projector,
                                penguin: penguin)
        papiAvatar = avatar

        // System seams (the gyu.13/.15 contracts): node parent +
        // geometry authority, the boss actor the throw cycle drives, and
        // the live dodge-target reads for aim/collision.
        encounterSystem.configure(parent: encounterRoot, projector: projector)
        // Encounter SFX nodes (gyu.27) attach to the SCENE, not
        // encounterRoot — a hidden+paused container would freeze
        // SKAudioNode actions mid-clip (the IcicleSystem rule). Guarded
        // per-file inside; idempotent, though this runs once anyway.
        encounterSystem.attachAudio(scene: self)
        encounterSystem.monster = monster
        encounterSystem.papiWorldXProvider = { [weak avatar] in
            avatar?.worldX ?? projector.vanishingX
        }
        encounterSystem.papiVxProvider = { [weak avatar] in avatar?.vx ?? 0 }

        // Impact/dodge FX (penguinslide-gyu.16): parented to
        // encounterRoot so FX shows/hides with the encounter world;
        // shares the scene camera for the hit shake.
        encounterFX = EncounterFX(parent: encounterRoot,
                                  camera: gameCamera,
                                  sceneSize: size)
    }

    /// One-shot restore back to the side view. Idempotent — also called
    /// from `restart()` so a death/restart mid-encounter (or mid-INTRO:
    /// the flash/swap flags are scrubbed too) can never leave the world
    /// hidden or the encounter content live.
    private func endEncounterPresentation() {
        // Persistent content is scrubbed, not destroyed (built once,
        // recycled — see ensureEncounterContent): the system reset tears
        // down the volley and returns the monster to idle; world/avatar
        // resets stop the scroll and recenter Papi.
        encounterSystem.reset()
        encounterWorld?.reset()
        papiAvatar?.reset()
        // Scrub transient impact/dodge FX (gyu.16) — a burst or whoosh
        // mid-flight at teardown must not leak into the next encounter.
        encounterFX?.reset()
        encounterRoot.isHidden = true
        encounterRoot.isPaused = true
        encounterRoot.alpha = 1
        worldRoot.isHidden = false
        worldRoot.isPaused = false
        penguin.node.isHidden = false
        // Interrupt hygiene: a restart mid-intro/mid-outro must drop the
        // flash and re-arm both midpoint one-shots.
        introFlash?.isHidden = true
        introFlash?.alpha = 0
        introSwapDone = false
        outroSwapDone = false
    }

    /// Intro timeline tick (gyu.17). `phaseTime` is dt-accumulated, so
    /// the dt sentinel and pauses inject no time, and the midpoint/
    /// completion checks are ordered so even a single giant-dt frame
    /// performs the swap BEFORE finishing the intro.
    private func updateEncounterIntro(dt: TimeInterval) {
        phaseTime += dt
        let progress = min(1, phaseTime / Tuning.Encounter.introDuration)

        // Snow-flash crossfade: a triangle over the timeline — fully
        // white exactly at the midpoint (masking the swap), gone at both
        // ends. Manually driven every frame; never an SKAction.
        introFlash?.alpha = CGFloat(1 - abs(progress * 2 - 1))

        if !introSwapDone, progress >= 0.5 {
            introSwapDone = true
            performEncounterWorldSwap()
        }

        // Post-swap the encounter world is already alive under the
        // fading flash: the ground scrolls and Papi answers tilt, so the
        // player is oriented before the first telegraph.
        if introSwapDone {
            encounterWorld?.update(dt: CGFloat(dt))
            papiAvatar?.update(dt: dt, tilt: currentTilt())
        }

        if phaseTime >= Tuning.Encounter.introDuration {
            introFlash?.isHidden = true
            introFlash?.alpha = 0
            transition(to: .encounter)
        }
    }

    /// The run's difficulty ramp position in [0, 1] — the same
    /// grace-then-ramp curve IcicleSystem.progress applies to the icicle
    /// knobs, read off the (frozen-during-encounters) gameplay clock. Feeds
    /// the volley plan lerp so encounter intensity tracks run intensity.
    private func runDifficultyProgress() -> Double {
        let p = (gameplayElapsed - Tuning.Run.gracePeriod) / Tuning.Run.rampDuration
        return max(0, min(1, p))
    }

    // ------------------------------------------------------------------
    // OUTRO CHOREOGRAPHY (gyu.18). The intro in reverse, stretched
    // around the monster's melt (the 2026-06-11 amendment: the exit
    // happens only after the melt completes):
    //
    //   win frame       onVolleyComplete → beginOutroPresentation():
    //                   volley-completion bonus paid into bonusPoints
    //                   (the ONLY non-dodge encounter income — the drip
    //                   stayed frozen with the gameplay clock) + score
    //                   recomputed + floatBonus shown, the monster's
    //                   melt starts, the bg-music restore seam fires,
    //                   the flash arms; transition(.encounterOutro)
    //                   resets the dt sentinel and plays the outcome
    //                   banner beat (the gyu.20 seam in transition(to:)).
    //   melt beat       [0, meltDuration): the encounter world stays
    //                   fully live (forward scroll + tilt) while the
    //                   monster slumps into its snow puddle.
    //   crossfade       [meltDuration, meltDuration + outroDuration]:
    //                   the intro's triangle snow-flash again; at the
    //                   midpoint (peak white) performOutroWorldSwap()
    //                   restores the side view — encounterRoot hides+
    //                   pauses, worldRoot shows+unpauses, the penguin
    //                   un-hides recentered (POSITION only; hp/i-frames
    //                   untouched — hearts carry over), the volley
    //                   tears down, and the icicle spawn timer takes
    //                   the post-encounter grace hold. The second half
    //                   fades onto the already-live side view, then
    //                   transition(.normal) resets the dt sentinel
    //                   again.
    //
    // Same interrupt-safety as the intro: the timeline is phaseTime-
    // driven (dt-accumulated), the flash is manually written per frame
    // (never an SKAction), and the midpoint check runs before the
    // completion check so a giant-dt frame still swaps exactly once.
    // ------------------------------------------------------------------

    /// One-shot outro entry, called exactly once per WIN immediately
    /// before `transition(to: .encounterOutro)` (the outro is reachable
    /// only through onVolleyComplete — a loss exits via triggerGameOver).
    private func beginOutroPresentation() {
        // Win payout: through the same bonusPoints accumulator the dodge
        // income uses, then recompute the score IMMEDIATELY (no .normal
        // drip frame will run until the outro ends) so the acceptance
        // arithmetic — score at intro + dodge bonuses + volley bonus —
        // holds the moment the outcome banner shows. The float rides the
        // shared HUD pipeline, just under the "DODGED!" banner (0.58 h).
        bonusPoints += Tuning.Encounter.volleyCompletionBonus
        score = Int(gameplayElapsed * Tuning.Score.survivalRate) + bonusPoints
        hud.floatBonus(Tuning.Encounter.volleyCompletionBonus,
                       at: CGPoint(x: size.width / 2, y: size.height * 0.48))

        // The defeat beat: the monster melts slowly into a snow puddle;
        // the crossfade waits out Tuning.Encounter.meltDuration. The win
        // sting (gyu.28) plays over this slot.
        snowMonster?.melt()
        if let sting = encounterWinSound { run(sting) }

        // Audio restore seam (gyu.28): bed back to the baseline, ambience
        // fades out underneath. Ramped so nothing pops against the
        // outcome banner.
        setBgMusicVolume(Self.bgMusicVolume,
                         ramp: Tuning.Encounter.bgRestoreRamp)
        stopEncounterAmbience(fade: Tuning.Encounter.bgRestoreRamp)

        // Arm the crossfade flash + the midpoint one-shot. The flash
        // stays at alpha 0 through the whole melt beat.
        outroSwapDone = false
        introFlash?.alpha = 0
        introFlash?.isHidden = false
    }

    /// The outro crossfade's midpoint: restore the side view behind the
    /// peak flash — performEncounterWorldSwap in reverse, one-shot per
    /// outro via `outroSwapDone`.
    private func performOutroWorldSwap() {
        // Scrub the recycled encounter content (built once, never
        // destroyed): volley teardown, the melted monster back to its
        // idle/home state, scroll stopped, Papi recentered — so the next
        // intro's begin()/reset() pair starts from exactly the same
        // cold state the first one did.
        encounterSystem.reset()
        encounterWorld?.reset()
        papiAvatar?.reset()
        // A whoosh from the volley's last dodge may still be fading —
        // scrub it with the rest of the encounter content (gyu.16).
        encounterFX?.reset()
        encounterRoot.isHidden = true
        encounterRoot.isPaused = true
        worldRoot.isHidden = false
        worldRoot.isPaused = false
        // "Papi turns back toward the camera": the side-view sprite
        // returns at mid-strip via the POSITION-only partial reset —
        // hp / i-frames / hit clock untouched (hearts carry over; the
        // heart row already matches via the shared onHealthChanged).
        penguin.recenter()
        penguin.node.isHidden = false
        // Post-encounter grace: hold the spawn timer (never the gameplay
        // clock — the ramp must not shift) so the first icicle lands no
        // sooner than postEncounterGrace after .normal resumes, then the
        // cadence picks up exactly where the intro froze it.
        icicles.holdSpawns(for: Tuning.Encounter.postEncounterGrace)

        #if DEBUG
        // Both root child counts just changed — keep the mirror honest
        // (e back to its idle count is the no-leak signal gyu.22 reads).
        refreshDebugEncounterState()
        #endif
    }

    /// Outro timeline tick (gyu.18) — see the choreography block above.
    /// dt-accumulated like the intro, so the dt == 0 sentinel and pauses
    /// inject no time and the melt → crossfade → swap ordering is
    /// deterministic even across settings/app-background interruptions.
    private func updateEncounterOutro(dt: TimeInterval) {
        phaseTime += dt
        let meltDuration = Tuning.Encounter.meltDuration

        if phaseTime < meltDuration {
            // Melt beat: the encounter vista stays fully live — ground
            // scrolls, Papi answers tilt — while the monster slumps. A
            // final-ball hit's snow chunks settle through the melt too
            // (penguinslide-bo8) instead of freezing as the outro starts.
            encounterWorld?.update(dt: CGFloat(dt))
            papiAvatar?.update(dt: dt, tilt: currentTilt())
            encounterFX?.update(dt: dt)
            return
        }

        // Crossfade segment: the intro's manually-driven triangle flash
        // (fully white exactly at the midpoint, gone at both ends).
        let progress = min(1, (phaseTime - meltDuration) / Tuning.Encounter.outroDuration)
        introFlash?.alpha = CGFloat(1 - abs(progress * 2 - 1))

        if !outroSwapDone, progress >= 0.5 {
            outroSwapDone = true
            performOutroWorldSwap()
        }

        // Whichever world is live keeps ticking under the flash — the
        // melting vista pre-swap, the restored side-view penguin post-
        // swap (mirroring the intro's post-swap ticks). Exactly ONE of
        // papiAvatar.update / penguin.update runs per frame: both
        // advance the penguin's shared hit clock.
        if outroSwapDone {
            penguin.update(dt: dt, tilt: currentTilt())
        } else {
            encounterWorld?.update(dt: CGFloat(dt))
            papiAvatar?.update(dt: dt, tilt: currentTilt())
        }

        if phaseTime >= meltDuration + Tuning.Encounter.outroDuration {
            introFlash?.isHidden = true
            introFlash?.alpha = 0
            transition(to: .normal)
        }
    }

    // MARK: - Encounter scoring/HUD pushes (penguinslide-gyu.20)

    /// One volley ball finished (hit OR dodge) — push the "n / total"
    /// progress tick. Total reads the live plan so the counter can never
    /// disagree with the volley actually running.
    private func registerEncounterBallResolved() {
        encounterResolvedCount += 1
        encounterHUD.setProgress(resolved: encounterResolvedCount,
                                 total: encounterSystem.plan?.count ?? 0)
        #if DEBUG
        // Every ball resolution rewrites the encounterState mirror so its
        // volley=n/total field tracks the progress counter exactly
        // (penguinslide-gyu.21).
        refreshDebugEncounterState()
        #endif
    }

    /// Turn a snowball dodge into points: `dodgeBonusBase` scaled by the
    /// near-miss severity (the knob's documented contract — "base points
    /// per dodged snowball, before severity scaling"), mirroring
    /// registerCloseCall minus the combo machinery (the combo clock is
    /// gameplayElapsed, frozen for the whole encounter). A wide dodge
    /// (severity ≈ 0) rounds to nothing and floats nothing — only close
    /// shaves pay, exactly like the icicle close-call path.
    private func registerEncounterDodge(severity: CGFloat, at point: CGPoint) {
        let bonus = Int((CGFloat(Tuning.Encounter.dodgeBonusBase) * severity).rounded())
        guard bonus > 0 else { return }
        bonusPoints += bonus
        hud.floatBonus(bonus, at: point)
    }

    /// Turn a survived close-call into points. Combo decay already ran this
    /// frame (top of `update`), so a lapsed streak is already 0 here and the
    /// increment is unconditional. Bonus scales with severity (closer = more)
    /// and the capped combo multiplier.
    private func registerCloseCall(severity: CGFloat, at point: CGPoint) {
        combo += 1
        // Stamped from the gameplay clock — the same clock the expiry check
        // at the top of update reads — so the combo window is measured in
        // .normal-phase time only.
        lastCloseCallTime = gameplayElapsed
        let multiplier = min(CGFloat(combo), Tuning.Score.comboMaxMultiplier)
        let bonus = Int((CGFloat(Tuning.Score.closeCallBase) * severity * multiplier).rounded())
        bonusPoints += bonus
        hud.floatBonus(bonus, at: point)
        if combo >= 2 { hud.showCombo(combo) }
        #if DEBUG
        // Surface the fire to the accessibility tree for test-near-miss.sh.
        debugLastCloseCall?.text = "closeCall:fired sev=\(String(format: "%.2f", severity)) bonus=\(bonusPoints)"
        #endif
    }

    // MARK: - Contact

    func didBegin(_ contact: SKPhysicsContact) {
        // Icicle contact is normal-phase gameplay ONLY. Falling icicles are
        // physics-velocity-driven (IcicleSystem adds gravity to
        // `body.velocity`), so once the phase leaves .normal they coast at
        // their last velocity — physicsWorld.speed stays 1 and hidden/paused
        // nodes still simulate — and can sweep through the (hidden) penguin
        // and kill the run at encounter entry. Entry also clears in-flight
        // icicles (beginEncounterPresentation → icicles.reset()); this gate
        // is the doctrine-level guarantee: encounter damage never arrives
        // through the 2D contact pass (KTD3 — snowball collision is manual,
        // and the shared-HP bead routes hits via tryTakeHit directly).
        guard phase == .normal else { return }
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
        // Getting clipped breaks the streak; i-frame saves (accepted == false)
        // do not.
        if accepted {
            combo = 0
            hud.hideCombo()
        }

        if !penguin.isAlive() { triggerGameOver() }
    }

    // MARK: - Game over / restart

    private func triggerGameOver() {
        guard !isGameOver else { return }
        isGameOver = true

        let best = bestScore()
        let isNewBest = score > best
        if isNewBest {
            UserDefaults.standard.set(score, forKey: "best_score")
            // Keep the top-of-screen HUD in sync with the new record; without
            // this, the player sees a stale "Best" until they restart.
            hud.setBest(score)
        }

        // Death visuals go to whichever actor the player can SEE
        // (penguinslide-gyu.19): penguin.triggerDeathAnimation targets
        // the side-view node, which is hidden during the encounter, so
        // an encounter death tips PapiAvatar instead (same scale-down/
        // fade/tip recipe). Snowball hits only land in .encounter and
        // didBegin guards .normal, so the non-.normal arm here is
        // always the rear-view death. Everything else in this method is
        // view-agnostic by inspection: best_score persistence, the
        // isNewBest computation, the .error haptic, game_over.caf, and
        // hud.triggerDeathFlash (a scene-level overlay covering both
        // roots) flow unchanged from either world.
        if phase == .normal {
            penguin.triggerDeathAnimation()
        } else {
            papiAvatar?.triggerDeathAnimation()
        }
        hud.triggerDeathFlash()

        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.error)
        run(gameOverSound)

        // gyu.28: a death INSIDE an encounter (or mid-intro/outro) must
        // not leave the bed ducked forever — game over keeps bgMusic
        // playing under the page, so restore the baseline here and fade
        // the ambience out. The game-over page then always sounds the
        // same regardless of which world killed you; from .normal this
        // is a volume no-op (already at baseline, ambience inactive).
        setBgMusicVolume(Self.bgMusicVolume,
                         ramp: Tuning.Encounter.bgRestoreRamp)
        stopEncounterAmbience(fade: Tuning.Encounter.bgRestoreRamp)

        // Freeze in-flight icicles AND pause shard fade actions per-node.
        // physicsWorld.speed = 0 halts physics-driven motion, but SKActions
        // (the shard fadeOut) run independently — pausing them keeps the
        // world consistently frozen.
        physicsWorld.speed = 0
        icicles.pauseShardActions()
        // Encounter mirror of pauseShardActions (penguinslide-gyu.15): a
        // death mid-volley must freeze the monster's clips/pulses too —
        // the balls themselves are manually integrated and stop with the
        // update guard. No-op when no encounter content is live.
        encounterSystem.pauseActions()
        // Transient impact/dodge FX one-shots (gyu.16) freeze per-node
        // too, so a death mid-burst leaves a coherent frozen frame —
        // same rationale as pauseShardActions.
        encounterFX?.pauseActions()

        // Hand off to the SwiftUI game-over page. The frozen scene stays
        // visible (dimmed) behind it, and `playAgain()` resumes from there.
        onGameOver?(GameResult(score: score, isNewBest: isNewBest))
    }

    /// Driven by the game-over page's "Play Again" button. ContentView
    /// dismisses the page and calls this to resume from a fresh round.
    func playAgain() { restart() }

    private func restart() {
        icicles.reset()
        // Fresh-run trigger state (gyu.17): arming, spacing, per-run cap,
        // and the score-bracket gate all re-arm with the new round.
        encounterTrigger.reset()
        // playAgain() after an encounter death must restore the side view:
        // endEncounterPresentation() (idempotent) re-shows worldRoot,
        // clears/hides encounterRoot, and resets the encounter system, so
        // a restart from ANY phase lands back in a visible side view.
        // transition(to:) also resets the dt sentinel (redundant with the
        // explicit reset below, but the invariant is owned there).
        endEncounterPresentation()
        pendingEncounterStart = false
        // gyu.28: restart from ANY phase (including mid-intro/outro with
        // a duck or restore ramp in flight) snaps the bed straight back
        // to the baseline and silences the ambience — the fresh round
        // starts from the canonical mix. Redundant after a .normal death
        // (triggerGameOver already restored), and harmless then.
        setBgMusicVolume(Self.bgMusicVolume, ramp: 0)
        stopEncounterAmbience(fade: 0)
        // Immediate encounter-HUD teardown (vs. the outro's animated
        // fades): "Play Again" from any phase must never leave a frozen
        // banner/progress label over the fresh round.
        encounterHUD.reset()
        encounterResolvedCount = 0
        transition(to: .normal)

        physicsWorld.speed = 1
        gameCamera.removeAction(forKey: "shake")
        gameCamera.position = CGPoint(x: size.width / 2, y: size.height / 2)

        elapsed = 0
        gameplayElapsed = 0
        score = 0
        bonusPoints = 0
        combo = 0
        lastCloseCallTime = 0
        hud.hideCombo()
        #if DEBUG
        debugLastCloseCall?.text = "closeCall:none"
        #endif
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

    // Same SKLabelNode-only accessibility constraint as above: its text is the
    // accessibility label test-near-miss.sh reads. Starts "closeCall:none";
    // registerCloseCall(severity:at:) rewrites it to "closeCall:fired ...".
    private func installDebugLastCloseCall() {
        let node = SKLabelNode(text: "closeCall:none")
        node.fontSize = 10
        node.fontColor = UIColor(red: 0, green: 0.6, blue: 1, alpha: 0.55)
        node.horizontalAlignmentMode = .left
        node.verticalAlignmentMode = .top
        node.position = CGPoint(x: 4, y: size.height - 18)
        node.zPosition = 10_000
        addChild(node)
        debugLastCloseCall = node
    }

    // Same SKLabelNode-only accessibility constraint: the text is the
    // accessibility label tests read. Scene-level (not under worldRoot/
    // encounterRoot) so it stays visible in every phase. Rewritten by
    // refreshDebugEncounterState() on phase changes, ball resolutions,
    // and HP changes (penguinslide-gyu.21).
    private func installDebugEncounterState() {
        let node = SKLabelNode(text: "encounterState:normal")
        node.fontSize = 10
        node.fontColor = UIColor(red: 0.6, green: 0.4, blue: 1, alpha: 0.55)
        node.horizontalAlignmentMode = .left
        node.verticalAlignmentMode = .top
        node.position = CGPoint(x: 4, y: size.height - 32)
        node.zPosition = 10_000
        addChild(node)
        debugEncounterState = node
        refreshDebugEncounterState()
    }

    /// Pure formatter for the encounterState mirror — kept static and
    /// side-effect-free so PenguinSlideTests can pin the exact string format
    /// EncounterUITests (gyu.22) and agent-device scripts will match on.
    /// `volley=resolved/total hp=n` are the bead-contract fields; the
    /// trailing child counts let tests assert no node leakage across
    /// repeated enter/exit cycles (w stable, e back to 0 after each outro).
    static func debugEncounterStateText(phase: String,
                                        resolved: Int,
                                        total: Int,
                                        hp: Int,
                                        worldChildren: Int,
                                        encounterChildren: Int) -> String {
        "encounterState:\(phase) volley=\(resolved)/\(total) hp=\(hp)"
            + " w=\(worldChildren) e=\(encounterChildren)"
    }

    /// Single rewrite site for the encounterState label. Called on every
    /// phase change (transition(to:)), every ball resolution
    /// (registerEncounterBallResolved), and every HP change
    /// (penguin.onHealthChanged) so XCUITests and agent-device get a
    /// synchronous state read with zero timing dependence.
    private func refreshDebugEncounterState() {
        debugEncounterState?.text = Self.debugEncounterStateText(
            phase: debugPhaseName(phase),
            resolved: encounterResolvedCount,
            total: encounterSystem.plan?.count ?? 0,
            hp: penguin?.hp ?? 0,
            worldChildren: worldRoot.children.count,
            encounterChildren: encounterRoot.children.count)
    }

    // Tap target forcing the encounter intro — same hidden-SKLabelNode
    // recipe as debugForceGameOver (label nodes are the only SpriteKit
    // nodes XCUITest's accessibility traversal surfaces; "element not
    // found" usually means a Release build). touchesBegan routes the tap:
    // auto-starts a pre-start round, then beginEncounterPresentation() +
    // transition(to: .encounterIntro); ignored unless phase == .normal
    // and the round is alive (penguinslide-gyu.21).
    private static let debugForceEncounterLabel = "debugForceEncounter"

    private func installDebugForceEncounter() {
        let node = SKLabelNode(text: Self.debugForceEncounterLabel)
        node.name = Self.debugForceEncounterLabel
        node.fontSize = 10
        node.fontColor = UIColor(red: 1, green: 0.5, blue: 0, alpha: 0.55)
        node.horizontalAlignmentMode = .left
        node.verticalAlignmentMode = .top
        // Next slot down the debug corner stack (14 pt rows: forceGameOver
        // at -4, closeCall at -18, encounterState at -32).
        node.position = CGPoint(x: 4, y: size.height - 46)
        node.zPosition = 10_000
        addChild(node)
    }

    private func debugPhaseName(_ p: GamePhase) -> String {
        switch p {
        case .normal:          return "normal"
        case .encounterIntro:  return "intro"
        case .encounter:       return "encounter"
        case .encounterOutro:  return "outro"
        }
    }
    #endif
}
