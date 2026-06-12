//
//  SpriteCatalog.swift
//  PenguinSlide
//
//  Single entry point for loading game art from Assets.xcassets.
//  Adding a new sprite = one enum case + one .imageset folder.
//

import SpriteKit
import UIKit

enum Sprite: String, CaseIterable {
    case penguin        = "Penguin"
    case penguinIdle    = "PenguinIdle"
    case penguinSlide   = "PenguinSlide"
    case penguinHurt    = "PenguinHurt"
    case penguinVictory = "PenguinVictory"
    case icicle         = "Icicle"
    case icicleShatter  = "IcicleShatter"
    case iceTile        = "IceTile"
    case skyBackdrop    = "SkyBackdrop"

    // Snow Monster encounter (sheets sliced by EncounterAnimations;
    // source metadata in spritecook-assets.json).
    case papiRearSlide     = "PapiRearSlide"
    case snowMonsterIdle   = "SnowMonsterIdle"
    case snowMonsterThrow  = "SnowMonsterThrow"
    case snowMonsterRoar   = "SnowMonsterRoar"
    case snowMonsterMelt   = "SnowMonsterMelt"
    case snowball          = "Snowball"
    case snowballBurst     = "SnowballBurst"
    case mountainBackdrop  = "MountainBackdrop"
    case perspectiveGround = "PerspectiveGround"
}

enum SpriteCatalog {

    private static var cache: [Sprite: SKTexture] = [:]

    static func texture(for sprite: Sprite) -> SKTexture {
        if let cached = cache[sprite] { return cached }
        let texture = SKTexture(imageNamed: sprite.rawValue)
        // Nearest-neighbor keeps pixel art crisp at non-integer scales.
        texture.filteringMode = .nearest
        cache[sprite] = texture
        return texture
    }

    /// Builds a one-off texture of `size` by repeating the sprite's image.
    /// Use this for surfaces that should tile rather than stretch.
    static func tiled(_ sprite: Sprite, size: CGSize) -> SKTexture {
        let base = UIImage(cgImage: texture(for: sprite).cgImage())
        let tileSize = base.size
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    base.draw(in: CGRect(origin: CGPoint(x: x, y: y), size: tileSize))
                    x += tileSize.width
                }
                y += tileSize.height
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return texture
    }

    /// Slice a horizontal N-frame spritesheet into per-frame textures
    /// (non-owning sub-textures sharing the atlas; nearest-neighbor).
    static func slicedFrames(_ sprite: Sprite, count: Int) -> [SKTexture] {
        let sheet = texture(for: sprite)
        let w = CGFloat(1) / CGFloat(count)
        return (0..<count).map { i in
            let t = SKTexture(rect: CGRect(x: CGFloat(i) * w, y: 0, width: w, height: 1), in: sheet)
            t.filteringMode = .nearest
            return t
        }
    }

    static func preload() {
        Sprite.allCases.forEach { _ = texture(for: $0) }
    }
}
