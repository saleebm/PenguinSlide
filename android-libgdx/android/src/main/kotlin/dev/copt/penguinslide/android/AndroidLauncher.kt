package dev.copt.penguinslide.android

import android.os.Bundle
import com.badlogic.gdx.backends.android.AndroidApplication
import com.badlogic.gdx.backends.android.AndroidApplicationConfiguration
import dev.copt.penguinslide.PenguinSlideGame

/**
 * Android entry point — the ship target. Enables the accelerometer (the real tilt input;
 * the desktop launcher's keyboard is only a dev stand-in) and hands off to the shared
 * [PenguinSlideGame]. Orientation/fullscreen are set in the manifest.
 */
class AndroidLauncher : AndroidApplication() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val config = AndroidApplicationConfiguration().apply {
            useAccelerometer = true
            useCompass = false
            useGyroscope = false
            useImmersiveMode = true
        }
        initialize(PenguinSlideGame(), config)
    }
}
