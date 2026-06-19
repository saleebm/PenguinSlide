//
//  EncounterAnimations.swift
//  PenguinSlide
//
//  Snow Monster encounter counterpart to PenguinAnimations: per-state
//  texture arrays sliced from the SpriteCook horizontal-strip
//  spritesheets in Assets.xcassets (SnowMonsterIdle/Throw/Roar,
//  PapiRearSlide). Frames are non-owning sub-textures via
//  SpriteCatalog.slicedFrames, sharing the underlying atlas pixels.
//
//  See `spritecook-assets.json` at the repo root for the source
//  asset IDs, prompts, and per-state frame counts.
//

import SpriteKit

enum EncounterAnimState {
    case monsterIdle
    case monsterThrow
    case monsterRoar
    case monsterMelt
    case papiSlide
}

enum EncounterAnimations {

    // Frame counts MUST match spritecook-assets.json (the integration
    // contract with the SpriteCook asset agent). Sheet width must be
    // divisible by the count or slices bleed at frame boundaries.
    //   snow_monster_idle      12 frames @ 88x88, 8fps, loops
    //   snow_monster_throw     10 frames @ 88x88, 8fps, one-shot
    //   snow_monster_roar       8 frames @ 88x88, 8fps, one-shot
    //   snow_monster_melt      16 frames @ 88x88, one-shot, NOT fixed-fps:
    //                           SnowMonster.melt stretches the clip across
    //                           Tuning.Encounter.meltDuration. Real
    //                           SpriteCook sheet (swapped in by
    //                           penguinslide-6m5); frames 14-16 are
    //                           near-identical settle/hold frames for
    //                           the slow-melt hold.
    //   papi_penguin_rear_slide 8 frames @ 90x90, 8fps, loops
    //                           (lean frames baked into the loop — no
    //                           separate dodge sheet; PapiAvatar mirrors
    //                           via xScale toward the dodge direction and
    //                           trims its zRotation lean target by
    //                           Tuning.Encounter.papiLeanScale so baked +
    //                           rotated lean don't over-rotate)
    //   (snowball_impact_burst was RETIRED by penguinslide-bo8: the sheet
    //   carried an opaque white background that rendered as a white box
    //   on device. Snowball impact FX is now procedural — see
    //   EncounterFX's puff + gravity snow chunks.)
    private static let monsterIdleFrameCount   = 12
    private static let monsterThrowFrameCount  = 10
    private static let monsterRoarFrameCount   = 8
    private static let monsterMeltFrameCount   = 16
    private static let papiSlideFrameCount     = 8

    static let monsterIdleFrames:   [SKTexture] = slice(.snowMonsterIdle,  count: monsterIdleFrameCount)
    static let monsterThrowFrames:  [SKTexture] = slice(.snowMonsterThrow, count: monsterThrowFrameCount)
    static let monsterRoarFrames:   [SKTexture] = slice(.snowMonsterRoar,  count: monsterRoarFrameCount)
    static let monsterMeltFrames:   [SKTexture] = slice(.snowMonsterMelt,  count: monsterMeltFrameCount)
    static let papiSlideFrames:     [SKTexture] = slice(.papiRearSlide,    count: papiSlideFrameCount)

    static func frames(for state: EncounterAnimState) -> [SKTexture] {
        switch state {
        case .monsterIdle:   return monsterIdleFrames
        case .monsterThrow:  return monsterThrowFrames
        case .monsterRoar:   return monsterRoarFrames
        case .monsterMelt:   return monsterMeltFrames
        case .papiSlide:     return papiSlideFrames
        }
    }

    static func loops(_ state: EncounterAnimState) -> Bool {
        switch state {
        case .monsterIdle, .papiSlide:
            return true
        case .monsterThrow, .monsterRoar, .monsterMelt:
            return false
        }
    }

    private static func slice(_ sprite: Sprite, count: Int) -> [SKTexture] {
        SpriteCatalog.slicedFrames(sprite, count: count)
    }
}
