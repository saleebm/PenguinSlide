//
//  EncounterWorld.swift
//  PenguinSlide
//
//  Perspective scenery for the Snow Monster encounter (penguinslide-gyu.10):
//  mountain backdrop on the horizon, pseudo-3D ground depth-bands, converging
//  lane-edge markings, and snow speed-lines — together they sell "Papi is
//  sliding FORWARD into the scene" even though SpriteKit has no depth camera.
//
//  ## How the forward-slide illusion works
//
//  Horizontal snow strips ("depth bands") live at virtual z stations between
//  the camera plane (z = 0) and beyond the monster (z = zMonster × span
//  factor). Every frame each band's z decreases by `groundScrollSpeed × dt`
//  and is re-projected through `DepthProjector`, so a band drifts down-screen,
//  widens, and thickens exactly as a real ground stripe would when driven
//  toward — the classic pseudo-3D road technique. When a band crosses z = 0
//  it wraps back to the far end of the span (recycled, never reallocated).
//  Alpha fades symmetric at BOTH ends of the span — out approaching the
//  camera plane, in near the horizon — so the single-frame z-wrap is
//  invisible at either end (penguinslide-hhz: the original near-side pop
//  read as "ice doesn't feel smooth" on device). Snow speed-line
//  particles run the same integration faster than the ground for a relative-
//  wind cue, and two static lane-edge lines converge to the vanishing point
//  to anchor the geometry. All motion is manual integration in `update(dt:)`
//  — ZERO SKActions — so phase freezes (`physicsWorld.speed = 0`, paused
//  containers) and the dt == 0 sentinel behave exactly like the rest of the
//  codebase with no pause-hook registration needed.
//
//  ## GameScene seam (wiring is intentionally tiny — see thread gyu.30)
//
//      let world = EncounterWorld(parent: encounterRoot, sceneSize: size)
//      world.startScroll()        // intro begins the forward-slide
//      world.update(dt: dt)       // each frame while intro/encounter/outro
//      world.stopScroll()         // outro
//      world.reset()              // restart()/post-outro: re-seat bands
//
//  Constructing while `encounterRoot` is hidden + paused is safe (no flash,
//  no actions). Steady state allocates zero nodes per frame; everything is
//  pooled at init.
//
//  ## zPosition ranges inside encounterRoot (RESERVED — actor beads slot in
//  without collisions; keep this block authoritative)
//
//      -100        sky fill                        (EncounterWorld)
//       -90        mountain backdrop               (EncounterWorld)
//       -80        base ground fill                (EncounterWorld)
//       -70..-60   ground depth-bands, depth-sorted (EncounterWorld)
//       -50        lane-edge markings              (EncounterWorld)
//       -40        snow speed-lines                (EncounterWorld)
//         0..9     SnowMonster                     (gyu.12)
//        10..29    far snowballs (z > depthWindow) (gyu.13)
//        30..49    near snowballs                  (gyu.13)
//        50..59    Papi avatar                     (gyu.11)
//        60+       encounter HUD accents / foreground FX
//

import SpriteKit

// MARK: - Pure band-field math (unit-tested in EncounterWorldTests)

/// The recyclable set of depth stations behind the band sprites. Pure value
/// type: advancing moves every station toward the camera and wraps anything
/// that crosses z = 0 back to the far end of the span, preserving relative
/// spacing — the invariant the whole illusion rests on.
struct DepthBandField: Equatable {
    let zSpan: CGFloat
    private(set) var stations: [CGFloat]

    /// Stations are seeded evenly over (0, zSpan]: i-th at zSpan·(i+1)/count.
    init(count: Int, zSpan: CGFloat) {
        self.zSpan = zSpan
        self.stations = (0..<max(count, 1)).map {
            zSpan * CGFloat($0 + 1) / CGFloat(max(count, 1))
        }
    }

