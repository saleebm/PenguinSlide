package dev.copt.penguinslide

import com.badlogic.gdx.Gdx
import com.badlogic.gdx.Input
import com.badlogic.gdx.InputAdapter
import com.badlogic.gdx.ScreenAdapter
import com.badlogic.gdx.graphics.GL20
import com.badlogic.gdx.graphics.OrthographicCamera
import com.badlogic.gdx.graphics.PixmapIO
import com.badlogic.gdx.graphics.g2d.SpriteBatch
import com.badlogic.gdx.graphics.g2d.TextureRegion
import com.badlogic.gdx.graphics.glutils.ShapeRenderer
import com.badlogic.gdx.math.MathUtils
import com.badlogic.gdx.math.Vector3
import com.badlogic.gdx.utils.ScreenUtils
import com.badlogic.gdx.utils.viewport.ExtendViewport
import dev.copt.penguinslide.audio.GameAudio
import dev.copt.penguinslide.data.HighScore
import dev.copt.penguinslide.data.Persistence
import dev.copt.penguinslide.entities.Penguin
import dev.copt.penguinslide.input.TiltProvider
import dev.copt.penguinslide.input.defaultTiltProvider
import dev.copt.penguinslide.render.FxTextures
import dev.copt.penguinslide.render.Sprite
import dev.copt.penguinslide.systems.IcicleSystem
import dev.copt.penguinslide.ui.Hud
import dev.copt.penguinslide.ui.Overlays
import kotlin.math.min

/**
 * The gameplay surface — libGDX equivalent of the SpriteKit `GameScene` + the SwiftUI shell
 * around it. Orchestrates the penguin, icicle system, camera shake, audio, HUD, scoring, and
 * the TITLE → PLAYING → GAMEOVER state machine with a settings overlay.
 */
class GameScreen(private val game: PenguinSlideGame) : ScreenAdapter() {

    private enum class State { TITLE, PLAYING, GAMEOVER }

    private val camera = OrthographicCamera()
    private val viewport = ExtendViewport(VIRTUAL_W, VIRTUAL_H, camera)
    private val hudCamera = OrthographicCamera()
    private val batch = SpriteBatch()
    private val shapes = ShapeRenderer()
    private val tiltProvider: TiltProvider = defaultTiltProvider()
    private val fx = FxTextures()
    private val audio = GameAudio()

    private var worldW = VIRTUAL_W
    private var worldH = VIRTUAL_H
    private var iceTopY = 0f
    private var iceFloorY = 0f
    private var penguinBaseY = 0f
    private var iceLeftX = 0f
    private var iceRightX = 0f

    private lateinit var iceField: TextureRegion
    private var penguin: Penguin? = null
    private var icicles: IcicleSystem? = null
    private var hud: Hud? = null
    private var overlays: Overlays? = null

    private var state = State.TITLE
    private var settingsOpen = false
    private var elapsed = 0f

    // Scoring state.
    private var score = 0
    private var bonusPoints = 0
    private var combo = 0
    private var lastCloseCallTime = 0f
    private var best = Persistence.bestScore()
    private var isNewBest = false
    private var scoreSaved = false

    private var playerName = Persistence.playerName()
    private var leaderboard: List<HighScore> = Persistence.highScores()

    // Camera shake.
    private var shakeTime = 0f
    private var shakeAmp = 0f
    private var draggingSlider = false

    // Dev screenshot + auto-drive hooks (no effect in normal runs).
    private val screenshotAt = System.getProperty("ps.screenshot")?.toFloatOrNull() ?: -1f
    private val autoStart = System.getProperty("ps.autostart")?.toBoolean() ?: false
    private val forceGameOverAt = System.getProperty("ps.forceGameOverAt")?.toFloatOrNull() ?: -1f
    private val openSettingsOnStart = System.getProperty("ps.openSettings")?.toBoolean() ?: false
    private var realTime = 0f

