//
//  EncounterDeathAccountingTests.swift
//  PenguinSlideTests
//
//  penguinslide-gyu.19 acceptance: "Death on the FINAL ball
//  (simultaneous with would-be volley completion) resolves as game
//  over, not outro — hit resolution must precede completion check in
//  the frame; assert ordering in a unit test of the accounting."
//
//  The system contract under test (SnowMonsterEncounterSystem.update's
//  ORDERING CONTRACT doc): within ONE update call the flight sweep
//  fires `onSnowballHit` for a connecting ball strictly BEFORE
//  `checkVolleyCompletion` can fire `onVolleyComplete`. GameScene
//  relies on exactly that ordering — its hit handler runs
//  `triggerGameOver()` (isGameOver = true) synchronously, and its
//  completion handler guards on `!isGameOver` — so a lethal final
//  ball lands as GAME OVER and the would-be outro is suppressed.
//  GameScene's handlers are private; these tests pin the SYSTEM-side
//  accounting ordering and replay the scene's guard logic verbatim on
//  top of it.
//
//  All-hit volleys are forced deterministically: the papi provider
//  TRACKS the oldest unresolved ball's worldX (lateral miss 0 every
//  sweep), so every ball connects the frame its swept depth segment
//  enters the hit slab — no RNG/jitter dependence.
//

import XCTest
import SpriteKit
@testable import PenguinSlide

