//
//  PenguinAnimations.swift
//  PenguinSlide
//
//  Per-state texture arrays sliced from the SpriteCook-generated
//  spritesheets in Assets.xcassets (PenguinIdle/Slide/Hurt/Victory).
//  Each sheet is a horizontal strip of equal-width 90×90 frames;
//  `slice` produces non-owning sub-textures via SKTexture(rect:in:)
//  so the underlying atlas pixels are shared across the array.
//
//  See `spritecook-assets.json` at the repo root for the source
//  asset IDs, prompts, and per-state frame counts.
//

import SpriteKit

enum PenguinAnimState {
    case idle
    case slide
    case hurt
    case victory
}

enum PenguinAnimations {

    static let idleFrames:    [SKTexture] = slice(.penguinIdle,    count: 12)
    static let slideFrames:   [SKTexture] = slice(.penguinSlide,   count: 8)
    static let hurtFrames:    [SKTexture] = slice(.penguinHurt,    count: 6)
    static let victoryFrames: [SKTexture] = slice(.penguinVictory, count: 10)

    static func frames(for state: PenguinAnimState) -> [SKTexture] {
        switch state {
        case .idle:    return idleFrames
        case .slide:   return slideFrames
        case .hurt:    return hurtFrames
        case .victory: return victoryFrames
        }
    }

    static func loops(_ state: PenguinAnimState) -> Bool {
        switch state {
        case .idle, .slide:   return true
        case .hurt, .victory: return false
        }
    }

    // SKTexture rect coordinates are normalized to the source atlas,
    // origin bottom-left. Each frame occupies (1/N) of the width and the
    // full height — these are horizontal strips, not grids. Delegates to
    // the shared `SpriteCatalog.slicedFrames` slicer.
    private static func slice(_ sprite: Sprite, count: Int) -> [SKTexture] {
        SpriteCatalog.slicedFrames(sprite, count: count)
    }
}
