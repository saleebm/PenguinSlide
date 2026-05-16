# Live tuning: from `let` constants to a UserDefaults-backed struct

Every game lives or dies on its numbers. How fast does the penguin slide? How long is the invulnerability window? How wide is the ice strip? How does the spawn rate ramp? PenguinSlide has dozens of these knobs, and for most of the project's life they lived in `Tuning.swift` as `static let` constants. Compile time only. Want a different value? Edit the source, rebuild, ship.

That works fine until you want to iterate on game feel on a real device. Then it doesn't.

This is the story of a refactor that took a couple of hours of careful work, changed zero call sites, and turned every penguin-input knob into a value the game can persist to disk and read back at runtime. The data layer is done; the UI is a follow-up; the architecture is the interesting part.

## Where we started

The old `Tuning.Penguin` was a flat namespace of `static let`:

```swift
enum Tuning {
    enum Penguin {
        static let maxSpeed: CGFloat = 1000
        static let iFrameDuration: TimeInterval = 1.0
        static let leanMaxAngle: CGFloat = 0.30
        // ...etc, ~18 knobs
    }
    enum Icicle { /* ... */ }
}
```

Call sites read these directly:

```swift
let targetVx = tilt * Tuning.Penguin.maxSpeed
let alpha = 1 - exp(-Tuning.Penguin.tiltResponseRate * dt)
invulnerableUntil = elapsed + Tuning.Penguin.iFrameDuration
```

Eighteen of them, scattered across `Penguin.swift`, `IcicleSystem.swift`, `HUDController.swift`, and `GameScene.swift`. Touching the surface meant touching every call site. So we needed a refactor that left those eighteen call sites alone.

## Where we ended up

The trick is that `static let` and `static var` of a struct have the same syntax at the read site. `Tuning.Penguin.maxSpeed` is valid in both worlds — once when `Tuning.Penguin` is a namespace with a `static let maxSpeed`, and again when `Tuning.Penguin` is a `static var` of a struct with an *instance* property `maxSpeed`. Same dotted access, different mechanism.

So `Tuning.Penguin` became this:

```swift
// PenguinSlide/Tuning.swift:17
enum Tuning {
    /// Penguin input + feel. Now a mutable struct (see `PenguinTuning`)
    /// so a future settings UI or debug menu can override knobs at
    /// runtime. Call sites stay the same: `Tuning.Penguin.maxSpeed` etc.
    /// First access loads any persisted overrides from UserDefaults.
    static var Penguin: PenguinTuning = .loadFromUserDefaults()
    // ...other namespaces unchanged
}
```

And the values moved to a new file:

```swift
// PenguinSlide/PenguinTuning.swift:22
struct PenguinTuning: Codable {
    var maxSpeed: CGFloat = 1000
    var tiltCurve: CGFloat = 1.5
    var iFrameDuration: TimeInterval = 1.0
    // ...
}
```

Eighteen call sites: unchanged. Two files changed: `Tuning.swift` and a new `PenguinTuning.swift`. The compiler did the verification — if any call site had referenced these as `static let`s in a way that broke with `var`s, it would have failed the build.

## Persistence with a versioned key

The struct is `Codable`, so JSON round-trip is one line each way:

```swift
// PenguinSlide/PenguinTuning.swift:121
static func loadFromUserDefaults(_ defaults: UserDefaults = .standard) -> PenguinTuning {
    guard let data = defaults.data(forKey: userDefaultsKey),
          let decoded = try? JSONDecoder().decode(PenguinTuning.self, from: data)
    else { return PenguinTuning() }
    return decoded
}

func saveToUserDefaults(_ defaults: UserDefaults = .standard) {
    guard let data = try? JSONEncoder().encode(self) else { return }
    defaults.set(data, forKey: Self.userDefaultsKey)
}

static func resetUserDefaults(_ defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: userDefaultsKey)
}
```

The key is **versioned**:

```swift
// PenguinSlide/PenguinTuning.swift:116
// Versioned so a future schema break (renamed/removed field) can be
// handled by bumping the key — old data is then ignored and defaults
// re-seed the active tuning.
private static let userDefaultsKey = "PenguinTuning.v1"
```

