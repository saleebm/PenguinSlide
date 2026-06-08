package dev.copt.penguinslide.ui

import com.badlogic.gdx.Gdx
import com.badlogic.gdx.graphics.Color
import com.badlogic.gdx.graphics.g2d.BitmapFont
import com.badlogic.gdx.graphics.g2d.GlyphLayout
import com.badlogic.gdx.graphics.g2d.NinePatch
import com.badlogic.gdx.graphics.g2d.SpriteBatch
import com.badlogic.gdx.graphics.g2d.freetype.FreeTypeFontGenerator
import com.badlogic.gdx.graphics.g2d.freetype.FreeTypeFontGenerator.FreeTypeFontParameter
import com.badlogic.gdx.math.MathUtils
import com.badlogic.gdx.math.Rectangle
import com.badlogic.gdx.utils.Disposable
import dev.copt.penguinslide.data.HighScore
import dev.copt.penguinslide.render.FxTextures

/**
 * Lightweight, immediate-mode overlays — game-over and settings — drawn with the batch and
 * the rounded Baloo 2 font (no Scene2D). Player name uses the native `Gdx.input.getTextInput`
 * dialog. Mirrors the SwiftUI `GameOverView` / `SettingsView` surfaces.
 *
 * Visual language: frosted rounded panels with a soft drop shadow, soft-shadow text (no hard
 * outline), and a calm icy palette so the UI sits with the painted backdrop rather than on
 * top of it. Layout rectangles are exposed for [GameScreen] hit-testing.
 */
class Overlays(private val worldW: Float, private val worldH: Float, private val fx: FxTextures) : Disposable {

    private val generator = FreeTypeFontGenerator(Gdx.files.internal("fonts/game.ttf"))
    private val titleFont = font(40)
    private val bigFont = font(60)
    private val buttonFont = font(22)
    private val bodyFont = font(21)
    private val smallFont = font(16)
    private val layout = GlyphLayout()

    private val panelPatch = NinePatch(fx.roundedLarge, 24, 24, 24, 24)
    private val buttonPatch = NinePatch(fx.roundedSmall, 15, 15, 15, 15)

    init { generator.dispose() }

    // ---- shared button bounds ----

    val settingsButton = Rectangle(worldW - 120f, worldH - 46f, 104f, 34f)

    private val goPanel = Rectangle(worldW / 2f - 250f, worldH / 2f - 150f, 500f, 300f)
    val playAgainButton = Rectangle(goPanel.x + goPanel.width / 2f + 14f, goPanel.y + 26f, 176f, 50f)
    val saveButton = Rectangle(goPanel.x + goPanel.width / 2f - 190f, goPanel.y + 26f, 176f, 50f)

    private val sePanel = Rectangle(worldW / 2f - 235f, worldH / 2f - 155f, 470f, 310f)
    val sliderTrack = Rectangle(sePanel.x + 44f, sePanel.y + sePanel.height - 118f, sePanel.width - 88f, 12f)
    val changeNameButton = Rectangle(sePanel.x + 44f, sePanel.y + 96f, 184f, 44f)
    val resetButton = Rectangle(sePanel.x + sePanel.width - 228f, sePanel.y + 96f, 184f, 44f)
    val closeButton = Rectangle(sePanel.x + sePanel.width / 2f - 92f, sePanel.y + 30f, 184f, 48f)

    // ---- render ----

    fun renderGameOver(batch: SpriteBatch, score: Int, isNewBest: Boolean, leaderboard: List<HighScore>) {
        scrim(batch)
        panel(batch, goPanel)

        val cx = goPanel.x + goPanel.width / 2f
        titleFont.color = if (isNewBest) AMBER else CREAM
        drawCentered(batch, titleFont, if (isNewBest) "New Best!" else "Game Over", cx, goPanel.y + goPanel.height - 22f)
        bigFont.color = CREAM
        drawCentered(batch, bigFont, score.toString(), cx, goPanel.y + goPanel.height - 74f)

        smallFont.color = MUTED
        var ly = goPanel.y + goPanel.height - 150f
        if (leaderboard.isEmpty()) {
            drawCentered(batch, smallFont, "No runs saved yet", cx, ly)
        } else {
            leaderboard.take(5).forEachIndexed { i, e ->
                drawCentered(batch, smallFont, "${i + 1}.  ${e.name.ifBlank { "Anonymous" }}  ·  ${e.score}", cx, ly)
                ly -= 22f
            }
        }

        button(batch, saveButton, "Save Score", BLUE)
        button(batch, playAgainButton, "Play Again", GREEN)
    }

