package dev.copt.penguinslide.ui

import com.badlogic.gdx.Gdx
import com.badlogic.gdx.graphics.Color
import com.badlogic.gdx.graphics.g2d.BitmapFont
import com.badlogic.gdx.graphics.g2d.GlyphLayout
import com.badlogic.gdx.graphics.g2d.SpriteBatch
import com.badlogic.gdx.graphics.g2d.freetype.FreeTypeFontGenerator
import com.badlogic.gdx.graphics.g2d.freetype.FreeTypeFontGenerator.FreeTypeFontParameter
import com.badlogic.gdx.math.MathUtils
import com.badlogic.gdx.utils.Disposable
import dev.copt.penguinslide.Tuning
import dev.copt.penguinslide.render.FxTextures

/**
 * Heads-up display — pure presentation, ported from the iOS `HUDController`. Reads no game
 * state; [GameScreen] pushes updates via setScore/setBest/setHealth/showCombo/floatBonus.
 *
 * Drawn in a stationary HUD space (the caller binds a non-shaking projection), so the
 * score/hearts don't jitter with the camera shake.
 */
class Hud(private val worldW: Float, private val worldH: Float, private val fx: FxTextures) : Disposable {

    private val generator = FreeTypeFontGenerator(Gdx.files.internal("fonts/game.ttf"))
    private val scoreFont = font(56, Color.WHITE)
    private val bestFont = font(18, Color(0.8f, 0.85f, 0.9f, 1f))
    private val comboFont = font(28, GOLD)
    private val bonusFont = font(24, GOLD)
    private val titleFont = font(44, Color.WHITE)
    private val promptFont = font(22, Color(0.95f, 0.97f, 1f, 1f))
    private val layout = GlyphLayout()

    private var score = 0
    private var best = 0
    private var hp = Tuning.penguin.maxHealth

    private var comboVisible = false
    private var comboValue = 0
    private var comboPulse = 1f

    private var deathFlash = 0f
    private var startPrompt = false
    private var promptTime = 0f

    private class Bonus(val text: String, val x: Float, val y0: Float) { var age = 0f }
    private val bonuses = ArrayList<Bonus>()

    init { generator.dispose() } // fonts are generated; the generator is no longer needed

    // ---- push API ----

    fun setScore(value: Int) { score = value }
    fun setBest(value: Int) { best = value }
    fun setHealth(value: Int) { hp = value }

    fun showCombo(combo: Int) { comboVisible = true; comboValue = combo; comboPulse = 1.3f }
    fun hideCombo() { comboVisible = false }

    fun floatBonus(amount: Int, x: Float, y: Float) { bonuses.add(Bonus("+$amount", x, y)) }

    fun triggerDeathFlash() { deathFlash = 0.6f }

    fun showStartPrompt() { startPrompt = true }
    fun dismissStartPrompt() { startPrompt = false }

    // ---- update + render ----

    fun update(dt: Float) {
        if (deathFlash > 0f) deathFlash = (deathFlash - dt / 0.35f * 0.6f).coerceAtLeast(0f)
        if (comboPulse > 1f) comboPulse = (comboPulse - dt * 2.5f).coerceAtLeast(1f)
        promptTime += dt
        val it = bonuses.iterator()
        while (it.hasNext()) { val b = it.next(); b.age += dt; if (b.age >= 0.7f) it.remove() }
    }

    fun render(batch: SpriteBatch) {
        // Hearts (top-left): filled = red, empty = dim gray.
        val maxHp = Tuning.penguin.maxHealth
        for (i in 0 until maxHp) {
            if (i < hp) batch.setColor(0.95f, 0.25f, 0.3f, 1f) else batch.setColor(0.4f, 0.4f, 0.45f, 0.6f)
            val s = 30f
            batch.draw(fx.heart, 24f + i * 38f, worldH - 56f, s, s)
        }
        batch.setColor(Color.WHITE)

        drawCentered(batch, scoreFont, score.toString(), worldW / 2f, worldH - 54f)
        drawCentered(batch, bestFont, "Best  $best", worldW / 2f, worldH - 108f)

        if (comboVisible && comboValue >= 2) {
            comboFont.data.setScale(comboPulse)
            drawCentered(batch, comboFont, "COMBO x$comboValue", worldW / 2f, worldH - 132f)
            comboFont.data.setScale(1f)
        }

        for (b in bonuses) {
            val y = b.y0 + 60f * (b.age / 0.7f)
            val a = if (b.age < 0.35f) 1f else (1f - (b.age - 0.35f) / 0.35f).coerceIn(0f, 1f)
            bonusFont.color = Color(GOLD.r, GOLD.g, GOLD.b, a)
            drawCentered(batch, bonusFont, b.text, b.x, y)
        }
        bonusFont.color = GOLD

        if (startPrompt) {
            drawCentered(batch, titleFont, "ICY PENGUIN SLIDE", worldW / 2f, worldH * 0.62f)
            val pulse = 0.6f + 0.4f * (0.5f + 0.5f * MathUtils.sin(promptTime * 3f))
            promptFont.color = Color(0.95f, 0.97f, 1f, pulse)
            drawCentered(batch, promptFont, "Tap / Space to start", worldW / 2f, worldH * 0.42f)
            promptFont.color = Color(0.95f, 0.97f, 1f, 1f)
        }

        if (deathFlash > 0f) {
            batch.setColor(1f, 1f, 1f, deathFlash)
            batch.draw(fx.white, 0f, 0f, worldW, worldH)
            batch.setColor(Color.WHITE)
        }
    }

    private fun drawCentered(batch: SpriteBatch, font: BitmapFont, text: String, cx: Float, topY: Float) {
        layout.setText(font, text)
        font.draw(batch, layout, cx - layout.width / 2f, topY)
    }

    private fun font(size: Int, color: Color): BitmapFont {
        val param = FreeTypeFontParameter().apply {
            this.size = size
            this.color = color
            borderWidth = 1.5f
            borderColor = Color(0f, 0f, 0f, 0.5f)
        }
        return generator.generateFont(param)
    }

    override fun dispose() {
        scoreFont.dispose(); bestFont.dispose(); comboFont.dispose()
        bonusFont.dispose(); titleFont.dispose(); promptFont.dispose()
    }

    companion object {
        private val GOLD = Color(1f, 0.84f, 0.3f, 1f)
    }
}
