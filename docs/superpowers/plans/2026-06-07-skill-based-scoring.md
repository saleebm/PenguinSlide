# Skill-Based Scoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reward close-call icicle dodges with a severity-scaled bonus and a consecutive-dodge combo multiplier, with combo + floating-`+N` HUD feedback.

**Architecture:** `IcicleSystem` detects a survived landing whose existing `severity` (0…1, from `shakeRadius`) clears a threshold and fires a new `onCloseCall(severity, point)` closure. `GameScene` owns combo/bonus state, turns the event into points, and resets on clip/restart. `HUDController` renders the combo label and floating bonus. `severity`/`shakeRadius` stays the single source of truth — no new radius.

**Tech Stack:** Swift 5, SpriteKit, iOS 17+. Source of truth project is `project.yml` (xcodegen); no `project.yml` change here. No Swift unit-test target exists — gameplay is verified by **compile** (`./run-sim.sh`) and **manual device runs** (`./run-device.sh`), per `TESTING.md`. Each task ends in a compile + commit; manual gameplay verification is the final task.

**Spec:** `docs/superpowers/specs/2026-06-07-skill-based-scoring-design.md`

---

## File Structure

- **Modify** `PenguinSlide/Tuning.swift` — add a `Tuning.Score` sub-enum (knobs only).
- **Modify** `PenguinSlide/IcicleSystem.swift` — add `onCloseCall` closure property; fire it at the landing site.
- **Modify** `PenguinSlide/HUDController.swift` — add `comboLabel`; add `showCombo`/`hideCombo`/`floatBonus`.
- **Modify** `PenguinSlide/GameScene.swift` — add combo/bonus state; wire the callback; change the score line; combo decay; `registerCloseCall`; reset on accepted hit; reset in `restart()`.
- **Modify** `README.md` — add `Score` rows to the "Where to tweak difficulty" table.

---

### Task 1: Add `Tuning.Score` knobs

**Files:**
- Modify: `PenguinSlide/Tuning.swift` (insert a new enum; the `Feel` enum starts at `:71`)

- [ ] **Step 1: Add the `Score` enum**

Insert this immediately **before** `enum Feel {` (currently `Tuning.swift:71`), so it sits between `Chase`/`Icicle` and `Feel` in the file:

```swift
    /// Skill-based scoring (penguinslide-y7f). A "close-call" is a *survived*
    /// icicle landing — reaching the landing code already means the penguin
    /// dodged it — whose `Feel.shakeRadius`-derived `severity` clears
    /// `closeCallSeverity`. Severity is the single source of truth for "how
    /// close"; there is intentionally no separate close-call radius.
    enum Score {
        /// Passive survival points per second. Unchanged value; relocated
        /// from the literal `10` in GameScene's score line.
        static let survivalRate: CGFloat = 10
        /// A survived landing with `severity >= this` counts as a scored
        /// close-call. 0.5 ≈ within 70pt (half of `Feel.shakeRadius`).
        static let closeCallSeverity: CGFloat = 0.5
        /// Base points for a close-call, before severity and combo scaling.
        static let closeCallBase: Int = 50
        /// Max seconds between close-calls to keep a combo streak alive.
        static let comboWindow: TimeInterval = 2.5
        /// Combo multiplier ceiling so a long streak can't run away.
        static let comboMaxMultiplier: CGFloat = 5.0
    }

```

- [ ] **Step 2: Compile**

Run: `./run-sim.sh`
Expected: build succeeds (app installs/launches on the simulator). The new enum is unused so far — that is fine; Swift does not warn on an unused enum.

- [ ] **Step 3: Commit**

```bash
git add PenguinSlide/Tuning.swift
git commit -m "feat(scoring): add Tuning.Score knobs (penguinslide-y7f)"
```

---

### Task 2: Emit `onCloseCall` from IcicleSystem

**Files:**
- Modify: `PenguinSlide/IcicleSystem.swift` (closure property near the haptic generators ~`:61`; fire site at the landing block ~`:510`)

- [ ] **Step 1: Declare the outbound closure**

Insert immediately **after** the `hapticLight` declaration (currently `IcicleSystem.swift:62`):