    private val input = object : InputAdapter() {
        override fun touchDown(screenX: Int, screenY: Int, pointer: Int, button: Int): Boolean {
            val w = unproject(screenX, screenY)
            return handleTap(w.x, w.y)
        }

        override fun touchDragged(screenX: Int, screenY: Int, pointer: Int): Boolean {
            if (draggingSlider) {
                val w = unproject(screenX, screenY)
                applyTiltIntensity(overlays!!.sliderValueFor(w.x))
                return true
            }
            return false
        }

        override fun touchUp(screenX: Int, screenY: Int, pointer: Int, button: Int): Boolean {
            draggingSlider = false
            return false
        }

        override fun keyDown(keycode: Int): Boolean {
            when (keycode) {
                Input.Keys.SPACE, Input.Keys.ENTER -> {
                    if (state == State.TITLE && !settingsOpen) { startGame(); return true }
                    if (state == State.GAMEOVER && !settingsOpen) { playAgain(); return true }
                }
                Input.Keys.G -> { // debug: force game over
                    if (state == State.PLAYING) { triggerGameOver(); return true }
                }
            }
            return false
        }
    }

    private val scratch = Vector3()
    private fun unproject(screenX: Int, screenY: Int): Vector3 {
        scratch.set(screenX.toFloat(), screenY.toFloat(), 0f)
        hudCamera.unproject(scratch)
        return scratch
    }

    override fun show() {
        audio.startMusic()
        Gdx.input.inputProcessor = input
        if (autoStart) startGame()
        if (openSettingsOnStart) settingsOpen = true
    }

    override fun resize(width: Int, height: Int) {
        viewport.update(width, height, true)
        worldW = viewport.worldWidth
        worldH = viewport.worldHeight
        hudCamera.setToOrtho(false, worldW, worldH)
        hudCamera.update()
        iceTopY = worldH * 0.28f
        iceFloorY = iceTopY * 0.55f
        penguinBaseY = iceFloorY + 42f
        val playW = worldW * Tuning.Run.playWidthFraction
        iceLeftX = (worldW - playW) / 2f
        iceRightX = iceLeftX + playW
        iceField = game.catalog.tiled(Sprite.ICE_TILE, worldW.toInt(), iceTopY.toInt())

        if (penguin == null) build()
    }

    private fun build() {
        val h = Hud(worldW, worldH, fx).also { it.setBest(best); it.showStartPrompt() }
        hud = h
        overlays = Overlays(worldW, worldH, fx)
        val p = Penguin(penguinBaseY, iceLeftX, iceRightX, game.penguinAnimations).also {
            it.onHealthChanged = { hp -> h.setHealth(hp) }
        }
        penguin = p
        icicles = IcicleSystem(
            worldH = worldH, iceLandingY = iceFloorY, iceLeftX = iceLeftX, iceRightX = iceRightX,
            catalog = game.catalog, icicleAnims = game.icicleAnimations, fx = fx, audio = audio, penguin = p,
        ).also {
            it.onShake = { amp -> shakeAmp = amp; shakeTime = SHAKE_DURATION }
            it.onCloseCall = { severity, x -> registerCloseCall(severity, x) }
            it.onPenguinHit = { accepted -> if (accepted) { combo = 0; h.hideCombo() } }
        }
    }

    // ---- state transitions ----

    private fun startGame() {
        if (state != State.TITLE) return
        state = State.PLAYING
        hud?.dismissStartPrompt()
    }

    private fun triggerGameOver() {
        if (state == State.GAMEOVER) return
        state = State.GAMEOVER
        isNewBest = score > best
        if (isNewBest) { best = score; Persistence.setBestScore(best); hud?.setBest(best) }
        penguin?.triggerDeath()
        icicles?.freeze()
        hud?.triggerDeathFlash()
        audio.playGameOver()
        leaderboard = Persistence.highScores()
        scoreSaved = false
    }