/// SplitMix64 — tiny, well-distributed, fully deterministic per seed
/// (same helper VolleyOrchestrationTests uses; private there, so
/// redeclared).
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class EncounterDeathAccountingTests: XCTestCase {

    private let sceneSize = CGSize(width: 390, height: 844)
    private let dt: TimeInterval = 1.0 / 60.0

    /// The system holds its parent weakly (the scene owns the tree in
    /// production), so the case retains every parent it makes.
    private var retainedParents: [SKNode] = []

    override func tearDown() {
        retainedParents.removeAll()
        super.tearDown()
    }

    private func makeAllHitSystem(seed: UInt64 = 19)
        -> (system: SnowMonsterEncounterSystem, parent: SKNode) {
        let parent = SKNode()
        retainedParents.append(parent)
        let projector = DepthProjector(sceneSize: sceneSize)
        let system = SnowMonsterEncounterSystem()
        system.configure(parent: parent, projector: projector)
        system.volleyRNG = SplitMix64(seed: seed)
        // Papi "stands on the line": track the oldest unresolved ball
        // laterally so its miss is 0 on the resolution frame — every
        // ball is a guaranteed hit, deterministically.
        system.papiWorldXProvider = { [weak system] in
            system?.snowballs.first(where: { !$0.resolved })?.worldX
                ?? projector.vanishingX
        }
        return (system, parent)
    }

    // MARK: - The accounting ordering (the bead's core assertion)

    /// On the frame the FINAL ball connects, `onSnowballHit` fires
    /// strictly BEFORE `onVolleyComplete` — same update call, hit
    /// first. This is the ordering GameScene's `!isGameOver` guard
    /// stands on.
    func testFinalBallHitFiresBeforeCompletionWithinTheSameUpdateCall() {
        let (system, _) = makeAllHitSystem()

        // (frame, event) trace: `frame` increments once per update call,
        // so equal frame numbers ⇒ the same update call.
        var frame = 0
        var trace: [(frame: Int, event: String)] = []
        system.onSnowballHit = { _, _ in trace.append((frame, "hit")) }
        system.onDodge = { _, _ in trace.append((frame, "dodge")) }
        system.onVolleyComplete = { trace.append((frame, "complete")) }

        system.begin(difficultyProgress: 0)
        guard let plan = system.plan else { return XCTFail("begin computed no plan") }

        var guardTicks = 0
        while !trace.contains(where: { $0.event == "complete" }) && guardTicks < 60 * 90 {
            frame += 1
            system.update(dt: dt, tilt: 0)
            guardTicks += 1
        }

        // Every ball connected; nothing was dodged.
        XCTAssertEqual(trace.filter { $0.event == "hit" }.count, plan.count,
                       "tracking provider must force an all-hit volley")
        XCTAssertEqual(trace.filter { $0.event == "dodge" }.count, 0)

        guard let completeIndex = trace.firstIndex(where: { $0.event == "complete" }) else {
            return XCTFail("volley never completed (hang)")
        }
        XCTAssertEqual(completeIndex, trace.count - 1, "completion must be the final event")
        let finalHitIndex = completeIndex - 1
        XCTAssertEqual(trace[finalHitIndex].event, "hit",
                       "the event immediately preceding completion must be the final hit")
        // The bead's exact clause: hit resolution precedes the
        // completion check IN THE FRAME — same update call, hit first.
        XCTAssertEqual(trace[finalHitIndex].frame, trace[completeIndex].frame,
                       "final hit and completion must share one update call")
        XCTAssertEqual(system.outstandingBalls, 0)
    }

    /// Replay GameScene's handler logic verbatim on the system
    /// callbacks: the hit handler "dies" (isGameOver = true) when the
    /// final hit exhausts HP, and the completion handler applies the
    /// scene's `phase == .encounter && !isGameOver` guard. The lethal
    /// final ball must therefore resolve as game over — the outro
    /// (and its volley bonus) suppressed.
    func testLethalFinalBallResolvesAsGameOverNotOutro() {
        let (system, _) = makeAllHitSystem(seed: 7)

        var isGameOver = false
        var hits = 0
        var completions = 0
        var outroEntered = false
        var gameOverWasSetWhenCompletionFired: Bool?

        system.begin(difficultyProgress: 0)
        guard let plan = system.plan else { return XCTFail("begin computed no plan") }

        // GameScene.onSnowballHit, distilled: route the hit, then
        // trigger game over when HP runs out. Model HP as exactly
        // enough that the FINAL ball is the lethal one — the bead's
        // "simultaneous with would-be volley completion" worst case.
        system.onSnowballHit = { _, _ in
            hits += 1
            if hits == plan.count && !isGameOver {
                isGameOver = true   // triggerGameOver()'s effect
            }
        }
        // GameScene.onVolleyComplete, distilled: the gyu.19 guard.
        system.onVolleyComplete = {
            completions += 1
            gameOverWasSetWhenCompletionFired = isGameOver
            guard !isGameOver else { return }
            outroEntered = true     // beginOutroPresentation + transition
        }

        var guardTicks = 0
        while completions == 0 && guardTicks < 60 * 90 {
            system.update(dt: dt, tilt: 0)
            guardTicks += 1
        }

        XCTAssertEqual(hits, plan.count)
        XCTAssertEqual(completions, 1,
                       "the system still reports completion (it is outcome-agnostic)")
        XCTAssertEqual(gameOverWasSetWhenCompletionFired, true,
                       "game over must already be in force when completion arrives")
        XCTAssertTrue(isGameOver, "the lethal final ball must end the run")
        XCTAssertFalse(outroEntered,
                       "death on the final ball must resolve as game over, NOT outro")
    }

    // MARK: - Death-freeze + restart hygiene (system side)

    /// A mid-volley death freezes a coherent frame: triggerGameOver's
    /// system-side calls (pauseActions; the update guard stops ticks)
    /// leave the remaining balls in the tree, paused, with the
    /// accounting intact — then restart()'s reset() scrubs everything
    /// back to the same cold state a normal-mode restart sees.
    func testMidVolleyDeathFreezeThenResetRestoresColdState() {
        let (system, parent) = makeAllHitSystem(seed: 3)
        let baseline = parent.children.count

        var isGameOver = false
        var completions = 0
        // Die on the FIRST hit, mid-volley: like GameScene, once the
        // run is over update() is never called again.
        system.onSnowballHit = { _, _ in isGameOver = true }
        system.onVolleyComplete = { completions += 1 }

        system.begin(difficultyProgress: 0)
        var guardTicks = 0
        while !isGameOver && guardTicks < 60 * 90 {
            system.update(dt: dt, tilt: 0)
            guardTicks += 1
        }
        XCTAssertTrue(isGameOver, "first hit never landed (hang)")
        XCTAssertEqual(completions, 0, "death frame is mid-volley, not completion")

        // triggerGameOver's freeze seam: every surviving ball/shadow
        // pauses where it is; nothing leaves the tree.
        system.pauseActions()
        for ball in system.snowballs {
            XCTAssertEqual(ball.node?.isPaused, true)
            XCTAssertEqual(ball.shadow?.isPaused, true)
        }

        // restart() → encounterSystem.reset(): the volley tears down
        // wholesale — zero nodes left, accounting re-armed, and no
        // ghost completion can ever fire from the dead volley.
        system.reset()
        XCTAssertTrue(system.snowballs.isEmpty)
        XCTAssertEqual(system.outstandingBalls, 0)
        XCTAssertEqual(system.throwsMade, 0)
        XCTAssertNil(system.plan)
        XCTAssertFalse(system.volleyActive)
        XCTAssertEqual(parent.children.count, baseline,
                       "restart after an encounter death leaked encounter nodes")

        for _ in 0..<(60 * 5) { system.update(dt: dt, tilt: 0) }
        XCTAssertEqual(completions, 0, "torn-down volley fired a ghost completion")
        XCTAssertTrue(system.snowballs.isEmpty)
    }
}