    /// Move every station `dz` toward the camera (positive dz = forward
    /// slide), wrapping past z = 0 back to the far end. `truncatingRemainder`
    /// keeps a huge dt hiccup from looping.
    mutating func advance(by dz: CGFloat) {
        guard zSpan > 0 else { return }
        for i in stations.indices {
            var z = (stations[i] - dz).truncatingRemainder(dividingBy: zSpan)
            if z <= 0 { z += zSpan }
            stations[i] = z
        }
    }
}

/// Wrap-fade alpha for a recycled element so the z-wrap never pops at
/// EITHER end of the span: 0 at z = zSpan ramping in over the far fade
/// region, 1 through the mid-field, and ramping back out to 0 at z = 0
/// (penguinslide-hhz: the near side previously held alpha 1 right up to the
/// wrap, a visible one-frame blink at full scale). Both ends sit at ~0 when
/// a wrap teleports z, so per-frame alpha is jump-free across the wrap —
/// EncounterWorldTests asserts the bound. Pure for testability; fraction
/// parameters default to the live tuning knobs.
func encounterBandAlpha(
    z: CGFloat,
    zSpan: CGFloat,
    farFadeFraction: CGFloat = Tuning.Encounter.groundBandFarFadeFraction,
    nearFadeFraction: CGFloat = Tuning.Encounter.groundBandNearFadeFraction
) -> CGFloat {
    guard zSpan > 0 else { return 1 }
    let fadeIn = farFadeFraction > 0
        ? (zSpan - z) / (zSpan * farFadeFraction)
        : 1
    let fadeOut = nearFadeFraction > 0
        ? z / (zSpan * nearFadeFraction)
        : 1
    return min(max(min(fadeIn, fadeOut), 0), 1)
}

// MARK: - World builder + per-frame animator

final class EncounterWorld {

    private let projector: DepthProjector
    private let sceneSize: CGSize

    /// Half the corridor width gets a margin so the ground visibly outruns
    /// Papi's dodge range and the lane lines read as edges, not walls.
    private let groundBaseWidth: CGFloat

    // Pooled nodes (allocated once at init, recycled forever).
    private(set) var bandNodes: [SKSpriteNode] = []
    private(set) var bandField: DepthBandField
    /// Mountain vista sprite — exposed for the gyu.25 alignment asserts.
    private(set) var backdropNode: SKSpriteNode?

    private struct SpeedLine {
        let node: SKSpriteNode
        var worldX: CGFloat
        var z: CGFloat
        var speedFactor: CGFloat
    }
    private var speedLines: [SpeedLine] = []

    private(set) var isScrolling = false

    init(parent: SKNode, sceneSize: CGSize) {
        self.sceneSize = sceneSize
        self.projector = DepthProjector(sceneSize: sceneSize)
        self.groundBaseWidth = sceneSize.width * 1.25
        self.bandField = DepthBandField(
            count: Tuning.Encounter.groundBandCount,
            zSpan: Tuning.Encounter.zMonster * Tuning.Encounter.groundSpanFactor
        )

        buildSky(parent: parent)
        buildBackdrop(parent: parent)
        buildGroundFill(parent: parent)
        buildBands(parent: parent)
        buildLaneMarkings(parent: parent)
        buildSpeedLines(parent: parent)

        layout()
    }

    // MARK: Seam

    /// Begin the forward-slide scroll (intro choreography calls this).
    func startScroll() { isScrolling = true }

    /// Halt the scroll (outro). Bands keep their current stations so the
    /// outro crossfade leaves a coherent still frame.
    func stopScroll() { isScrolling = false }

    /// Manual integration tick. Call every frame the encounter phases run;
    /// dt == 0 (sentinel frame) is a free no-op layout refresh.
    func update(dt: CGFloat) {
        guard isScrolling, dt > 0 else { return }
        bandField.advance(by: Tuning.Encounter.groundScrollSpeed * dt)
        advanceSpeedLines(dt: dt)
        layout()
    }