`v1` for a reason. The day we rename `iFrameDuration` to `invulnerabilityWindow`, or remove `iceDecayRate` entirely, `JSONDecoder()` will fail to decode the old shape — and silently return defaults, which is exactly what we want. Bumping to `PenguinTuning.v2` makes the new key empty on first launch, defaults re-seed, and any user with persisted v1 overrides gets a clean slate. No migration code, no try/catch dance, no ghosts.

This is the same pattern Apple uses for `NSCoder.requiresSecureCoding` schema breaks. Pick a key suffix; bump it when the shape changes.

## Tunable vs. non-tunable: keep the line clean

Not every property in `PenguinTuning` belongs in the JSON. The shield-ring color is a deliberate, calibrated value (it's part of [making i-frames legible](04-i-frames-game-feel.md)) — a settings UI making it red by accident would break the contrast contract. So it's a computed property *outside* the Codable surface:

```swift
// PenguinSlide/PenguinTuning.swift:101
// MARK: - Visual constants (non-tunable)

/// Shield-ring stroke colour. Cyan was chosen to contrast cleanly
/// with the red damage flash so the two states read as different
/// events at a glance. Not part of the Codable surface — SKColor
/// doesn't bridge to JSON cleanly and this isn't a difficulty knob.
var shieldRingColor: SKColor { Self.defaultShieldRingColor }
private static let defaultShieldRingColor =
    SKColor(red: 0.5, green: 0.9, blue: 1.0, alpha: 1.0)
```

`SKColor` doesn't `Codable` cleanly, *and* we don't want it tuned. Both reasons line up: it's a computed property of `SKColor`, backed by a `private static let`. Encoder skips it (no stored value). Decoder doesn't try to restore it. It's accessed exactly as if it were a stored field — `Tuning.Penguin.shieldRingColor` — but it lives outside the persistence layer.

This is a useful pattern. Anything that's currently `static let` and you wouldn't want a debug UI to mess with should stay outside the JSON surface, even if it lives on the same struct.

## What's wired, what isn't

Honesty section. The data layer is complete: load on first access, save when called, reset when called. `Tuning.Penguin = PenguinTuning()` works for a live revert.

What's *not* there yet: the settings UI to actually expose these as sliders. `SettingsView.swift` currently shows player name, how-to-play, and version. The file's header comment plans for it:

```swift
//  `PenguinTuning` sliders into this same Form.
```

That's the next increment. The architecture is ready for it — drop a `Slider` bound to `$Tuning.Penguin.maxSpeed`, call `saveToUserDefaults()` on commit. Five or six knobs at most for the initial UI; the rest stay developer-only.

## What it costs

- **Two files instead of one.** `Tuning.swift` is now a thin wrapper; `PenguinTuning.swift` holds the values. New contributors have to know to look in both.
- **Mutability is now possible.** With `static let`, the compiler guaranteed no one could mutate `maxSpeed` from a random call site. With `static var` on a struct, that protection is gone — anyone could write `Tuning.Penguin.maxSpeed = 9999`. We rely on discipline; consider adding a wrapper if the codebase grows.
- **First access is suddenly heavier.** `static var Penguin: PenguinTuning = .loadFromUserDefaults()` runs the JSON decode on the first reference. Fine for our scale (one decode at app start), but worth knowing — old `static let` was zero-cost at access.
- **Codable can drift silently.** If a property type changes (`Int` → `Double`), `JSONDecoder` returns `nil` and we silently re-seed defaults. The user-visible effect is "I lost my settings." Versioned key + integration test catches it; nothing else does.
- **The persistence surface is implicit.** Every `var` on `PenguinTuning` is part of the user-facing config schema, whether you intended it or not. Adding a new field means agreeing it can persist. Compiler doesn't enforce that thinking.

## The general shape

This isn't a "tuning system." It's a tiny refactor with two careful choices:

1. **Use `static var Container: Struct` instead of `enum Container { static let ... }`** when you want the values to be mutable. Call sites don't notice. Everything downstream gets the live values for free.
2. **Version the persistence key.** `Key.v1`, `Key.v2`. When the schema breaks, bump the suffix and let defaults re-seed. Refusing to write a migration is sometimes the right call.

The win isn't "tunability." The win is *unblocking* tunability. We didn't ship sliders yet, but the day we want to, every wiring decision is already made. That's what the refactor bought.

If you're sitting on a flat namespace of `static let` constants and starting to feel them get in your way — the lift is small, the call-site change is zero, and the day you wire a debug UI you'll be glad you did it.
