//
//  EncounterWorldTests.swift
//  PenguinSlideTests
//
//  penguinslide-gyu.10: pure band-field math (seeding, advance/wrap,
//  fade alpha) plus node-level spot asserts that EncounterWorld places
//  every band exactly where DepthProjector says it belongs, scrolls only
//  when started, recycles instead of allocating, and reseats on reset.
//

import SpriteKit
import XCTest
@testable import PenguinSlide

final class EncounterWorldTests: XCTestCase {

    // MARK: DepthBandField (pure)

    func testFieldSeedsEvenlySpacedStationsWithinSpan() {
        let field = DepthBandField(count: 8, zSpan: 1350)
        XCTAssertEqual(field.stations.count, 8)
        let step: CGFloat = 1350 / 8
        for (i, z) in field.stations.enumerated() {
            XCTAssertEqual(z, step * CGFloat(i + 1), accuracy: 0.001)
            XCTAssertGreaterThan(z, 0)
            XCTAssertLessThanOrEqual(z, 1350)
        }
    }

    func testAdvanceMovesStationsTowardCamera() {
        var field = DepthBandField(count: 4, zSpan: 1000)
        let before = field.stations
        field.advance(by: 100)
        for (b, a) in zip(before, field.stations) where b > 100 {
            XCTAssertEqual(a, b - 100, accuracy: 0.001)
        }
    }

    func testAdvanceWrapsPastCameraToFarEnd() {
        var field = DepthBandField(count: 4, zSpan: 1000)
        // Nearest station starts at 250; advancing 300 must wrap it to 950.
        field.advance(by: 300)
        XCTAssertEqual(field.stations[0], 950, accuracy: 0.001)
        // All stations stay inside (0, zSpan].
        for z in field.stations {
            XCTAssertGreaterThan(z, 0)
            XCTAssertLessThanOrEqual(z, 1000)
        }
    }

    func testAdvanceByFullSpanIsIdentity() {
        var field = DepthBandField(count: 5, zSpan: 800)
        let before = field.stations
        field.advance(by: 800)
        for (b, a) in zip(before, field.stations) {
            XCTAssertEqual(a, b, accuracy: 0.001)
        }
    }

    func testAdvanceSurvivesHugeDtWithoutLoopingOut() {
        var field = DepthBandField(count: 3, zSpan: 500)
        field.advance(by: 500 * 7 + 123)   // multi-span hiccup
        for z in field.stations {
            XCTAssertGreaterThan(z, 0)
            XCTAssertLessThanOrEqual(z, 500)
        }
    }

    func testBandAlphaFadesInFromFarEnd() {
        let span: CGFloat = 1000
        XCTAssertEqual(encounterBandAlpha(z: span, zSpan: span), 0)          // spawn point
        XCTAssertEqual(encounterBandAlpha(z: span * 0.5, zSpan: span), 1)   // mid-field
        // Monotone over the far fade region.
        let nearFade = encounterBandAlpha(z: span * 0.95, zSpan: span)
        let nearerFade = encounterBandAlpha(z: span * 0.90, zSpan: span)
        XCTAssertGreaterThan(nearerFade, nearFade)
        XCTAssertGreaterThan(nearFade, 0)
    }

    /// penguinslide-hhz: bands must fade OUT approaching the camera plane —
    /// the wrap at z = 0 previously happened at full alpha + full scale, a
    /// one-frame blink right where the eye rests.
    func testBandAlphaFadesOutApproachingCameraPlane() {
        let span: CGFloat = 1000
        let nearDepth = span * Tuning.Encounter.groundBandNearFadeFraction
        XCTAssertEqual(encounterBandAlpha(z: 0, zSpan: span), 0)             // wrap point
        XCTAssertEqual(encounterBandAlpha(z: nearDepth, zSpan: span), 1, accuracy: 0.001)
        // Monotone increasing over the near fade region (out as z → 0).
        let closer = encounterBandAlpha(z: nearDepth * 0.25, zSpan: span)
        let farther = encounterBandAlpha(z: nearDepth * 0.75, zSpan: span)
        XCTAssertGreaterThan(farther, closer)
        XCTAssertGreaterThan(closer, 0)
        // Fully opaque through the whole mid-field between the two fades.
        let farDepth = span * Tuning.Encounter.groundBandFarFadeFraction
        for frac in stride(from: 0.0, through: 1.0, by: 0.05) {
            let z = nearDepth + (span - farDepth - nearDepth) * CGFloat(frac)
            XCTAssertEqual(encounterBandAlpha(z: z, zSpan: span), 1, accuracy: 0.001)
        }
    }

