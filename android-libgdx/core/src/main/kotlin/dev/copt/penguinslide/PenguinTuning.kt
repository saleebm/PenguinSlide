package dev.copt.penguinslide

/**
 * Mutable, persisted tuning for the penguin's input and feel — port of the iOS
 * `PenguinTuning` struct.
 *
 * The Settings UI exposes one knob, [tiltIntensity] (0 = calm, 1 = wild). It drives the
 * derived trio ([maxSpeed], [tiltResponseRate], [tiltCurve]) in lockstep via
 * [applyTiltIntensity]. The constructor seeds from [tiltIntensityDefault], so a fresh
 * instance has the derived values for t=0.25 — NOT the raw field defaults. This matches
 * the Swift `init()` which routes through `applyTiltIntensity(tiltIntensityDefault)`.
 */
class PenguinTuning {

    // Speed & input feel (the derived trio + the persisted intensity).
    var tiltIntensity = tiltIntensityDefault
    var maxSpeed = speedDefault
    var tiltCurve = 1.5f
    var tiltResponseRate = 5.0f
    var iceDecayRate = 0.7f

    // Body.
    var collisionRadiusFraction = 0.42f
    var massKg = 4.0f

    // Lean (spring-damped tilt).
    var leanMaxAngle = 0.30f
    var leanStiffness = 60f
    var leanDampingRatio = 0.55f

    // Health & i-frames.
    var maxHealth = 3
    var iFrameDuration = 1.0f
    var iFrameFlashHz = 8f
    var iFrameDimAlpha = 0.75f

    // Shield ring.
    var shieldRingLineWidth = 3f
    var shieldRingPulsePeriod = 0.3f

    // Animation.
    var idleSlideThresholdPtPerSec = 60f
    var animationFps = 8f

    // Knockback.
    var knockbackImpulseScale = 0.5f

    init {
        // Keep the derived trio coherent with the default intensity, exactly as the
        // Swift memberwise init does — the literal field defaults above for maxSpeed/
        // tiltResponseRate/tiltCurve are immediately overwritten here.
        applyTiltIntensity(tiltIntensityDefault)
    }

    /** Set intensity and recompute the derived trio together so they never drift. */
    fun applyTiltIntensity(t: Float) {
        val (s, rate, curve) = derived(t)
        tiltIntensity = t.coerceIn(0f, 1f)
        maxSpeed = s
        tiltResponseRate = rate
        tiltCurve = curve
    }

    companion object {
        const val tiltIntensityDefault = 0.25f
        const val speedDefault = 1125f
        val speedRange = 850f..1950f
        val tiltIntensityRange = 0f..1f

        // Shield-ring stroke colour (cyan), contrasting the red damage flash.
        const val shieldRingR = 0.5f
        const val shieldRingG = 0.9f
        const val shieldRingB = 1.0f

        /** Pure mapping from a 0..1 intensity to (maxSpeed, tiltResponseRate, tiltCurve). */
        fun derived(t: Float): Triple<Float, Float, Float> {
            val c = t.coerceIn(0f, 1f)
            return Triple(850f + c * 1100f, 4f + c * 2f, 1.5f - c * 0.2f)
        }
    }
}
