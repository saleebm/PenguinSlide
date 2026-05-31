import SpriteKit
/// Frames for the icicle shatter burst, sliced from the SpriteCook
/// spritesheet in Assets.xcassets/IcicleShatter.imageset. One-shot.
enum IcicleAnimations {
    static let shatterFrames: [SKTexture] = SpriteCatalog.slicedFrames(.icicleShatter, count: 8)
}