    fun renderSettings(batch: SpriteBatch, tiltIntensity: Float, playerName: String, version: String) {
        scrim(batch)
        panel(batch, sePanel)
        val cx = sePanel.x + sePanel.width / 2f

        titleFont.color = CREAM
        drawCentered(batch, titleFont, "Settings", cx, sePanel.y + sePanel.height - 22f)

        bodyFont.color = CREAM
        drawLeft(batch, bodyFont, "Tilt Response", sliderTrack.x, sliderTrack.y + 46f)

        // Track (rounded), filled portion (amber), knob (rounded).
        ninePatch(batch, buttonPatch, sliderTrack.x, sliderTrack.y, sliderTrack.width, sliderTrack.height, TRACK)
        ninePatch(batch, buttonPatch, sliderTrack.x, sliderTrack.y, sliderTrack.width * tiltIntensity, sliderTrack.height, AMBER)
        val knobX = sliderTrack.x + sliderTrack.width * tiltIntensity
        ninePatch(batch, buttonPatch, knobX - 9f, sliderTrack.y - 9f, 18f, 30f, CREAM)

        smallFont.color = MUTED
        drawLeft(batch, smallFont, "Calm", sliderTrack.x, sliderTrack.y - 18f)
        layout.setText(smallFont, "Wild")
        smallFont.draw(batch, "Wild", sliderTrack.x + sliderTrack.width - layout.width, sliderTrack.y - 18f)

        bodyFont.color = CREAM
        drawCentered(batch, bodyFont, "Player:  ${playerName.ifBlank { "Anonymous" }}", cx, sePanel.y + 166f)

        button(batch, changeNameButton, "Change Name", BLUE)
        button(batch, resetButton, "Reset Tilt", SLATE)
        button(batch, closeButton, "Close", GREEN)

        smallFont.color = FAINT
        drawCentered(batch, smallFont, "v$version", cx, sePanel.y + 24f)
    }

    fun renderSettingsButton(batch: SpriteBatch) {
        button(batch, settingsButton, "Settings", SLATE)
    }

    fun sliderValueFor(touchX: Float): Float =
        ((touchX - sliderTrack.x) / sliderTrack.width).coerceIn(0f, 1f)

    // ---- drawing helpers ----

    private fun scrim(batch: SpriteBatch) {
        batch.setColor(0.04f, 0.07f, 0.13f, 0.58f)
        batch.draw(fx.white, 0f, 0f, worldW, worldH)
        batch.setColor(Color.WHITE)
    }

    private fun panel(batch: SpriteBatch, r: Rectangle) {
        // Soft drop shadow.
        ninePatch(batch, panelPatch, r.x - 6f, r.y - 12f, r.width + 12f, r.height + 12f, SHADOW)
        // Frosted body.
        ninePatch(batch, panelPatch, r.x, r.y, r.width, r.height, PANEL)
        // Subtle top highlight.
        ninePatch(batch, panelPatch, r.x + 10f, r.y + r.height - 14f, r.width - 20f, 8f, HIGHLIGHT)
    }

    private fun button(batch: SpriteBatch, r: Rectangle, label: String, color: Color) {
        ninePatch(batch, buttonPatch, r.x + 2f, r.y - 3f, r.width, r.height, SHADOW) // shadow
        ninePatch(batch, buttonPatch, r.x, r.y, r.width, r.height, color)
        buttonFont.color = CREAM
        layout.setText(buttonFont, label)
        buttonFont.draw(batch, layout, r.x + (r.width - layout.width) / 2f, r.y + (r.height + layout.height) / 2f)
    }

    private fun ninePatch(batch: SpriteBatch, np: NinePatch, x: Float, y: Float, w: Float, h: Float, color: Color) {
        np.color = color
        np.draw(batch, x, y, w, h)
        batch.setColor(Color.WHITE)
    }

    private fun drawCentered(batch: SpriteBatch, font: BitmapFont, text: String, cx: Float, topY: Float) {
        layout.setText(font, text)
        font.draw(batch, layout, cx - layout.width / 2f, topY)
    }

    private fun drawLeft(batch: SpriteBatch, font: BitmapFont, text: String, x: Float, topY: Float) {
        font.draw(batch, text, x, topY)
    }

    private fun font(size: Int): BitmapFont {
        val param = FreeTypeFontParameter().apply {
            this.size = size
            color = Color.WHITE
            shadowOffsetX = 0
            shadowOffsetY = maxOf(2, size / 18)
            shadowColor = Color(0.04f, 0.08f, 0.16f, 0.5f)
        }
        return generator.generateFont(param)
    }

    override fun dispose() {
        titleFont.dispose(); bigFont.dispose(); buttonFont.dispose(); bodyFont.dispose(); smallFont.dispose()
    }

    companion object {
        private val CREAM = Color(0.98f, 0.98f, 0.96f, 1f)
        private val AMBER = Color(1f, 0.80f, 0.40f, 1f)
        private val MUTED = Color(0.80f, 0.86f, 0.93f, 0.92f)
        private val FAINT = Color(0.66f, 0.72f, 0.80f, 0.85f)
        private val PANEL = Color(0.11f, 0.17f, 0.28f, 0.94f)
        private val HIGHLIGHT = Color(1f, 1f, 1f, 0.06f)
        private val SHADOW = Color(0f, 0f, 0f, 0.30f)
        private val TRACK = Color(0.28f, 0.34f, 0.44f, 1f)
        private val BLUE = Color(0.30f, 0.56f, 0.86f, 1f)
        private val GREEN = Color(0.30f, 0.68f, 0.52f, 1f)
        private val SLATE = Color(0.34f, 0.40f, 0.50f, 1f)
    }
}
