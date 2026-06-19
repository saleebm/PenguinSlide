//
//  DepthProjectorTests.swift
//  PenguinSlideTests
//
//  penguinslide-gyu.7 acceptance suite: projection invariants for the
//  encounter's single-vanishing-point pseudo-3D math. Every encounter
//  element shares this projector, so a regression here visually breaks the
//  whole faux-3D scene — the assertions below are the geometry contract.
//

import XCTest
@testable import PenguinSlide

final class DepthProjectorTests: XCTestCase {

    /// iPhone-ish portrait scene used by most tests.
    private let sceneSize = CGSize(width: 390, height: 844)

    private var projector: DepthProjector { DepthProjector(sceneSize: sceneSize) }

    private let accuracy: CGFloat = 1e-9

    // MARK: - Anchor stations (z = 0 and z = zMonster)

    func testCameraPlaneProjectsAtScaleOneOnPapiPlane() {
        let p = projector
        let worldX: CGFloat = 123.45
        let (point, scale) = p.project(worldX: worldX, z: 0)

        XCTAssertEqual(scale, 1.0, accuracy: accuracy,
                       "z=0 is the camera plane: scale must be exactly 1.0, got \(scale)")
        XCTAssertEqual(point.x, worldX, accuracy: accuracy,
                       "At z=0 the lateral projection must be the identity (worldX is defined in camera-plane points); expected x=\(worldX), got \(point.x)")
        let expectedY = sceneSize.height * Tuning.Encounter.papiPlaneYFraction
        XCTAssertEqual(point.y, expectedY, accuracy: accuracy,
                       "z=0 must land on the Papi plane y (\(expectedY)), got \(point.y)")
    }

    func testMonsterDepthProjectsAtExpectedScaleAndY() {
        let p = projector
        let z = Tuning.Encounter.zMonster
        let focal = Tuning.Encounter.focal
        let expectedScale = focal / (focal + z)
        let (point, scale) = p.project(worldX: p.vanishingX, z: z)

        XCTAssertEqual(scale, expectedScale, accuracy: accuracy,
                       "Scale at zMonster must be focal/(focal+zMonster) = \(expectedScale), got \(scale)")
        // Shipped knobs: 300 / (300 + 900) = 0.25 (recorded in the .4 knob docs).
        XCTAssertEqual(scale, 0.25, accuracy: 1e-6,
                       "With shipped knobs (focal 300, zMonster 900) the monster scale must be 0.25, got \(scale) — a knob or formula drifted")

        let expectedY = p.horizonY - (p.horizonY - p.papiPlaneY) * expectedScale
        XCTAssertEqual(point.y, expectedY, accuracy: accuracy,
                       "screenY at zMonster must sit \(expectedScale) of the way from horizon toward the Papi plane; expected \(expectedY), got \(point.y)")
        XCTAssertGreaterThan(point.y, sceneSize.height * Tuning.Encounter.papiPlaneYFraction,
                             "Far depth must render ABOVE the Papi plane (closer to the horizon)")
        XCTAssertLessThan(point.y, p.horizonY,
                          "No finite depth may reach or pass the horizon line")
    }

    // MARK: - Monotonicity in z

    func testScaleAndScreenYAreStrictlyMonotonicInZ() {
        let p = projector
        let worldX: CGFloat = 80
        var previous = p.project(worldX: worldX, z: 0)
        // Sweep well past zMonster to cover any future deeper stations.
        for step in 1...60 {
            let z = CGFloat(step) * 25 // 25 ... 1500
            let current = p.project(worldX: worldX, z: z)
            XCTAssertLessThan(current.scale, previous.scale,
                              "Scale must strictly shrink with depth: scale(z=\(z)) = \(current.scale) !< scale(z=\(z - 25)) = \(previous.scale)")
            XCTAssertGreaterThan(current.point.y, previous.point.y,
                                 "screenY must strictly rise toward the horizon with depth: y(z=\(z)) = \(current.point.y) !> y(z=\(z - 25)) = \(previous.point.y)")
            previous = current
        }
    }

    func testScreenXConvergesTowardVanishingPointWithDepth() {
        let p = projector
        for worldX: CGFloat in [-300, -50, 60, 350] {
            var previousDistance = abs(p.project(worldX: worldX, z: 0).point.x - p.vanishingX)
            for step in 1...40 {
                let z = CGFloat(step) * 50 // 50 ... 2000
                let distance = abs(p.project(worldX: worldX, z: z).point.x - p.vanishingX)
                XCTAssertLessThan(distance, previousDistance,
                                  "Lateral distance to the vanishing point must strictly shrink with depth (worldX=\(worldX)): |dx|(z=\(z)) = \(distance) !< \(previousDistance)")
                previousDistance = distance
            }
            // Deep limit: effectively on the vanishing line.
            let deep = p.project(worldX: worldX, z: 1_000_000).point.x
            XCTAssertEqual(deep, p.vanishingX, accuracy: 0.5,
                           "At extreme depth screenX must converge to vanishingX (\(p.vanishingX)); worldX=\(worldX) projected to \(deep)")
        }
    }

