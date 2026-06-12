# Snowball Impact Rework — kill the box, shatter like icicles

Date: 2026-06-12 · Author: VioletPlateau (with Mina's device feedback) · Status: approved-by-feedback, implementing

## Problem (observed on device by Mina)

Snowball impacts (on Papi and at the near plane) render as a **white square**
with faint art inside, and don't read as an animation at all.

**Root cause (verified by inspecting the asset):** the SpriteCook sheet
`snowball_impact_burst.png` has an opaque white background baked into all 8
frames (alpha channel present but background not transparent), and frames 6–8
are nearly blank white rectangles. `EncounterFX.playHitBurst` animates the
sheet correctly — every frame is just a white card. No code bug; bad asset.

## Decision

Replace the sheet-based burst with the **icicle-shatter recipe** (Mina's
explicit spec: "like the icicles bursting … follows gravity … has a noise"):

1. **Gravity snow chunks** — on every resolved hit, spawn 6–10 small rounded
   snow-chip sprites (cached texture, never SKShapeNode-per-particle) launched
   radially with upward bias, integrated manually (`vy -= g·dt`) in a new
   `EncounterFX.update(dt:)` ticked from the encounter phase bodies. dt == 0
   sentinel = no-op; game-over freeze = ticks stop = coherent frozen frame;
   `reset()` scrubs. Sized/launched × the avatar depth scale. Fade by lifetime
   fraction in the same tick (no SKActions for shards).
2. **Powder puff** — one soft cached radial puff at the impact point
   (scale-up + fade via tracked one-shot SKAction, pause-registered), so the
   chunk burst has a core. Absorbed (i-frame) hits: fewer chunks, dimmer puff,
   same as the icicle "softer pop".
3. **Sound** — keep the existing `snowball_impact.caf` trigger (already wired
   in SnowMonsterEncounterSystem); regenerate the sample via ElevenLabs
   (`/sound-effects`): wet snow splat + icy crunch, punchy, < 1 s.
4. **Remove the sheet path** — delete `SnowballBurst.imageset`, the
   `Sprite.snowballBurst` case, `EncounterAnimations.snowballBurst*`, and the
   burst-sheet knobs; mark the manifest entry retired (history kept). Update
   EncounterFXTests / animation tests accordingly.
5. **NOT regenerating a burst sheet via SpriteCook** — the box came from a
   generated sheet; procedural chunks match the icicle FX exactly and cannot
   have background artifacts. (Revisit only if Mina wants a fancier core
   splash after feeling this version.)

## Non-goals

- Catch-the-snowball mechanic: separate design decision, asked to Mina.
- Encounter pacing/ground: shipped earlier (fr7/hhz), awaiting device sign-off.

## Verification

Simulator embargo still on → compile gate (`xcodebuild build-for-testing`,
generic destination) + pure-logic unit tests compile; runtime suites deferred
to `penguinslide-x06`; feel sign-off by Mina on device.