    /// penguinslide-hhz acceptance: no single-frame alpha jump, including
    /// across the z-wrap. Simulate a station at the live (paceScale-scaled)
    /// scroll speed through several full wraps and bound the per-frame
    /// alpha delta by the analytic worst case dz × (1/nearDepth + 1/farDepth).
    func testBandAlphaHasNoSingleFrameJumpAcrossWrap() {
        let span = Tuning.Encounter.zMonster * Tuning.Encounter.groundSpanFactor
        let dz = Tuning.Encounter.groundScrollSpeed / 60   // one 60 fps frame
        let nearDepth = span * Tuning.Encounter.groundBandNearFadeFraction
        let farDepth = span * Tuning.Encounter.groundBandFarFadeFraction
        let bound = dz * (1 / nearDepth + 1 / farDepth) + 0.0001
        var field = DepthBandField(count: 1, zSpan: span)
        var previous = encounterBandAlpha(z: field.stations[0], zSpan: span)
        let framesForThreeWraps = Int((span * 3 / dz).rounded(.up)) + 1
        for _ in 0..<framesForThreeWraps {
            field.advance(by: dz)
            let alpha = encounterBandAlpha(z: field.stations[0], zSpan: span)
            XCTAssertLessThanOrEqual(abs(alpha - previous), bound,
                                     "alpha jumped \(abs(alpha - previous)) in one frame at z=\(field.stations[0])")
            previous = alpha
        }
    }

    /// penguinslide-hhz acceptance: between frames every non-wrapping
    /// station's projected screen-Y moves strictly DOWN-screen (toward the
    /// Papi plane) — any reversal or stall would read as ground stutter.
    func testProjectedYMovesMonotonicallyDownscreenAtAllStations() {
        let size = CGSize(width: 393, height: 852)
        let projector = DepthProjector(sceneSize: size)
        let span = Tuning.Encounter.zMonster * Tuning.Encounter.groundSpanFactor
        let dz = Tuning.Encounter.groundScrollSpeed / 60
        // Sweep stations across the whole span at fine granularity.
        for i in 1...200 {
            let z = span * CGFloat(i) / 200
            guard z - dz > 0 else { continue }   // wrap frames teleport by design
            let before = projector.project(worldX: projector.vanishingX, z: z).point.y
            let after = projector.project(worldX: projector.vanishingX, z: z - dz).point.y
            XCTAssertLessThan(after, before,
                              "projected y must strictly decrease as z advances; stalled at z=\(z)")
        }
    }

    // MARK: EncounterWorld node-level spot asserts

    private func makeWorld() -> (parent: SKNode, world: EncounterWorld, size: CGSize) {
        let size = CGSize(width: 393, height: 852)
        let parent = SKNode()
        return (parent, EncounterWorld(parent: parent, sceneSize: size), size)
    }

    /// Acceptance: band y/scale at each station match DepthProjector output.
    func testBandLayoutMatchesProjectorAtEveryStation() {
        let (_, world, size) = makeWorld()
        let projector = DepthProjector(sceneSize: size)
        for (node, z) in zip(world.bandNodes, world.bandField.stations) {
            let expected = projector.project(worldX: projector.vanishingX, z: z)
            XCTAssertEqual(node.position.y, expected.point.y, accuracy: 0.001)
            XCTAssertEqual(node.position.x, expected.point.x, accuracy: 0.001)
            XCTAssertEqual(node.xScale, expected.scale, accuracy: 0.001)
            XCTAssertEqual(node.yScale, expected.scale, accuracy: 0.001)
        }
    }

    func testUpdateDoesNotScrollUntilStarted() {
        let (_, world, _) = makeWorld()
        let before = world.bandField.stations
        world.update(dt: 1.0 / 60.0)
        XCTAssertEqual(world.bandField.stations, before)

        world.startScroll()
        world.update(dt: 1.0 / 60.0)
        XCTAssertNotEqual(world.bandField.stations, before)
    }

    func testSentinelFrameIsANoOp() {
        let (_, world, _) = makeWorld()
        world.startScroll()
        let before = world.bandField.stations
        world.update(dt: 0)   // dt == 0 sentinel frame
        XCTAssertEqual(world.bandField.stations, before)
    }

    /// Acceptance: zero per-frame node allocation in steady state — the
    /// child count is identical after many scrolled frames (bands and
    /// speed-lines recycle, nothing spawns).
    func testSteadyStateAllocatesNoNodes() {
        let (parent, world, _) = makeWorld()
        world.startScroll()
        let childCount = parent.children.count
        for _ in 0..<600 {   // ~10 s of frames, several full wraps
            world.update(dt: 1.0 / 60.0)
        }
        XCTAssertEqual(parent.children.count, childCount)
    }

    func testResetReseatsBandsAndStopsScroll() {
        let (_, world, size) = makeWorld()
        world.startScroll()
        for _ in 0..<120 { world.update(dt: 1.0 / 60.0) }
        world.reset()

        XCTAssertFalse(world.isScrolling)
        let fresh = DepthBandField(count: Tuning.Encounter.groundBandCount,
                                   zSpan: world.bandField.zSpan)
        XCTAssertEqual(world.bandField, fresh)

        // Layout refreshed to the reseated stations.
        let projector = DepthProjector(sceneSize: size)
        for (node, z) in zip(world.bandNodes, world.bandField.stations) {
            let expected = projector.project(worldX: projector.vanishingX, z: z)
            XCTAssertEqual(node.position.y, expected.point.y, accuracy: 0.001)
        }
    }

