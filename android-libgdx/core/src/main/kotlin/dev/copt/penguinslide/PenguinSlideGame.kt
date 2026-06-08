package dev.copt.penguinslide

import com.badlogic.gdx.Game
import dev.copt.penguinslide.data.Persistence
import dev.copt.penguinslide.render.IcicleAnimations
import dev.copt.penguinslide.render.PenguinAnimations
import dev.copt.penguinslide.render.SpriteCatalog

/**
 * Root libGDX [Game]. Owns shared, screen-independent resources (asset catalog,
 * animations) and hands control to the active [com.badlogic.gdx.Screen].
 *
 * Mirrors the role `PenguinSlideApp` + `ContentView` play on iOS: a thin shell that
 * builds the gameplay surface once and routes lifecycle into it.
 */
class PenguinSlideGame : Game() {

    lateinit var catalog: SpriteCatalog
        private set
    lateinit var penguinAnimations: PenguinAnimations
        private set
    lateinit var icicleAnimations: IcicleAnimations
        private set

    override fun create() {
        // Load any persisted feel overrides before building gameplay (mirrors the iOS
        // `Tuning.Penguin = .loadFromUserDefaults()` first-access behaviour).
        Tuning.penguin = Persistence.loadPenguinTuning()
        catalog = SpriteCatalog().also { it.preload() }
        penguinAnimations = PenguinAnimations(catalog)
        icicleAnimations = IcicleAnimations(catalog)
        setScreen(GameScreen(this))
    }

    override fun dispose() {
        screen?.dispose()
        catalog.dispose()
        super.dispose()
    }
}
