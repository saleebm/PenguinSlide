# Testing a physics game deterministically with a debug accessibility hook

PenguinSlide is a physics game. Icicles fall at speeds that ramp over ninety seconds. The penguin slides on tilt input that doesn't work on the simulator. When you try to write a test that asserts "the game-over screen appears after the penguin dies," you immediately run into the problem: how do you reliably kill the penguin?

The naive answer is "wait." Tilt the simulator keyboard, dodge poorly, let the penguin take three hits. In practice the wait is somewhere between five seconds (lucky RNG) and ninety seconds (very lucky RNG). The test is flaky, slow, and unrelated to what you actually want to verify: that the game-over panel appears, the score reads correctly, and the tap-to-play-again button works.

The fix is one tiny piece of debug-only code: an invisible-ish accessibility node that XCUITest can tap. Game-over fires instantly through the real production code path. No physics, no waiting.

## The hook itself

Inside `GameScene`, gated behind `#if DEBUG`:

```swift
// PenguinSlide/GameScene.swift:392
#if DEBUG
// MARK: - Debug hooks

// Mechanism: hidden accessibility node — only option XCUITest can drive
// mid-round without touching ContentView.
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
```

`didMove(to:)` calls `installDebugForceGameOver()` once on scene boot. A small, semi-transparent red "debugForceGameOver" label appears at the top-left of the screen during debug builds. Release builds don't even compile this code; the symbol literally doesn't exist in App Store binaries.

The comment in there saved us an hour. We initially used an `SKSpriteNode` with `isAccessibilityElement = true` and a label set programmatically, exactly the pattern Apple's docs suggest for arbitrary views. XCUITest never saw it. The accessibility tree just... didn't include it. Turns out SpriteKit's automatic accessibility traversal only surfaces `SKLabelNode`s. Plant an `SKSpriteNode` with whatever accessibility configuration you like and the framework silently prunes it. The label *text* becomes the accessibility identifier; no `isAccessibilityElement = true` needed.

## The tap router

The label is a node, not a button. Tapping it just creates a touch in SpriteKit's scene graph; we need the scene to recognize that touch and trigger game-over. `touchesBegan(_:with:)` handles this with a `#if DEBUG` branch at the top:

```swift
// PenguinSlide/GameScene.swift:258
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
    // ...normal touch handling (start round, restart, etc.)
}
```

Key thing: this routes through the *real* `triggerGameOver()`. Death animation, game-over sound, score persistence, HUD overlay: every production code path runs exactly as it would after a natural death. The test isn't mocking the death; it's triggering it deterministically.

The `if !isStarted` guard handles the edge case where a test taps the debug node before the title screen is dismissed. Without it, a force-game-over from the title screen would leave `isStarted = false` and the post-restart tap logic would dismiss the wrong overlay.

## The test side

XCUITest calls into this with one line:

```swift
// PenguinSlideUITests/PenguinSlideUITests.swift:28
// Drive game-over via the #if DEBUG accessibility hook installed by
// GameScene (penguinslide-ei0). Removes the 30 s physics-dependent
// wait and decouples the test from icicle timing.
app.otherElements["debugForceGameOver"].tap()
```

XCUITest finds the node by its accessibility label (which is just the `text` we set on the `SKLabelNode`), sends a synthetic tap, and `touchesBegan` does the rest. The whole test for "starting a round and reaching game-over" takes about two seconds:

```swift
// PenguinSlideUITests/PenguinSlideUITests.swift:20
func testStartTriggersGameAndShowsGameOver() throws {
    let app = XCUIApplication()
    app.launch()

    let tapToStart = app.otherElements["Tap to start"]
    XCTAssertTrue(tapToStart.waitForExistence(timeout: 5))
    tapToStart.tap()

    app.otherElements["debugForceGameOver"].tap()

    let tapAgain = app.otherElements["Tap to play again"]
    XCTAssertTrue(tapAgain.waitForExistence(timeout: 2))
}
```

The same hook works for our agent-device-driven smoke test, which uses it to drive a four-screenshot UI loop (title → playing → game-over → restarted). [`TESTING.md`](../../TESTING.md) documents both paths.

## What this is and isn't

This is a *test seam*, not a backdoor: a piece of code that exists specifically so tests can poke a specific internal state from outside the public API. Crucially:

- It's `#if DEBUG`. Release binaries don't include it.
- It triggers the same code path a natural death would have. No mock, no shortcut around the system under test.
- It's discoverable. The label is visibly rendered during debug builds and shows up in the accessibility tree.

The alternative would have been to expose a `forceGameOver()` method on `GameScene`, make `GameScene` accessible from `ContentView`, and have a debug toggle in SwiftUI. That works, but it requires every test entry point to live in production code. The accessibility-hook pattern keeps the test surface bolted onto the scene where the action is, without polluting the SwiftUI side.

## What it costs

- **The SKLabelNode constraint is invisible.** Anyone who hasn't been burned will reach for `SKSpriteNode` first. The comment at the install site is the only thing standing between them and an hour of debugging.
- **Release builds aren't covered by these tests.** The hook doesn't exist in Release, so the tests literally can't run against a Release binary. We mitigate this by running the smoke test against the Debug build that we ship the simulator from, and doing manual validation on Release before App Store submission.
- **Tests gate on accessibility labels, not types.** Renaming the `Tap to start` SKLabelNode would silently break two tests. `TESTING.md` flags this explicitly in the "Known gotchas" section.
- **The debug node is *visible* in debug.** Small red "debugForceGameOver" in the corner of every debug screenshot. We decided this was a feature (it's a marker that you're running a debug build), but it does show up in screenshots intended for visual review.
- **You have to remember to install it.** `installDebugForceGameOver()` is called in `didMove(to:)`. If a future refactor creates a new scene without copying that line, the test silently fails to find the node. The accessibility tree just doesn't have it.

## The general shape

Two rules from this.

1. **Build the test seam where the system actually lives.** Don't route every test through ContentView or a UIKit shim if the thing you want to test is in the SpriteKit scene. Drop a labeled `SKLabelNode` and have XCUITest tap it. The closer the seam to the system, the less plumbing the test needs.

2. **Use accessibility labels as your test API.** Accessibility is already the cross-process way to address UI elements on Apple platforms. If you can name an element such that VoiceOver could read it out, XCUITest can find it. You don't need a parallel `id="test-foo"` system; you have one for free.

The bigger pattern: physics, animation, RNG, and timing are all enemies of deterministic tests. Wherever your code has those, build a `#if DEBUG`-gated seam that lets the test bypass the nondeterminism while still exercising the real failure mode. Calling that hook cheating misses the point; it's the difference between a 2-second test and a 30-second flake.
