//
//  DepthProjector.swift
//  PenguinSlide
//
//  Pure pseudo-3D projection math for the Snow Monster encounter
//  (penguinslide-gyu.7). SpriteKit is 2D; the encounter fakes depth with a
//  single-vanishing-point perspective, and THIS type is the one canonical
//  geometry authority: every encounter element (monster, snowballs, ground
//  bands, lane markings, shadows) must be positioned through `project` so
//  the scene never disagrees with itself.
//
//  ## Coordinate system (canonical doc — consumer beads read this)
//
//  - **worldX**: lateral position in *screen points at the camera plane*
//    (z = 0). At z = 0 the projection is the identity laterally:
//    `project(worldX: x, z: 0).point.x == x`. Papi's dodge corridor
//    (`Tuning.Encounter.papiLateralRange`) and snowball aim/hit math
//    (`lateralHitRadius`, `severityRadius`) are all expressed in these units.
//  - **z**: virtual depth in points *into* the scene. z = 0 is the
//    camera/Papi plane (scale 1.0); z = `Tuning.Encounter.zMonster` is the
//    monster's station. Negative z is clamped to 0 — a snowball crossing the
//    camera plane must never invert or blow up; the collision/dodge pass culls
//    it before the visual ever matters.
//  - **Vanishing point**: owned by the projector. The scene-size initializer
//    places it at horizontal scene center on the horizon line
//    (`Tuning.Encounter.horizonYFraction` × scene height); the memberwise
//    initializer exists for tests and any future off-center composition.
//
//  ## Projection
//
//      t       = focal / (focal + z)                      // 1 at camera, → 0 far
//      screenX = vanishingX + (worldX - vanishingX) * t   // converges to VP
//      screenY = horizonY - (horizonY - papiPlaneY) * t   // papiPlaneY → horizon
//      scale   = t
//
//  With the shipped knobs (focal 300, zMonster 900) the monster renders at
//  scale 300/(300+900) = 0.25.
//
//  No SpriteKit node dependencies — CG types in, CG types out — so the math
//  is trivially unit-testable (DepthProjectorTests) and shared by the world
//  builder (.10), monster (.12), avatar (.11), and snowball system (.13).
//

import CoreGraphics

struct DepthProjector: Equatable {

    /// Degenerate-focal policy: a focal length ≤ 0 is *clamped* to this
    /// floor (not trapped) so a bad knob edit degrades to an extreme
    /// wide-angle look instead of NaN positions or a runtime crash.
    static let minFocal: CGFloat = 1

    /// Screen x of the vanishing point (also the convergence target for
    /// lateral positions as z grows).
    let vanishingX: CGFloat
    /// Screen y of the horizon line that screenY approaches as z → ∞.
    let horizonY: CGFloat
    /// Screen y of the camera/Papi plane (the z = 0 station).
    let papiPlaneY: CGFloat
    /// Perspective constant: scale = focal / (focal + z). Always ≥ `minFocal`.
    let focal: CGFloat

    init(vanishingX: CGFloat, horizonY: CGFloat, papiPlaneY: CGFloat, focal: CGFloat) {
        self.vanishingX = vanishingX
        self.horizonY = horizonY
        self.papiPlaneY = papiPlaneY
        self.focal = max(focal, Self.minFocal)
    }

    /// Standard configuration: geometry knobs from `Tuning.Encounter`
    /// resolved against the live scene size. Vanishing point sits at
    /// horizontal center on the horizon line.
    init(sceneSize: CGSize) {
        self.init(
            vanishingX: sceneSize.width / 2,
            horizonY: sceneSize.height * Tuning.Encounter.horizonYFraction,
            papiPlaneY: sceneSize.height * Tuning.Encounter.papiPlaneYFraction,
            focal: Tuning.Encounter.focal
        )
    }

    /// Perspective attenuation factor `t = focal / (focal + z)`: 1.0 at the
    /// camera plane, monotonically shrinking toward 0 with depth. Negative z
    /// clamps to the z = 0 value. Exposed separately so consumers that only
    /// need scale (shadow alpha ramps, zPosition depth sorting) skip the
    /// point math.
    func depthFactor(z: CGFloat) -> CGFloat {
        focal / (focal + max(z, 0))
    }

    /// Project a world-space position to screen point + sprite scale.
    func project(worldX: CGFloat, z: CGFloat) -> (point: CGPoint, scale: CGFloat) {
        let t = depthFactor(z: z)
        let screenX = vanishingX + (worldX - vanishingX) * t
        let screenY = horizonY - (horizonY - papiPlaneY) * t
        return (CGPoint(x: screenX, y: screenY), t)
    }
}
