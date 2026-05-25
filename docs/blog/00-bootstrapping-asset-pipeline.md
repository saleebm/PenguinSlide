# Bootstrapping PenguinSlide: SpriteKit, SpriteCook, and ElevenLabs

Before any of the runtime decisions in the rest of this series were possible, the game needed *stuff*. A penguin that had to look like a penguin. Icicles that read as menacing. A heartbeat of background music, a satisfying shatter on impact, a yelp when the penguin gets hit. None of that comes from code; code only knows what to *do* with it. So the very first move on PenguinSlide was figuring out who was going to make the raw materials.

The answer turned out to be a three-tool pipeline. SpriteKit for the runtime canvas, SpriteCook for the sprites and animations, ElevenLabs for the audio. I am not a pixel artist. I am not a composer. The pipeline is what bridges that gap.

## SpriteKit: the canvas

SpriteKit is Apple's built-in 2D game framework. iOS 17+ ships with it. Zero dependencies, no SwiftPM packages to wire, no `pod install`. You hand it textures and sound files; it gives you a scene graph, a physics world, and a 60-fps update loop. Free. Already on every iPhone.

The whole runtime side of PenguinSlide is SpriteKit on top of a thin SwiftUI host. `ContentView` holds the `GameScene` in `@State`, `GameScene` is an `SKScene` subclass, and everything that moves on screen is an `SKSpriteNode` or `SKShapeNode` parented to it. If you've used a game engine before, the model is familiar; if you haven't, SpriteKit's API is small enough to learn in an afternoon.

What SpriteKit does *not* give you: assets. Penguins, icicles, music, sound effects: all on you.

## SpriteCook: sprites and spritesheet animations

SpriteCook is a generation service that produces game-ready 2D art: single sprites, tilesets, characters, animation spritesheets. There's an MCP server for it, which means an agent can call `generate_character`, `generate_character_animations`, etc. directly from a coding session. You get back an `asset_id` and a presigned download URL.

For PenguinSlide, SpriteCook produced the penguin family, five imagesets that ship in `Assets.xcassets`:

| Imageset | Type | Frames |
|---|---|---|
| `Penguin` | base sprite | 1 |
| `PenguinIdle` | spritesheet, loops | 12 @ 8 fps |
| `PenguinSlide` | spritesheet, loops | 8 @ 8 fps |
| `PenguinHurt` | spritesheet, one-shot | 6 @ 8 fps |
| `PenguinVictory` | spritesheet, one-shot | 10 @ 8 fps |

The other three imagesets (`Icicle`, `IceTile`, `SkyBackdrop`) came from outside SpriteCook, kept in the same asset catalog for consistency.

Every SpriteCook-generated asset has a row in `spritecook-assets.json` at the repo root:

```json
"penguin_idle": {
  "asset_id": "3b8a4812-7473-473a-a955-43982ac378b4",
  "sha12": "c74fa2f26171",
  "label": "Idle loop — 12 frames, 90x90 each, 8fps. Subtle breathing bob + flipper sway + blink.",
  "frames": 12,
  "frame_size": "90x90",
  "fps": 8,
  "output_format": "spritesheet",
  "loops": true,
  "asset_path": "PenguinSlide/Assets.xcassets/PenguinIdle.imageset/penguin_idle.png"
}
```

This is the local manifest pattern the SpriteCook workflow recommends. `asset_id` is the stable identifier on the SpriteCook side; `sha12` is the local file's content hash. If I lose track of which file came from which generation, the manifest reconciles. If I want to iterate on the idle animation, I reuse `asset_id` instead of generating from scratch and getting a different penguin face.

The **8 fps** in the manifest is the same number that lives in `PenguinTuning.animationFps`. The asset and the runtime agreed on the playback rate before I wrote a single `SKAction.animate(with:timePerFrame:)`. That alignment wasn't accidental; telling SpriteCook the target frame rate up front is what made the animations feel right when SpriteKit played them back.

## ElevenLabs: music and sound effects