    // MARK: - Lateral consistency at equal z

    func testEqualDepthPreservesLateralOrderAndProportionalSeparation() {
        let p = projector
        let xs: [CGFloat] = [-280, -70, 0, 40, 195, 280]
        for z: CGFloat in [0, 150, 450, Tuning.Encounter.zMonster] {
            let t = p.depthFactor(z: z)
            let projected = xs.map { p.project(worldX: $0, z: z).point.x }
            for i in 1..<xs.count {
                XCTAssertLessThan(projected[i - 1], projected[i],
                                  "Lateral ORDER must be preserved at z=\(z): worldX \(xs[i - 1]) → \(projected[i - 1]) must stay left of worldX \(xs[i]) → \(projected[i])")
                let worldGap = xs[i] - xs[i - 1]
                let screenGap = projected[i] - projected[i - 1]
                XCTAssertEqual(screenGap, worldGap * t, accuracy: 1e-6,
                               "Screen separation must equal world separation × depthFactor at z=\(z): expected \(worldGap * t), got \(screenGap)")
            }
        }
    }

    // MARK: - Degenerate inputs

    func testNegativeZClampsToCameraPlaneProjection() {
        let p = projector
        let worldX: CGFloat = -42
        let reference = p.project(worldX: worldX, z: 0)
        for z: CGFloat in [-0.001, -25, -900, -1e9] {
            let clamped = p.project(worldX: worldX, z: z)
            XCTAssertEqual(clamped.scale, reference.scale, accuracy: accuracy,
                           "z=\(z) must clamp to the z=0 scale (a ball crossing the camera plane must never invert/explode); got \(clamped.scale)")
            XCTAssertEqual(clamped.point.x, reference.point.x, accuracy: accuracy,
                           "z=\(z) must clamp to the z=0 screenX; got \(clamped.point.x)")
            XCTAssertEqual(clamped.point.y, reference.point.y, accuracy: accuracy,
                           "z=\(z) must clamp to the z=0 screenY; got \(clamped.point.y)")
        }
    }

    func testDegenerateFocalClampsToSafeFloor() {
        // Policy (asserted, per bead spec): zero/negative focal CLAMPS to
        // DepthProjector.minFocal rather than trapping, so a bad knob edit
        // degrades visually instead of producing NaN or a crash.
        for badFocal: CGFloat in [0, -1, -300] {
            let p = DepthProjector(vanishingX: 195, horizonY: 523, papiPlaneY: 186, focal: badFocal)
            XCTAssertEqual(p.focal, DepthProjector.minFocal,
                           "focal=\(badFocal) must clamp to the \(DepthProjector.minFocal) floor, got \(p.focal)")
            let (point, scale) = p.project(worldX: 100, z: 900)
            XCTAssertFalse(scale.isNaN || point.x.isNaN || point.y.isNaN,
                           "Clamped-focal projection must stay finite, got point=\(point) scale=\(scale)")
            XCTAssertGreaterThan(scale, 0, "Scale must remain positive after focal clamping, got \(scale)")
            XCTAssertLessThanOrEqual(scale, 1, "Scale must not exceed 1 after focal clamping, got \(scale)")
        }
    }

    // MARK: - Resolution independence

    func testNormalizedLayoutIsIdenticalAcrossSceneSizes() {
        let small = CGSize(width: 390, height: 844)   // iPhone portrait
        let large = CGSize(width: 1024, height: 1366) // iPad portrait
        let pSmall = DepthProjector(sceneSize: small)
        let pLarge = DepthProjector(sceneSize: large)

        // Compare positions expressed as worldX fractions of scene width and
        // screen output normalized by scene dimensions.
        for worldXFraction: CGFloat in [-0.4, -0.1, 0, 0.25, 0.45] {
            for z: CGFloat in [0, 200, 600, Tuning.Encounter.zMonster] {
                let resultSmall = pSmall.project(
                    worldX: small.width / 2 + worldXFraction * small.width, z: z)
                let resultLarge = pLarge.project(
                    worldX: large.width / 2 + worldXFraction * large.width, z: z)

                XCTAssertEqual(resultSmall.scale, resultLarge.scale, accuracy: 1e-9,
                               "Perspective scale must not depend on scene size (worldXFrac=\(worldXFraction), z=\(z)): \(resultSmall.scale) vs \(resultLarge.scale)")
                XCTAssertEqual(resultSmall.point.x / small.width,
                               resultLarge.point.x / large.width, accuracy: 1e-9,
                               "Normalized screenX must match across scene sizes (worldXFrac=\(worldXFraction), z=\(z))")
                XCTAssertEqual(resultSmall.point.y / small.height,
                               resultLarge.point.y / large.height, accuracy: 1e-9,
                               "Normalized screenY must match across scene sizes (worldXFrac=\(worldXFraction), z=\(z))")
            }
        }
    }
}