    private fun playAgain() {
        penguin?.reset()
        icicles?.reset()
        elapsed = 0f; score = 0; bonusPoints = 0; combo = 0; lastCloseCallTime = 0f
        isNewBest = false; scoreSaved = false
        hud?.apply { setScore(0); hideCombo() }
        state = State.PLAYING
    }

    private fun registerCloseCall(severity: Float, x: Float) {
        combo += 1
        lastCloseCallTime = elapsed
        val bonus = Scoring.closeCallBonus(severity, combo)
        bonusPoints += bonus
        hud?.floatBonus(bonus, x, iceFloorY + 20f)
        if (combo >= 2) hud?.showCombo(combo)
    }

    // ---- input handling ----

    private fun handleTap(x: Float, y: Float): Boolean {
        val ov = overlays ?: return false
        if (settingsOpen) {
            when {
                ov.sliderTrack.let { x >= it.x - 14 && x <= it.x + it.width + 14 && y >= it.y - 16 && y <= it.y + 24 } -> {
                    draggingSlider = true; applyTiltIntensity(ov.sliderValueFor(x))
                }
                ov.changeNameButton.contains(x, y) -> promptName()
                ov.resetButton.contains(x, y) -> applyTiltIntensity(PenguinTuning.tiltIntensityDefault)
                ov.closeButton.contains(x, y) -> settingsOpen = false
            }
            return true
        }
        if (state == State.GAMEOVER) {
            when {
                ov.saveButton.contains(x, y) -> saveScore()
                ov.playAgainButton.contains(x, y) -> playAgain()
            }
            return true
        }
        // TITLE / PLAYING
        if (ov.settingsButton.contains(x, y)) { settingsOpen = true; return true }
        if (state == State.TITLE) { startGame(); return true }
        return false
    }

    private fun applyTiltIntensity(v: Float) {
        Tuning.penguin.applyTiltIntensity(v)
        Persistence.savePenguinTuning(Tuning.penguin)
    }

    private fun promptName() {
        Gdx.input.getTextInput(object : Input.TextInputListener {
            override fun input(text: String) = Gdx.app.postRunnable {
                playerName = text.trim()
                Persistence.setPlayerName(playerName)
            }
            override fun canceled() {}
        }, "Your name", playerName, "Anonymous")
    }

    private fun saveScore() {
        if (scoreSaved || score <= 0) return
        Gdx.input.getTextInput(object : Input.TextInputListener {
            override fun input(text: String) = Gdx.app.postRunnable {
                val name = text.trim().ifBlank { "Anonymous" }
                playerName = name
                Persistence.setPlayerName(name)
                leaderboard = Persistence.addHighScore(
                    HighScore(name = name, score = score, date = System.currentTimeMillis(), id = "$name-$score")
                )
                scoreSaved = true
            }
            override fun canceled() {}
        }, "Name your run", playerName, "Anonymous")
    }

    // ---- frame ----

    override fun render(delta: Float) {
        realTime += delta
        val dt = min(delta, MAX_DT)
        val p = penguin
        val ice = icicles
        val h = hud

        if (forceGameOverAt > 0f && realTime >= forceGameOverAt && state == State.PLAYING) {
            triggerGameOver()
        }

        val active = state == State.PLAYING && !settingsOpen
        if (active && p != null && ice != null) {
            elapsed += dt
            if (combo > 0 && elapsed - lastCloseCallTime > Tuning.Score.comboWindow) {
                combo = 0; h?.hideCombo()
            }
            p.update(dt, tiltProvider.tilt())
            ice.update(dt, elapsed)
            score = Scoring.survivalScore(elapsed) + bonusPoints
            h?.setScore(score)
            if (!p.isAlive()) triggerGameOver()
        }
        if (!settingsOpen) h?.update(dt)

        updateShake(dt)

        Gdx.gl.glClearColor(SKY_R, SKY_G, SKY_B, 1f)
        Gdx.gl.glClear(GL20.GL_COLOR_BUFFER_BIT)

        camera.update()
        batch.projectionMatrix = camera.combined
        batch.begin()
        batch.draw(game.catalog.texture(Sprite.SKY), 0f, 0f, worldW, worldH)
        batch.draw(iceField, 0f, 0f)
        ice?.render(batch)
        p?.render(batch)
        batch.end()

        drawShieldRing(p)

        // HUD + overlays in stationary space.
        batch.projectionMatrix = hudCamera.combined
        batch.begin()
        h?.render(batch)
        if (state != State.GAMEOVER && !settingsOpen) overlays?.renderSettingsButton(batch)
        if (state == State.GAMEOVER && !settingsOpen) overlays?.renderGameOver(batch, score, isNewBest, leaderboard)
        if (settingsOpen) overlays?.renderSettings(batch, Tuning.penguin.tiltIntensity, playerName, VERSION)
        batch.end()

        maybeCaptureScreenshot()
    }

