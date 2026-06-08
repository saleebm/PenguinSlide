package dev.copt.penguinslide.entities

import com.badlogic.gdx.graphics.Color
import com.badlogic.gdx.graphics.g2d.SpriteBatch
import com.badlogic.gdx.math.MathUtils
import dev.copt.penguinslide.PenguinTuning
import dev.copt.penguinslide.Tuning
import dev.copt.penguinslide.render.PenguinAnimState
import dev.copt.penguinslide.render.PenguinAnimations
import kotlin.math.abs
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The player's penguin: position, tilt-driven motion/lean, and HP / i-frames / knockback.
 * Faithful port of the iOS `Penguin`.
 *
 * No physics engine: position is the single source of truth, written manually each frame.
 * The hit logic runs on a [localElapsed] clock independent of the scene so it stays
 * self-contained. Rendering (sprite + shield ring) is pulled by [GameScreen] via the
 * exposed state, mirroring how the iOS scene let SpriteKit draw the node.
 */
class Penguin(
    private val baseY: Float,
    private val leftBound: Float,
    private val rightBound: Float,
    private val animations: PenguinAnimations,
) {
    var x = (leftBound + rightBound) / 2f
        private set
    var y = baseY
        private set
    var vx = 0f
        private set
    var hp = Tuning.penguin.maxHealth
        private set

    /** Fired when [hp] changes (accepted hit, or [reset]) — GameScreen wires it to the HUD. */
    var onHealthChanged: ((Int) -> Unit)? = null

    private val tuning get() = Tuning.penguin

    private var localElapsed = 0f
    private var invulnerableUntil = 0f
    private var bobPhase = 0f
    private var leanVelocity = 0f
    private var rotationRad = 0f

    private var animState = PenguinAnimState.IDLE
    private var stateTime = 0f
    private var oneShotUntil = 0f

    // Visual feedback timers (procedural ports of the SKAction tints/squash).
    private var hurtFlash = 0f      // seconds remaining on the red flash
    private var squashTime = 0f     // seconds elapsed into the squash, -1 when idle
    private var dead = false

    // Exposed render state, read by GameScreen each frame.
    var alpha = 1f; private set
    var scaleX = 1f; private set
    var scaleY = 1f; private set
    val rotationDeg get() = rotationRad * MathUtils.radiansToDegrees

    var shieldVisible = false; private set
    var shieldAlpha = 0f; private set
    var shieldScale = 1f; private set
    /** Hitbox centre = sprite centre raised by [HITBOX_OFFSET_Y]; the shield ring wraps it. */
    val shieldCx get() = x
    val shieldCy get() = y + HITBOX_OFFSET_Y
    val shieldRadius get() = WIDTH * tuning.collisionRadiusFraction + 6f

    /** Per-frame tick. [tilt] is in [-1, 1]. */
    fun update(dt: Float, tilt: Float) {
        localElapsed += dt

        // Ice-feel: tilt sets a target velocity; actual velocity glides toward it via a
        // frame-rate-independent exponential approach (see PenguinMotion).
        vx = PenguinMotion.stepVelocity(vx, tilt, tuning, dt)

        val halfW = WIDTH * 0.42f
        val minX = leftBound + halfW
        val maxX = rightBound - halfW
        var newX = x + vx * dt
        if (newX < minX) { newX = minX; vx = 0f }
        if (newX > maxX) { newX = maxX; vx = 0f }

        bobPhase += dt
        val bobY = sin(bobPhase * 5.2f) * 3f
        x = newX
        y = baseY + bobY

        // Spring-damped lean: a = ω₀²·error − 2·ω₀·ζ·v, with ω₀ = sqrt(stiffness).
        val leanTarget = -(vx / tuning.maxSpeed) * tuning.leanMaxAngle
        val leanError = leanTarget - rotationRad
        val omega = sqrt(tuning.leanStiffness)
        val leanAccel = tuning.leanStiffness * leanError - 2f * omega * tuning.leanDampingRatio * leanVelocity
        leanVelocity += leanAccel * dt
        rotationRad += leanVelocity * dt

        updateAnimationState(dt)
        updateInvulnerabilityVisuals()
        updateFlashAndSquash(dt)
    }

    private fun updateAnimationState(dt: Float) {
        val desired = when {
            localElapsed < oneShotUntil -> animState // keep one-shot running
            abs(vx) < tuning.idleSlideThresholdPtPerSec -> PenguinAnimState.IDLE
            else -> PenguinAnimState.SLIDE
        }
        if (desired != animState) startAnimation(desired) else stateTime += dt
    }

    private fun updateInvulnerabilityVisuals() {
        val invulnerable = localElapsed < invulnerableUntil
        if (invulnerable) {
            // Soft alpha pulse so the penguin stays readable; ring is the primary tell.
            val lit = sin(localElapsed * 2f * MathUtils.PI * tuning.iFrameFlashHz) > 0f
            if (hurtFlash <= 0f) alpha = if (lit) 1f else tuning.iFrameDimAlpha
            shieldVisible = true
            val k = 0.5f + 0.5f * sin(localElapsed * MathUtils.PI / tuning.shieldRingPulsePeriod)
            shieldAlpha = 0.4f + 0.4f * k
            shieldScale = 1f + 0.15f * k
        } else {
            if (!dead && hurtFlash <= 0f) alpha = 1f
            shieldVisible = false
            shieldAlpha = 0f
            shieldScale = 1f
        }
    }

    private fun updateFlashAndSquash(dt: Float) {
        if (hurtFlash > 0f) hurtFlash = (hurtFlash - dt).coerceAtLeast(0f)
        if (squashTime >= 0f) {
            squashTime += dt
            // 0.05 s squash to 0.92, 0.05 s hold, 0.12 s back to 1.0 (matches the SKAction).
            val s = when {
                squashTime < 0.05f -> MathUtils.lerp(1f, 0.92f, squashTime / 0.05f)
                squashTime < 0.10f -> 0.92f
                squashTime < 0.22f -> MathUtils.lerp(0.92f, 1f, (squashTime - 0.10f) / 0.12f)
                else -> { squashTime = -1f; 1f }
            }
            if (!dead) { scaleX = s; scaleY = s }
        }
    }

    fun isAlive() = hp > 0

    /**
     * Try to land a hit. Returns true if HP was decremented, false if absorbed by i-frames.
     * The caller drives the icicle recoil/FX either way.
     */
    fun tryTakeHit(impactX: Float): Boolean {
        if (localElapsed < invulnerableUntil) return false
        hp = (hp - 1).coerceAtLeast(0)
        if (hp > 0) invulnerableUntil = localElapsed + tuning.iFrameDuration
        vx = PenguinMotion.knockback(vx, x, impactX, tuning)
        hurtFlash = 0.25f
        squashTime = 0f
        startAnimation(PenguinAnimState.HURT)
        onHealthChanged?.invoke(hp)
        return true
    }

    fun playVictory() {
        if (isAlive()) startAnimation(PenguinAnimState.VICTORY)
    }

    private fun startAnimation(state: PenguinAnimState) {
        animState = state
        stateTime = 0f
        val anim = animations.forState(state)
        oneShotUntil = if (anim.playMode == com.badlogic.gdx.graphics.g2d.Animation.PlayMode.LOOP) {
            0f
        } else {
            localElapsed + anim.animationDuration
        }
    }

    /** Death feedback (HP == 0): scale down, fade, and rotate; freeze the sprite loop. */
    fun triggerDeath() {
        dead = true
        scaleX = 0.9f; scaleY = 0.9f
        alpha = 0.6f
        rotationRad += MathUtils.PI / 6f
        shieldVisible = false
        shieldAlpha = 0f
    }

    fun reset() {
        x = (leftBound + rightBound) / 2f
        y = baseY
        vx = 0f
        hp = tuning.maxHealth
        localElapsed = 0f
        invulnerableUntil = 0f
        bobPhase = 0f
        leanVelocity = 0f
        rotationRad = 0f
        alpha = 1f; scaleX = 1f; scaleY = 1f
        hurtFlash = 0f; squashTime = -1f; dead = false
        shieldVisible = false; shieldAlpha = 0f; shieldScale = 1f
        startAnimation(PenguinAnimState.IDLE)
        onHealthChanged?.invoke(hp)
    }

    /** Draw the penguin sprite with its current lean, scale, alpha, and hurt tint. */
    fun render(batch: SpriteBatch) {
        val loop = animations.forState(animState).playMode ==
            com.badlogic.gdx.graphics.g2d.Animation.PlayMode.LOOP
        val frame = animations.forState(animState).getKeyFrame(stateTime, loop)

        // Hurt flash: redden multiplicatively (approximates the additive SKAction flash).
        val flash = (hurtFlash / 0.25f).coerceIn(0f, 1f) * 0.7f
        batch.setColor(1f, 1f - flash, 1f - flash, alpha)
        batch.draw(
            frame,
            x - WIDTH / 2f, y - HEIGHT / 2f,
            WIDTH / 2f, HEIGHT / 2f,
            WIDTH, HEIGHT,
            scaleX, scaleY,
            rotationDeg,
        )
        batch.setColor(Color.WHITE)
    }

    companion object {
        const val WIDTH = 70f
        const val HEIGHT = 84f
        private const val HITBOX_OFFSET_Y = 14f
    }
}
