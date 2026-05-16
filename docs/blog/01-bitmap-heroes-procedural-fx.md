# Bitmap heroes, procedural FX: a mixed asset strategy

When the penguin slides across the ice in PenguinSlide, every visible thing on screen falls into one of two buckets. The penguin, the icicle, the ice tile, the sky — all bitmap PNGs in `Assets.xcassets`, rendered through SpriteKit's texture loader. The snow puff when an icicle detaches, the icy-blue chips that pop on impact, the red heart in the corner — none of those have an image file. They're drawn at runtime out of `UIBezierPath`s and ellipses, cached once, then reused thousands of times.

Two pipelines, one game. We didn't set out to do this; it's what we ended up with after asking, for each thing on screen, what does it cost to ship a PNG?

## When the answer is "ship the PNG"

The penguin has character. There are five poses — idle, slide, hurt, victory, and the base sprite — and the difference between them is the shape of the eyes, the angle of the body, the position of the flippers. None of that is parametric. You can't generate "penguin looking scared" from a function. Pixel art is the medium *because* every pixel was a choice.

So the penguin gets bitmaps. The icicle is the same story — it's a hand-drawn ice shape with highlights that suggest depth. The sky backdrop has a gradient and a couple of clouds. The ice tile has a specific frost pattern that tiles cleanly. All of these have identity.

Eight imagesets total:

```
Assets.xcassets/
  Penguin.imageset/        # base penguin pose
  PenguinIdle.imageset/    # animation frame
  PenguinSlide.imageset/   # animation frame
  PenguinHurt.imageset/    # hit reaction
  PenguinVictory.imageset/ # round-end pose
  Icicle.imageset/         # the threat
  IceTile.imageset/        # tiled floor surface
  SkyBackdrop.imageset/    # background
```

The loader is a thirty-line file. It memoizes `SKTexture(imageNamed:)` and pins filtering mode to `.nearest` so pixel art doesn't blur at non-integer scales:

```swift
// PenguinSlide/SpriteCatalog.swift:27
static func texture(for sprite: Sprite) -> SKTexture {
    if let cached = cache[sprite] { return cached }
    let texture = SKTexture(imageNamed: sprite.rawValue)
    // Nearest-neighbor keeps pixel art crisp at non-integer scales.
    texture.filteringMode = .nearest
    cache[sprite] = texture
    return texture
}
```

There's also a `tiled(_:size:)` helper that takes a small bitmap and tiles it across a larger surface. The ice floor uses it. The bitmap is the source of truth; the runtime work is just stamping.

## When the answer is "don't ship the PNG"

Now look at a snow puff. It's a white circle, three pixels in radius. There's nothing to draw — the *concept* is "white circle," and the function `UIGraphicsImageRenderer` plus `fillEllipse(in:)` produces it in three lines:

```swift
// PenguinSlide/IcicleSystem.swift:67
private lazy var puffTexture: SKTexture = {
    let r: CGFloat = 3
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: r * 2, height: r * 2))
    let img = renderer.image { ctx in
        ctx.cgContext.setFillColor(UIColor.white.cgColor)
        ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: r * 2, height: r * 2))
    }
    let tex = SKTexture(image: img)
    tex.filteringMode = .linear
    return tex
}()
```

A shatter shard is the same idea, one rung up: an 8x8 icy-blue triangle, drawn with three `addLine(to:)` calls. The heart icon in the HUD is the most fun one — two arcs and a V, rendered into a 24x22 bitmap exactly once, then reused for the three hearts that count the penguin's HP. Look at `HUDController.swift:96`:

```swift
// PenguinSlide/HUDController.swift:96
private static func buildHeartTexture() -> SKTexture {
    let size = CGSize(width: 24, height: 22)
    let renderer = UIGraphicsImageRenderer(size: size)
    let img = renderer.image { _ in
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 12, y: 22))
        p.addCurve(to: CGPoint(x: 0, y: 8),
                   controlPoint1: CGPoint(x: 12, y: 18),
                   controlPoint2: CGPoint(x: 0, y: 14))
        p.addArc(withCenter: CGPoint(x: 6, y: 6),  radius: 6,
                 startAngle: .pi, endAngle: 0, clockwise: true)
        // ... mirror arc + close path
        UIColor(red: 0.95, green: 0.25, blue: 0.35, alpha: 1).setFill()
        p.fill()
    }
    let tex = SKTexture(image: img)
    tex.filteringMode = .linear
    return tex
}
```

The shipped binary doesn't include `heart.png` because the heart isn't an image, it's a recipe.

## What the split costs

Every choice has a price. Worth being honest about them.

- **Procedural shapes lose pixel-art identity.** A `UIBezierPath` heart is smooth and curvy. It will never look hand-pixeled. Fine for HUD glyphs; wrong for hero sprites.
- **Procedural shapes are harder to iterate on.** Adjusting the shape means editing code and recompiling. You can't drop a new PNG into Xcode and reload.
- **They're invisible in the Asset Catalog.** No preview. No size warning. The only way to see a `shardTexture` is to run the game.
- **Bitmap sprites grow linearly with variants.** Five penguin poses means five imagesets. If we add a "stunned" frame, that's a sixth.
- **Bitmap scaling is filtering-mode-fragile.** We pin `.nearest` in `SpriteCatalog`; one stray `.linear` somewhere and the pixel art turns to mush.
- **Cold-start cost is on the bitmap side.** Loading eight imagesets at scene boot takes a few milliseconds. Procedural textures are built lazily on first use.

## The generalization

Don't pick one pipeline and apply it religiously. Ask the question per-object:

> Does this thing have identity, or is it a parametric shape?

If it has identity — pixel-perfect eyes, a particular silhouette, animation frames — ship the bitmap. If it's a circle, a triangle, two arcs, or a procedural pattern parameterized by size and color, draw it at runtime. You'll end up with a few imagesets for the things that matter and a handful of `lazy var someTexture: SKTexture = { ... }()` blocks for everything else.

The mistake is treating the choice as ideological. "Asset-free games" is a vanity metric. "PNG everything" is asset bloat. The interesting line is the one between the two, and it runs through the question above.