```swift

    /// Fired when a *survived* landing clears the close-call severity
    /// threshold. (severity 0…1, landingPoint in scene coords.) GameScene
    /// turns this into a scored dodge; IcicleSystem stays pure detection and
    /// knows nothing about score. Mirrors `Penguin.onHealthChanged`.
    var onCloseCall: ((CGFloat, CGPoint) -> Void)?
```

- [ ] **Step 2: Fire it at the landing site**

In the landing block, find this existing code (currently `IcicleSystem.swift:510-513`):

```swift
                if severity > 0 {
                    hapticLight.impactOccurred()
                    screenShake(near: landingPoint.x)
                }
```

Insert immediately **after** that `if` block (before `icicle.removeFromParent()`):

```swift
                // Scored close-call: a stricter subset of the shake band, so
                // it never fires for distant landings.
                if severity >= Tuning.Score.closeCallSeverity {
                    onCloseCall?(severity, landingPoint)
                }
```

- [ ] **Step 3: Compile**

Run: `./run-sim.sh`
Expected: build succeeds. `onCloseCall` is nil (not yet wired), so behaviour is unchanged.

- [ ] **Step 4: Commit**

```bash
git add PenguinSlide/IcicleSystem.swift
git commit -m "feat(scoring): emit onCloseCall on threshold landings (penguinslide-y7f)"
```

---

### Task 3: HUD combo label + floating bonus

**Files:**
- Modify: `PenguinSlide/HUDController.swift` (add stored property; init it after `scoreLabel`; add three methods)

- [ ] **Step 1: Add the stored property**

After the `bestLabel` property declaration (currently `HUDController.swift:21`):

```swift
    private let comboLabel: SKLabelNode
```

- [ ] **Step 2: Build the combo label in `init`**

In `init`, immediately **after** the score-label block ends with `self.scoreLabel = s` (currently `HUDController.swift:46`), insert:

```swift

        let c = SKLabelNode(fontNamed: Self.safeFont(named: "AvenirNext-Bold"))
        c.fontSize = 28
        c.fontColor = UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1)  // warm gold
        c.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height - 165)
        c.zPosition = 50
        c.horizontalAlignmentMode = .center
        c.alpha = 0
        c.text = ""
        scene.addChild(c)
        self.comboLabel = c
```

- [ ] **Step 3: Add the three presentation methods**

Immediately **after** `func setBest(_ value: Int) { bestLabel.text = "Best: \(value)" }` (currently `HUDController.swift:68`):

```swift

    /// Show / refresh the combo multiplier. Called when combo >= 2.
    func showCombo(_ combo: Int) {
        comboLabel.text = "×\(combo)"
        comboLabel.removeAction(forKey: "comboFx")
        comboLabel.run(.sequence([
            .group([.fadeIn(withDuration: 0.1), .scale(to: 1.3, duration: 0.1)]),
            .scale(to: 1.0, duration: 0.12)
        ]), withKey: "comboFx")
    }

    /// Fade the combo label out (streak ended or window lapsed).
    func hideCombo() {
        comboLabel.removeAction(forKey: "comboFx")
        comboLabel.run(.fadeOut(withDuration: 0.2))
    }

    /// Float a "+N" up from a landing point, then remove it. Added to the
    /// scene in scene coordinates — same pattern the shard burst uses.
    func floatBonus(_ amount: Int, at point: CGPoint) {
        guard let scene else { return }
        let label = SKLabelNode(fontNamed: Self.safeFont(named: "AvenirNext-Bold"))
        label.text = "+\(amount)"
        label.fontSize = 22
        label.fontColor = UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1)
        label.position = point
        label.zPosition = 60
        label.horizontalAlignmentMode = .center
        scene.addChild(label)
        label.run(.sequence([
            .group([
                .moveBy(x: 0, y: 60, duration: 0.7),
                .sequence([.wait(forDuration: 0.4), .fadeOut(withDuration: 0.3)])
            ]),
            .removeFromParent()
        ]))
    }
```

- [ ] **Step 4: Compile**

Run: `./run-sim.sh`
Expected: build succeeds. Methods are unused so far (no caller) — Swift does not warn on unused methods.

- [ ] **Step 5: Commit**

```bash
git add PenguinSlide/HUDController.swift
git commit -m "feat(scoring): HUD combo label + floating bonus (penguinslide-y7f)"
```

---

### Task 4: GameScene — wire state, scoring, combo lifecycle

