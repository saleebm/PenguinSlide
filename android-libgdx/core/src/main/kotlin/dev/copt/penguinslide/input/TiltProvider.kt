package dev.copt.penguinslide.input

import com.badlogic.gdx.Gdx
import com.badlogic.gdx.Input
import com.badlogic.gdx.Input.Keys
import kotlin.math.abs

/** Source of horizontal tilt in [-1, 1] (0 = neutral). */
fun interface TiltProvider {
    fun tilt(): Float
}

/**
 * Keyboard tilt — the desktop/dev driver and the iOS `GCKeyboard` fallback equivalent.
 * Left arrow / A → -1, right arrow / D → +1. No dead zone needed (digital input).
 */
class KeyboardTiltProvider : TiltProvider {
    override fun tilt(): Float {
        val left = Gdx.input.isKeyPressed(Keys.LEFT) || Gdx.input.isKeyPressed(Keys.A)
        val right = Gdx.input.isKeyPressed(Keys.RIGHT) || Gdx.input.isKeyPressed(Keys.D)
        var t = 0f
        if (left) t = -1f
        if (right) t = 1f
        return t
    }
}

/**
 * Accelerometer tilt for Android — the analogue of the iOS `CMMotionManager.gravity`
 * read + `screenGravity` rotation. libGDX reports the accelerometer in m/s²; we normalise
 * by g, apply the same 0.04 dead zone, and clamp to [-1, 1].
 *
 * For a landscape-locked app, rolling the device left/right maps to one accelerometer
 * axis. [AXIS_SIGN] makes the direction trivial to flip after on-device verification
 * (the one thing that can't be confirmed without real hardware).
 */
class AccelerometerTiltProvider : TiltProvider {
    override fun tilt(): Float {
        // In landscape, the screen's horizontal tilt tracks the device Y axis.
        var t = (Gdx.input.accelerometerY / GRAVITY) * AXIS_SIGN
        if (abs(t) < DEAD_ZONE) t = 0f
        return t.coerceIn(-1f, 1f)
    }

    companion object {
        private const val GRAVITY = 9.81f
        private const val DEAD_ZONE = 0.04f
        // Flip to -1f if tilt direction is inverted on device (landscape-left vs right).
        private const val AXIS_SIGN = 1f
    }
}

/** Pick the right driver for the platform: accelerometer if present, else keyboard. */
fun defaultTiltProvider(): TiltProvider =
    if (Gdx.input.isPeripheralAvailable(Input.Peripheral.Accelerometer)) {
        AccelerometerTiltProvider()
    } else {
        KeyboardTiltProvider()
    }