ElevenLabs is best known for voice synthesis, but their music and sound-effects APIs are what PenguinSlide used. Five `.caf` files now live in `PenguinSlide/Sounds/`:

- `bg_music.caf`: a looping ambient bed, generated via ElevenLabs Music. Calm, icy, plays under everything at 0.18 volume.
- `icicle_crack.caf`: the warning rattle when an icicle telegraphs before falling.
- `icicle_shatter.caf`: the percussive break when an icicle hits ice or penguin.
- `penguin_cry.caf`: a short "ouch" that fires only on damaging hits, not on i-frame saves.
- `game_over.caf`: the round-end sting.

Each came from an ElevenLabs SFX prompt: a short text description like "high-pitched ice crack, ceramic, 0.4 seconds" or "soft cinematic underscore, ambient pads, icy texture, loopable." The audio is `.caf` (Apple's preferred lossless format) so SpriteKit's `SKAudioNode` and `SKAction.playSoundFileNamed` can load them without re-encoding.

The interaction model is similar to SpriteCook: prompt → asset URL → save to `Sounds/`. There's no on-device generation; the audio is baked at design time and shipped with the app.

## The order of operations

Roughly what I did, in order, to go from empty Xcode project to running game:

1. **`File → New Project → App`** in Xcode, SwiftUI + Swift, iOS 17+ target. Standard template.
2. **Generated the penguin family in SpriteCook.** Five separate calls: one base, four animations. Saved asset IDs to `spritecook-assets.json` and the PNGs to the Xcode asset catalog.
3. **Generated audio with ElevenLabs.** Five SFX/music prompts. Saved `.caf` files to `PenguinSlide/Sounds/` and added the folder reference to the Xcode project.
4. **Authored the icicle, ice tile, and sky backdrop separately** and dropped them into `Assets.xcassets`.
5. **Wired everything in code.** `SpriteCatalog.swift` loads imagesets by name; `IcicleSystem` and `GameScene` reference audio files by filename. From this point on, the codebase is the focus of the other posts in this series.

Total elapsed time for steps 2-4: an afternoon. The bulk of the project's effort was code, not assets.

## What it costs

- **SpriteCook credits aren't free.** Each animation costs credits; iterations cost more credits. Check the balance before a batch via `get_credit_balance`.
- **ElevenLabs has its own quota** and audio-generation latency is higher than image. Plan prompts carefully; the cheapest workflow is "get it right the first time."
- **Asset manifests rot if you don't maintain them.** Every regenerated asset needs its `sha12` updated, or the manifest stops matching the file on disk. Skip manifests for throwaway work; keep them for anything you'll iterate on.
- **You're tied to your prompts as much as your code.** Losing the prompt that produced a clean icicle shatter is losing the asset. Save your prompts.
- **Generated audio is fixed-length.** No procedural variation. If the same icicle crack plays every spawn, players notice. Mitigation: short clips + restart-on-trigger patterns (covered in [post #3](03-arcade-audio-layering.md)).

## The general shape

If you're starting a small game and you're not an artist or a composer, the modern pipeline is shorter than you think:

1. **Pick a runtime that gives you the most for free.** SpriteKit on Apple platforms is hard to beat: zero install, zero dependencies, full scene graph, physics, audio.
2. **Use a generation tool for the sprites you'd commission an artist for** otherwise. SpriteCook handles characters and animations well. Save asset IDs in a manifest so you can iterate without losing track.
3. **Use a generation tool for audio you can describe in a sentence.** ElevenLabs SFX and Music cover most of what an arcade game needs. Save the `.caf` files; bake them in.
4. **Author what's specific to your game by other means.** The icicle silhouette and the sky backdrop in PenguinSlide were calibrated by hand because they carry the game's identity in a way a prompt couldn't capture.

The rest of [this series](README.md) is what happened after the assets existed: how the sprites got drawn, how the audio got mixed, how the haptics got budgeted, and the bugs we hit along the way.