**Files:**
- Modify: `PenguinSlide/GameScene.swift` (state props ~`:50`; callback wire ~`:110`; score line `:359`; decay in `update` ~`:352`; new method; hit reset `:374`; restart reset `:425`)

- [ ] **Step 1: Add combo/bonus state**

Immediately **after** the `score` property's closing `}` (currently `GameScene.swift:52`, the line `}` after `didSet { hud?.setScore(score) }`):

```swift
    // Skill scoring (penguinslide-y7f). `bonusPoints` accumulates close-call
    // rewards on top of survival time; `combo` is the live streak length;
    // `lastCloseCallTime` is the `elapsed` stamp of the last dodge.
    private var bonusPoints: Int = 0
    private var combo: Int = 0
    private var lastCloseCallTime: TimeInterval = 0
```

- [ ] **Step 2: Wire the callback in setup**

Immediately **after** `penguin.onHealthChanged = { [weak self] hp in self?.hud.setHealth(hp) }` (currently `GameScene.swift:110`):

```swift
        // Close-call dodges flow in from IcicleSystem; GameScene owns the
        // scoring state and HUD push (penguinslide-y7f).
        icicles.onCloseCall = { [weak self] severity, point in
            self?.registerCloseCall(severity: severity, at: point)
        }
```

- [ ] **Step 3: Replace the score line and add combo decay**

In `update(_:)`, find this block (currently `GameScene.swift:354-359`):

```swift
        penguin.update(dt: dt, tilt: currentTilt())
        icicles.update(dt: dt, elapsed: elapsed)

        // Score grows steadily so survival is rewarded even without dodges.
        // Bead penguinslide-y7f will add a close-call bonus on top of this.
        score = Int(elapsed * 10)
```

Replace it with:

```swift
        // Expire a lapsed combo BEFORE this frame's landings are evaluated,
        // so a dodge this frame can never be decayed in the same frame.
        if combo > 0 && elapsed - lastCloseCallTime > Tuning.Score.comboWindow {
            combo = 0
            hud.hideCombo()
        }

        penguin.update(dt: dt, tilt: currentTilt())
        icicles.update(dt: dt, elapsed: elapsed)  // may fire onCloseCall

        // Survival drip (unchanged rate) plus accumulated close-call bonus.
        score = Int(elapsed * Tuning.Score.survivalRate) + bonusPoints
```

- [ ] **Step 4: Add `registerCloseCall`**

Immediately **after** the `update(_:)` method's closing brace (currently `GameScene.swift:360`, the `}` before `// MARK: - Contact`):

```swift

    /// Turn a survived close-call into points. Combo decay already ran this
    /// frame (top of `update`), so a lapsed streak is already 0 here and the
    /// increment is unconditional. Bonus scales with severity (closer = more)
    /// and the capped combo multiplier.
    private func registerCloseCall(severity: CGFloat, at point: CGPoint) {
        combo += 1
        lastCloseCallTime = elapsed
        let multiplier = min(CGFloat(combo), Tuning.Score.comboMaxMultiplier)
        let bonus = Int((CGFloat(Tuning.Score.closeCallBase) * severity * multiplier).rounded())
        bonusPoints += bonus
        hud.floatBonus(bonus, at: point)
        if combo >= 2 { hud.showCombo(combo) }
    }
```

- [ ] **Step 5: Reset combo on an accepted hit**

In `didBegin(_:)`, find (currently `GameScene.swift:374-375`):

```swift
        let accepted = penguin.tryTakeHit(from: icicleNode.position.x)
        icicles.onIcicleHitPenguin(icicle: icicleNode, at: contact.contactPoint, accepted: accepted)
```

Insert immediately **after** those two lines:

```swift
        // Getting clipped breaks the streak; i-frame saves (accepted == false)
        // do not.
        if accepted {
            combo = 0
            hud.hideCombo()
        }
```

- [ ] **Step 6: Reset scoring state in `restart()`**

In `restart()`, find (currently `GameScene.swift:425-426`):

```swift
        elapsed = 0
        score = 0
```

Replace with:

```swift
        elapsed = 0
        score = 0
        bonusPoints = 0
        combo = 0
        lastCloseCallTime = 0
        hud.hideCombo()
```

- [ ] **Step 7: Compile**