    /// Re-seat bands at their initial stations and re-roll speed lines —
    /// the next encounter starts from a clean field. Also stops the scroll.
    func reset() {
        isScrolling = false
        bandField = DepthBandField(
            count: Tuning.Encounter.groundBandCount,
            zSpan: bandField.zSpan
        )
        for i in speedLines.indices {
            speedLines[i].z = CGFloat.random(in: 1...bandField.zSpan)
            speedLines[i].worldX = randomSpeedLineWorldX()
        }
        layout()
    }

    // MARK: Construction (buildSky/buildIceField style)

    private func buildSky(parent: SKNode) {
        let skyHeight = sceneSize.height - projector.horizonY
        // Tinted to the SpriteCook backdrop's top-edge sky (RGB ≈ 138/230/249)
        // so the seam where the vista art ends and this fill continues
        // upward is invisible (gyu.25).
        let sky = SKSpriteNode(color: UIColor(red: 0.54, green: 0.90, blue: 0.98, alpha: 1),
                               size: CGSize(width: sceneSize.width, height: skyHeight))
        sky.anchorPoint = .zero
        sky.position = CGPoint(x: 0, y: projector.horizonY)
        sky.zPosition = -100
        parent.addChild(sky)
    }

    private func buildBackdrop(parent: SKNode) {
        let texture = SpriteCatalog.texture(for: .mountainBackdrop)
        let backdrop = SKSpriteNode(texture: texture)
        // The delivered art is a full vista (sky, mountain ranges, painted
        // valley floor), so its INTERNAL horizon row — pinned via the
        // anchor (`backdropHorizonInArtFraction`) — sits exactly on the
        // projector's horizon line. The painted floor below the anchor
        // falls under horizonY where the ground fill (-80) and depth-bands
        // (-70..-60) draw over it; only mountains + art sky rise above.
        // Uniform width-fit scale so the vista always reaches both edges.
        backdrop.anchorPoint = CGPoint(x: 0.5,
                                       y: Tuning.Encounter.backdropHorizonInArtFraction)
        backdrop.position = CGPoint(x: projector.vanishingX, y: projector.horizonY)
        backdrop.setScale(sceneSize.width / max(texture.size().width, 1))
        backdrop.zPosition = -90
        parent.addChild(backdrop)
        backdropNode = backdrop
    }

    private func buildGroundFill(parent: SKNode) {
        // Flat snow base under the bands: covers the foreground strip below
        // Papi's plane and any inter-band gaps near the horizon.
        let fill = SKSpriteNode(color: UIColor(red: 0.87, green: 0.92, blue: 0.97, alpha: 1),
                                size: CGSize(width: sceneSize.width, height: projector.horizonY))
        fill.anchorPoint = .zero
        fill.position = .zero
        fill.zPosition = -80
        parent.addChild(fill)
    }

    private func buildBands(parent: SKNode) {
        let sheet = SpriteCatalog.texture(for: .perspectiveGround)
        let count = Tuning.Encounter.groundBandCount
        let baseSize = CGSize(width: groundBaseWidth,
                              height: Tuning.Encounter.groundBandThickness)
        // Inset each slice rect by half a texel vertically (penguinslide-hhz):
        // sampling exactly on a slice boundary bleeds the neighboring row's
        // texels into a band's top/bottom edge, a hard seam line that gets
        // magnified to several points when a band stretches near the camera.
        let sheetHeight = max(sheet.size().height, 1)
        let texelInsetY = 0.5 / sheetHeight
        let sliceHeight = 1 / CGFloat(count)
        for i in 0..<count {
            // Each band carries a distinct horizontal slice of the ground
            // texture (non-owning sub-texture) so the recycled strips don't
            // read as one repeating stripe.
            let slice = SKTexture(rect: CGRect(x: 0,
                                               y: CGFloat(i) * sliceHeight + texelInsetY,
                                               width: 1,
                                               height: max(sliceHeight - 2 * texelInsetY,
                                                           texelInsetY)),
                                  in: sheet)
            slice.filteringMode = .nearest   // crisp pixel art at any scale
            let band = SKSpriteNode(texture: slice, size: baseSize)
            band.anchorPoint = CGPoint(x: 0.5, y: 0)
            parent.addChild(band)
            bandNodes.append(band)
        }
    }

