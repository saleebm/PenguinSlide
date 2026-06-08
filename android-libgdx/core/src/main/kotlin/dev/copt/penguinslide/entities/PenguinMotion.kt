package dev.copt.penguinslide.entities

import dev.copt.penguinslide.PenguinTuning
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.pow
import kotlin.math.sign

/**
 * The feel-critical, pure motion math, factored out of [Penguin] so it can be unit-tested
 * headlessly (no `Gdx`, no animations). These are exact ports of the iOS `Penguin.update`
 * velocity/knockback lines.
 */
object PenguinMotion {

    /**
     * One velocity step: tilt → curved target → frame-rate-independent exponential approach.
     * Asymmetric friction: presses use [PenguinTuning.tiltResponseRate], release uses the
     * glidey [PenguinTuning.iceDecayRate].
     */
    fun stepVelocity(vx: Float, tilt: Float, t: PenguinTuning, dt: Float): Float {
        val curvedTilt = sign(tilt) * abs(tilt).pow(t.tiltCurve)
        val targetVx = curvedTilt * t.maxSpeed
        val rate = if (tilt == 0f) t.iceDecayRate else t.tiltResponseRate
        val alpha = 1f - exp(-rate * dt)
        return vx + (targetVx - vx) * alpha
    }

    /** Knockback impulse applied to vx, pushing *away* from the impact point. */
    fun knockback(vx: Float, x: Float, impactX: Float, t: PenguinTuning): Float {
        val dir = if (x >= impactX) 1f else -1f
        return vx + dir * t.maxSpeed * t.knockbackImpulseScale
    }
}