Run: `./run-sim.sh`
Expected: build succeeds and the app launches. (The simulator has no gyro, so dodges won't trigger from tilt there — full gameplay check is Task 6 on device.)

- [ ] **Step 8: Commit**

```bash
git add PenguinSlide/GameScene.swift
git commit -m "feat(scoring): close-call bonus + combo lifecycle (penguinslide-y7f)"
```

---

### Task 5: Document the Score knobs in README

**Files:**
- Modify: `README.md` ("Where to tweak difficulty" table)

- [ ] **Step 1: Locate the table**

Run: `grep -n "Where to tweak difficulty" README.md`
Expected: one match. Read the table that follows it to confirm its column layout (knob | effect, grouped by subsystem).

- [ ] **Step 2: Add Score rows**

Add these rows under a new `Score` group in the "Where to tweak difficulty" table, matching the existing column format (adjust column separators to match the table you found — this assumes a `Knob | Effect` shape):

```markdown
| `Score.survivalRate` | Passive points per second of survival. |
| `Score.closeCallSeverity` | How close a survived landing must be (0–1 severity) to score as a dodge; 0.5 ≈ 70pt. |
| `Score.closeCallBase` | Base points per close-call, before severity and combo scaling. |
| `Score.comboWindow` | Seconds allowed between dodges to keep the combo streak. |
| `Score.comboMaxMultiplier` | Combo multiplier ceiling. |
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(scoring): document Tuning.Score knobs (penguinslide-y7f)"
```

---

### Task 6: Manual gameplay verification (physical device)

**Files:** none (verification only)

- [ ] **Step 1: Build and launch on a physical iPhone**

Run: `./run-device.sh`
Expected: app installs and launches on the device. Tap to start.

- [ ] **Step 2: Verify close-call bonus + combo**

Tilt to slide the penguin so icicles land *close* (within ~70pt) without hitting it. Confirm:
- A gold `+N` floats up from each close landing point.
- After two close-calls within ~2.5s, a `×2` (then `×3`…) combo label appears under the score and the score jumps by more than the survival drip.
- Letting ~2.5s pass with no close-call fades the combo label and the next dodge restarts at `×1`.

- [ ] **Step 3: Verify reset semantics**

- Take a real hit (lose a heart) mid-combo → the combo label disappears and the next dodge starts at `×1`.
- Play a round mostly idle in a safe lane vs. a round actively threading icicles → the active round's score is clearly higher.
- Game over, then Play Again → score, combo, and `+N` all start clean (no carried-over bonus).

- [ ] **Step 4: Update the bead**

```bash
br update penguinslide-y7f --status in_progress
# after the above checks pass and the work is merged:
br close penguinslide-y7f
```

Note: this unblocks `penguinslide-ga8` (a real severity-thresholded close-call now exists to assert against) and gives `penguinslide-9f8` something real to document — both stay separate beads.

---

## Self-Review

**Spec coverage:**
- `Tuning.Score` knobs → Task 1. ✓
- Severity-thresholded `onCloseCall` from IcicleSystem → Task 2. ✓
- Score = survival + bonus (structural change) → Task 4 Step 3. ✓
- Combo decay / `registerCloseCall` / severity-scaled bonus + capped multiplier → Task 4 Steps 3–4. ✓
- Reset on accepted hit → Task 4 Step 5. ✓
- Reset on restart → Task 4 Step 6. ✓
- HUD combo label + floating `+N` → Task 3. ✓
- README tuning rows → Task 5. ✓
- Acceptance (idle < active; combo increments; resets on clip/window/restart) → Task 6. ✓
- Out of scope (ga8/9f8, physics tuning) → noted, not built. ✓

**Type consistency:** `onCloseCall: ((CGFloat, CGPoint) -> Void)?` declared (Task 2) and assigned with matching `(severity, point)` params (Task 4 Step 2); `registerCloseCall(severity:at:)` signature matches its caller; `showCombo(_:)`/`hideCombo()`/`floatBonus(_:at:)` defined (Task 3) match call sites (Task 4). `Tuning.Score.*` names match between Task 1 and Tasks 2/4/5. Consistent.

**Placeholder scan:** no TBD/TODO/"handle edge cases"; every code step shows complete code. The only template-dependent step is Task 5 Step 2 (README column format), which instructs matching the actual table shape found in Step 1 — acceptable since the table format is read at execution time.