    private func buildLaneMarkings(parent: SKNode) {
        // Straight depth lines project to straight screen lines under this
        // projection (x and y are both linear in t), so two static segments
        // from the corridor edges at z = 0 toward a deep z suffice.
        let path = CGMutablePath()
        // Push the lane lines well past the monster so they read as converging
        // on the vanishing point — at this depth the projector has shrunk them
        // to within a couple px of vanishingX, which looks like the VP.
        let vanishingPointDepthFactor: CGFloat = 6
        let zDeep = Tuning.Encounter.zMonster * vanishingPointDepthFactor
        for worldX in [projector.vanishingX - Tuning.Encounter.papiLateralRange,
                       projector.vanishingX + Tuning.Encounter.papiLateralRange] {
            let near = projector.project(worldX: worldX, z: 0).point
            let far = projector.project(worldX: worldX, z: zDeep).point
            path.move(to: near)
            path.addLine(to: far)
        }
        let markings = SKShapeNode(path: path)
        markings.strokeColor = UIColor(white: 1.0, alpha: 0.55)
        markings.lineWidth = 2
        markings.zPosition = -50
        parent.addChild(markings)
    }

    /// Cached streak texture for the snow speed-lines — same pattern as
    /// IcicleSystem.puffTexture: one texture, many cheap SKSpriteNodes,
    /// never a per-frame SKShapeNode.
    private static let speedLineTexture: SKTexture = {
        let size = CGSize(width: 3, height: 12)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: size))
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        return tex
    }()

    private func buildSpeedLines(parent: SKNode) {
        for _ in 0..<Tuning.Encounter.speedLineCount {
            let node = SKSpriteNode(texture: Self.speedLineTexture)
            node.zPosition = -40
            parent.addChild(node)
            speedLines.append(SpeedLine(
                node: node,
                worldX: randomSpeedLineWorldX(),
                z: CGFloat.random(in: 1...bandField.zSpan),
                speedFactor: CGFloat.random(in: 0.85...1.15)
            ))
        }
    }

    private func randomSpeedLineWorldX() -> CGFloat {
        let spread = Tuning.Encounter.papiLateralRange * 1.4
        return projector.vanishingX + CGFloat.random(in: -spread...spread)
    }

    // MARK: Per-frame layout (all placement through the projector)

    private func advanceSpeedLines(dt: CGFloat) {
        let base = Tuning.Encounter.groundScrollSpeed
            * Tuning.Encounter.speedLineSpeedFactor
        for i in speedLines.indices {
            var z = speedLines[i].z - base * speedLines[i].speedFactor * dt
            if z <= 0 {
                z += bandField.zSpan
                speedLines[i].worldX = randomSpeedLineWorldX()
            }
            speedLines[i].z = z
        }
    }

    private func layout() {
        for (node, z) in zip(bandNodes, bandField.stations) {
            let projected = projector.project(worldX: projector.vanishingX, z: z)
            node.position = projected.point
            node.setScale(projected.scale)
            node.alpha = encounterBandAlpha(z: z, zSpan: bandField.zSpan)
            // Depth-sort within the reserved -70..-60 range: nearer bands
            // (larger t) draw over farther ones where thicknesses overlap.
            node.zPosition = -70 + 10 * projected.scale
        }
        for line in speedLines {
            let projected = projector.project(worldX: line.worldX, z: line.z)
            line.node.position = projected.point
            line.node.setScale(projected.scale)
            line.node.alpha = 0.7 * encounterBandAlpha(z: line.z, zSpan: bandField.zSpan)
        }
    }
}