    private fun updateShake(dt: Float) {
        if (shakeTime > 0f) {
            shakeTime -= dt
            val k = (shakeTime / SHAKE_DURATION).coerceAtLeast(0f)
            val ox = MathUtils.random(-1f, 1f) * shakeAmp * k
            val oy = MathUtils.random(-1f, 1f) * shakeAmp * 0.5f * k
            camera.position.set(worldW / 2f + ox, worldH / 2f + oy, 0f)
        } else {
            camera.position.set(worldW / 2f, worldH / 2f, 0f)
        }
    }

    private fun drawShieldRing(p: Penguin?) {
        if (p == null || !p.shieldVisible || p.shieldAlpha <= 0f) return
        Gdx.gl.glEnable(GL20.GL_BLEND)
        shapes.projectionMatrix = camera.combined
        shapes.begin(ShapeRenderer.ShapeType.Line)
        Gdx.gl.glLineWidth(Tuning.penguin.shieldRingLineWidth)
        shapes.setColor(PenguinTuning.shieldRingR, PenguinTuning.shieldRingG, PenguinTuning.shieldRingB, p.shieldAlpha)
        shapes.circle(p.shieldCx, p.shieldCy, p.shieldRadius * p.shieldScale, 32)
        shapes.end()
    }

    override fun pause() = audio.pauseMusic()
    override fun resume() = audio.resumeMusic()

    override fun dispose() {
        batch.dispose(); shapes.dispose(); fx.dispose(); audio.dispose()
        hud?.dispose(); overlays?.dispose()
    }

    private fun maybeCaptureScreenshot() {
        if (screenshotAt <= 0f) return
        if (realTime < screenshotAt) return
        val path = System.getProperty("ps.screenshotFile") ?: "screenshot.png"
        val pm = ScreenUtils.getFrameBufferPixmap(0, 0, Gdx.graphics.backBufferWidth, Gdx.graphics.backBufferHeight)
        flipVertical(pm)
        PixmapIO.writePNG(Gdx.files.absolute(path), pm)
        pm.dispose()
        Gdx.app.exit()
    }

    private fun flipVertical(pm: com.badlogic.gdx.graphics.Pixmap) {
        val w = pm.width; val h = pm.height
        val stride = w * 4
        val buf = pm.pixels
        val top = ByteArray(stride); val bot = ByteArray(stride)
        for (y in 0 until h / 2) {
            val ty = y * stride; val by = (h - 1 - y) * stride
            buf.position(ty); buf.get(top)
            buf.position(by); buf.get(bot)
            buf.position(ty); buf.put(bot)
            buf.position(by); buf.put(top)
        }
        buf.position(0)
    }

    companion object {
        const val VIRTUAL_W = 844f
        const val VIRTUAL_H = 390f
        const val VERSION = "1.3.0"
        private const val MAX_DT = 0.05f
        private const val SHAKE_DURATION = 0.18f

        private const val SKY_R = 0.62f
        private const val SKY_G = 0.80f
        private const val SKY_B = 0.92f
    }
}
