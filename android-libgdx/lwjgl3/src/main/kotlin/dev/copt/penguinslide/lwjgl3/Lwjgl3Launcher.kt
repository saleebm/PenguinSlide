package dev.copt.penguinslide.lwjgl3

import com.badlogic.gdx.backends.lwjgl3.Lwjgl3Application
import com.badlogic.gdx.backends.lwjgl3.Lwjgl3ApplicationConfiguration
import dev.copt.penguinslide.PenguinSlideGame

/**
 * Desktop entry point — the dev/test harness. Runs the full game with keyboard tilt,
 * which is the whole reason for the desktop target: the iOS simulator has no gyro, so
 * gameplay could only be felt on a physical device. Here it runs anywhere.
 *
 * Window is sized to the virtual landscape resolution (844x390, iPhone-14 logical points)
 * so on-screen distances match the tuning constants 1:1.
 */
fun main() {
    val config = Lwjgl3ApplicationConfiguration().apply {
        setTitle("Icy Penguin Slide")
        setWindowedMode(844, 390)
        setForegroundFPS(60)
        useVsync(true)
        setWindowIcon("sprites/appicon128.png")
    }
    Lwjgl3Application(PenguinSlideGame(), config)
}
