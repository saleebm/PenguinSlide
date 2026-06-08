package dev.copt.penguinslide

import dev.copt.penguinslide.entities.PenguinMotion
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import kotlin.math.abs
import kotlin.math.pow

private const val EPS = 0.5f

class PenguinMotionTest {

    private fun tuning() = PenguinTuning() // default: maxSpeed 1125, rate 4.5, curve 1.45, decay 0.7

    @Test
    fun `full tilt accelerates toward maxSpeed but never overshoots in one step`() {
        val t = tuning()
        val vx = PenguinMotion.stepVelocity(vx = 0f, tilt = 1f, t = t, dt = 1f / 60f)
        assertTrue(vx > 0f, "should accelerate right")
        assertTrue(vx < t.maxSpeed, "single step must not exceed target")
    }

    @Test
    fun `holding full tilt converges to maxSpeed over time`() {
        val t = tuning()
        var vx = 0f
        repeat(240) { vx = PenguinMotion.stepVelocity(vx, tilt = 1f, t = t, dt = 1f / 60f) }
        assertEquals(t.maxSpeed, vx, EPS) // curved target at tilt=1 is exactly maxSpeed (1^curve = 1)
    }

    @Test
    fun `releasing tilt decays velocity toward zero`() {
        val t = tuning()
        var vx = t.maxSpeed
        // Decay rate 0.7 is deliberately glidey: ~1125·e^(-7) ≈ 1 after 10s. Confirm it
        // collapses to a tiny fraction of top speed (not snappy, but unmistakably decaying).
        repeat(600) { vx = PenguinMotion.stepVelocity(vx, tilt = 0f, t = t, dt = 1f / 60f) }
        assertTrue(abs(vx) < 2f, "velocity should glide back toward 0, was $vx")
        assertTrue(abs(vx) < 0.01f * t.maxSpeed, "should be well under 1% of top speed")
    }

    @Test
    fun `tilt curve makes partial tilt target sub-linear`() {
        val t = tuning()
        // One huge dt so alpha≈1 and vx reaches the target; target = 0.5^curve * maxSpeed.
        val vx = PenguinMotion.stepVelocity(vx = 0f, tilt = 0.5f, t = t, dt = 100f)
        val expectedTarget = 0.5f.pow(t.tiltCurve) * t.maxSpeed
        assertEquals(expectedTarget, vx, 1f)
        assertTrue(expectedTarget < 0.5f * t.maxSpeed, "curve>1 makes mid tilt slower than linear")
    }

    @Test
    fun `knockback pushes away from the impact point`() {
        val t = tuning()
        // Penguin to the right of impact → shoved further right (positive impulse).
        val right = PenguinMotion.knockback(vx = 0f, x = 100f, impactX = 50f, t = t)
        assertEquals(t.maxSpeed * t.knockbackImpulseScale, right, EPS)
        // Penguin to the left of impact → shoved left (negative).
        val left = PenguinMotion.knockback(vx = 0f, x = 10f, impactX = 50f, t = t)
        assertEquals(-t.maxSpeed * t.knockbackImpulseScale, left, EPS)
    }

    @Test
    fun `velocity step is frame-rate independent over equal wall-clock`() {
        val t = tuning()
        // 1/30s steps vs 1/60s steps over the same 0.5s should land close (exponential approach).
        var coarse = 0f
        repeat(15) { coarse = PenguinMotion.stepVelocity(coarse, 1f, t, 1f / 30f) }
        var fine = 0f
        repeat(30) { fine = PenguinMotion.stepVelocity(fine, 1f, t, 1f / 60f) }
        assertEquals(coarse, fine, 15f) // close, not identical (Euler vs continuous)
    }
}