    // MARK: Mountain backdrop alignment (gyu.25 swap-in)

    /// Acceptance (gyu.25): the SpriteCook vista's internal horizon row —
    /// pinned via the anchor knob — sits exactly on the projector's horizon
    /// line at the vanishing point. Art placement bends to the projector.
    func testBackdropPinsArtHorizonOntoProjectorHorizon() {
        let (_, world, size) = makeWorld()
        let projector = DepthProjector(sceneSize: size)
        guard let backdrop = world.backdropNode else {
            return XCTFail("EncounterWorld built no backdrop node")
        }
        XCTAssertEqual(backdrop.anchorPoint.y,
                       Tuning.Encounter.backdropHorizonInArtFraction,
                       accuracy: 0.001)
        XCTAssertEqual(backdrop.position.y, projector.horizonY, accuracy: 0.001)
        XCTAssertEqual(backdrop.position.x, projector.vanishingX, accuracy: 0.001)
    }

    /// The width-fit uniform scale must reach both screen edges with no
    /// horizontal squash (pixel art shimmers under non-uniform scaling).
    func testBackdropSpansFullSceneWidthUniformly() {
        let (_, world, size) = makeWorld()
        guard let backdrop = world.backdropNode else {
            return XCTFail("EncounterWorld built no backdrop node")
        }
        XCTAssertEqual(backdrop.size.width, size.width, accuracy: 0.5)
        XCTAssertEqual(backdrop.xScale, backdrop.yScale, accuracy: 0.0001)
    }

    /// penguinslide-hhz: one pooled node per tuned band — the count knob is
    /// the band-density fix, so the pool must actually honor it.
    func testWorldBuildsOneNodePerTunedBand() {
        let (_, world, _) = makeWorld()
        XCTAssertEqual(world.bandNodes.count, Tuning.Encounter.groundBandCount)
        XCTAssertEqual(world.bandField.stations.count, Tuning.Encounter.groundBandCount)
    }

    /// penguinslide-hhz: each band's sub-texture rect must be inset half a
    /// texel from its slice boundaries — sampling exactly on the boundary
    /// bleeds the neighboring slice's row into the band edge, a seam that
    /// magnifies to a visible line when the band stretches near the camera.
    func testBandTextureSlicesAreInsetFromSliceBoundaries() {
        let (_, world, _) = makeWorld()
        let count = CGFloat(Tuning.Encounter.groundBandCount)
        for (i, node) in world.bandNodes.enumerated() {
            guard let rect = node.texture?.textureRect() else {
                return XCTFail("band \(i) has no texture")
            }
            let sliceMinY = CGFloat(i) / count
            let sliceMaxY = CGFloat(i + 1) / count
            XCTAssertGreaterThan(rect.minY, sliceMinY - 0.0001)
            XCTAssertGreaterThan(rect.minY, sliceMinY,
                                 "band \(i) rect must be inset above its slice floor")
            XCTAssertLessThan(rect.maxY, sliceMaxY,
                              "band \(i) rect must be inset below its slice ceiling")
            XCTAssertGreaterThan(rect.height, 0)
        }
    }

    /// penguinslide-hhz: the world's layout must apply the two-sided wrap
    /// fade — a band parked just shy of the camera plane renders ~invisible
    /// instead of blinking out at full alpha.
    func testLayoutAppliesNearFadeToBandsApproachingCamera() {
        let (_, world, _) = makeWorld()
        world.startScroll()
        let dz = Tuning.Encounter.groundScrollSpeed / 60
        // March until the nearest station is inside the bottom half of the
        // near fade region, then verify that node's alpha matches the pure
        // function and is well below 1.
        let nearDepth = world.bandField.zSpan * Tuning.Encounter.groundBandNearFadeFraction
        for _ in 0..<(60 * 30) {
            world.update(dt: 1.0 / 60.0)
            if let z = world.bandField.stations.min(), z < nearDepth * 0.5 {
                let index = world.bandField.stations.firstIndex(of: z)!
                let node = world.bandNodes[index]
                XCTAssertEqual(node.alpha,
                               encounterBandAlpha(z: z, zSpan: world.bandField.zSpan),
                               accuracy: 0.001)
                XCTAssertLessThan(node.alpha, 0.55)
                return
            }
        }
        XCTFail("no station entered the near fade region in 30 simulated seconds (dz/frame = \(dz))")
    }

    func testBandDepthSortNearerBandsDrawOnTop() {
        let (_, world, _) = makeWorld()
        // Stations seed in ascending z, so zPositions must be strictly
        // descending (nearer band = higher zPosition within -70..-60).
        let zPositions = world.bandNodes.map(\.zPosition)
        for (a, b) in zip(zPositions, zPositions.dropFirst()) {
            XCTAssertGreaterThan(a, b)
        }
        for zp in zPositions {
            XCTAssertGreaterThan(zp, -70)
            XCTAssertLessThanOrEqual(zp, -60)
        }
    }
}
