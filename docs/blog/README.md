# Building PenguinSlide — blog series

Eight posts on what we built and what we learned shipping a tilt-controlled SpriteKit + SwiftUI game on iOS. Mined from agent session history and the source tree, written for other developers — not for marketing, not for the team retro.

## The posts

| # | Title | Subsystem |
|---|-------|-----------|
| [00](00-bootstrapping-asset-pipeline.md) | Bootstrapping PenguinSlide: SpriteKit, SpriteCook, and ElevenLabs | Pipeline |
| [01](01-bitmap-heroes-procedural-fx.md) | Bitmap heroes, procedural FX: a mixed asset strategy | Rendering |
| [02](02-haptic-budget.md) | Haptic budget: medium for damage, light for saves, silent for near-misses | Feedback |
| [03](03-arcade-audio-layering.md) | Layered arcade audio: cinematic loop, impact SFX, and attenuation rules | Audio |
| [04](04-i-frames-game-feel.md) | I-frames as game feel: making invulnerability legible | Game state |
| [05](05-per-icicle-gravity.md) | Per-icicle gravity in SpriteKit without rewriting physics | Physics |
| [06](06-live-tuning-struct.md) | Live tuning: from `let` constants to a UserDefaults-backed struct | Workflow |
| [07](07-screen-lock-frame-time-bug.md) | The screen-lock bug: resetting the frame-time anchor on resume | Lifecycle |
| [08](08-debug-accessibility-test-hooks.md) | Testing a physics game deterministically with a debug accessibility hook | Testing |

## Recommended reading order

Start with the prequel for context on how the raw materials got made, then move into the runtime decisions:

1. **00** — Bootstrapping the asset pipeline *(how the sprites and audio got here)*
2. **01** — Bitmap heroes, procedural FX *(rendering split)*
3. **05** — Per-icicle gravity *(working around the engine)*
4. **04** — I-frames as game feel *(state contract)*
5. **02** — Haptic budget *(feedback layer 1)*
6. **03** — Arcade audio layering *(feedback layer 2)*
7. **06** — Live tuning *(workflow turn)*
8. **07** — Screen-lock bug *(a war story)*
9. **08** — Debug accessibility hook *(testing rigor)*

## About the project

PenguinSlide is on iOS 17+. SpriteKit drives the game loop; SwiftUI hosts the scene; CoreMotion supplies tilt input. The full repo is the parent of this folder. The setup steps and difficulty knobs live in [the project README](../../README.md).

## About the source material

These posts were mined from past agent-coding sessions via [`cass`](https://github.com/Dicklesworthstone/coding_agent_session_search) and grounded in the surviving Swift source. The git history was intentionally reset to a single `init` commit (`1c253ac`) during development, so old commit hashes referenced in sessions no longer resolve. Every code reference in these posts points to a file path and line number in the current tree.

See [`_template.md`](_template.md) for the shape each post follows.
