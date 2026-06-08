package dev.copt.penguinslide.ui

import com.badlogic.gdx.Gdx
import com.badlogic.gdx.graphics.Color
import com.badlogic.gdx.graphics.g2d.BitmapFont
import com.badlogic.gdx.graphics.g2d.GlyphLayout
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
 * FreeType fonts (no Scene2D). Player name uses the native `Gdx.input.getTextInput` dialog.
 * Mirrors the SwiftUI `GameOverView` / `SettingsView` surfaces.
 *
 * Layout rectangles are exposed so [GameScreen] can hit-test taps against them.
 */
class Overlays(private val worldW: Float, private val worldH: Float, private val fx: FxTextures) : Disposable {

    private val generator = FreeTypeFontGenerator(Gdx.files.internal("fonts/game.ttf"))
    private val titleFont = font(40)
    private val bigFont = font(56)
    private val buttonFont = font(22)
    private val bodyFont = font(20)
    private val smallFont = font(15)
    private val layout = GlyphLayout()

    init { generator.dispose() }

    // ---- shared button bounds ----

    /** "Settings" button, top-right (shown on TITLE/PLAYING). */
    val settingsButton = Rectangle(worldW - 116f, worldH - 44f, 100f, 32f)

    // Game-over panel + buttons.
    private val goPanel = Rectangle(worldW / 2f - 250f, worldH / 2f - 150f, 500f, 300f)
    val playAgainButton = Rectangle(goPanel.x + goPanel.width / 2f + 12f, goPanel.y + 22f, 180f, 46f)
    val saveButton = Rectangle(goPanel.x + goPanel.width / 2f - 192f, goPanel.y + 22f, 180f, 46f)

    // Settings panel + controls.
    private val sePanel = Rectangle(worldW / 2f - 230f, worldH / 2f - 150f, 460f, 300f)
    val sliderTrack = Rectangle(sePanel.x + 40f, sePanel.y + sePanel.height - 110f, sePanel.width - 80f, 10f)
    val changeNameButton = Rectangle(sePanel.x + 40f, sePanel.y + 100f, 180f, 42f)
    val resetButton = Rectangle(sePanel.x + sePanel.width - 220f, sePanel.y + 100f, 180f, 42f)
    val closeButton = Rectangle(sePanel.x + sePanel.width / 2f - 90f, sePanel.y + 30f, 180f, 46f)

    // ---- render ----

    fun renderGameOver(batch: SpriteBatch, score: Int, isNewBest: Boolean, leaderboard: List<HighScore>) {
        scrim(batch)
        panel(batch, goPanel)

        val cx = goPanel.x + goPanel.width / 2f
        titleFont.color = if (isNewBest) GOLD else Color.WHITE
        drawCentered(batch, titleFont, if (isNewBest) "NEW BEST!" else "GAME OVER", cx, goPanel.y + goPanel.height - 18f)
        bigFont.color = Color.WHITE
        drawCentered(batch, bigFont, score.toString(), cx, goPanel.y + goPanel.height - 70f)

        // Leaderboard (top 5).
        smallFont.color = Color(0.85f, 0.9f, 0.95f, 1f)
        var ly = goPanel.y + goPanel.height - 140f
        if (leaderboard.isEmpty()) {
            drawCentered(batch, smallFont, "No high scores yet", cx, ly)
        } else {
            leaderboard.take(5).forEachIndexed { i, e ->
                val name = e.name.ifBlank { "Anonymous" }
                drawCentered(batch, smallFont, "${i + 1}.  $name  —  ${e.score}", cx, ly)
                ly -= 22f
            }
        }

        button(batch, saveButton, "Save Score")
        button(batch, playAgainButton, "Play Again")
    }

    fun renderSettings(batch: SpriteBatch, tiltIntensity: Float, playerName: String, version: String) {
        scrim(batch)
        panel(batch, sePanel)
        val cx = sePanel.x + sePanel.width / 2f

        titleFont.color = Color.WHITE
        drawCentered(batch, titleFont, "Settings", cx, sePanel.y + sePanel.height - 18f)

        bodyFont.color = Color.WHITE
        drawLeft(batch, bodyFont, "Tilt Response", sliderTrack.x, sliderTrack.y + 44f)
        // Track + filled portion + knob.
        batch.setColor(0.3f, 0.35f, 0.42f, 1f)
        batch.draw(fx.white, sliderTrack.x, sliderTrack.y, sliderTrack.width, sliderTrack.height)
        batch.setColor(GOLD)
        batch.draw(fx.white, sliderTrack.x, sliderTrack.y, sliderTrack.width * tiltIntensity, sliderTrack.height)
        val knobX = sliderTrack.x + sliderTrack.width * tiltIntensity
        batch.setColor(Color.WHITE)
        batch.draw(fx.white, knobX - 7f, sliderTrack.y - 9f, 14f, 28f)
        smallFont.color = Color(0.8f, 0.85f, 0.9f, 1f)
        drawLeft(batch, smallFont, "Calm", sliderTrack.x, sliderTrack.y - 16f)
        val wild = "Wild"
        layout.setText(smallFont, wild)
        smallFont.draw(batch, wild, sliderTrack.x + sliderTrack.width - layout.width, sliderTrack.y - 16f)

        bodyFont.color = Color.WHITE
        drawCentered(batch, bodyFont, "Player: ${playerName.ifBlank { "Anonymous" }}", cx, sePanel.y + 168f)

        button(batch, changeNameButton, "Change Name")
        button(batch, resetButton, "Reset Tilt")
        button(batch, closeButton, "Close")

        smallFont.color = Color(0.7f, 0.75f, 0.8f, 1f)
        drawCentered(batch, smallFont, "v$version", cx, sePanel.y + 22f)
    }

    fun renderSettingsButton(batch: SpriteBatch) {
        button(batch, settingsButton, "Settings")
    }

    /** Slider value [0,1] for a touch x inside (or near) the track. */
    fun sliderValueFor(touchX: Float): Float =
        ((touchX - sliderTrack.x) / sliderTrack.width).coerceIn(0f, 1f)

    // ---- drawing helpers ----

    private fun scrim(batch: SpriteBatch) {
        batch.setColor(0f, 0f, 0f, 0.55f)
        batch.draw(fx.white, 0f, 0f, worldW, worldH)
        batch.setColor(Color.WHITE)
    }

    private fun panel(batch: SpriteBatch, r: Rectangle) {
        batch.setColor(0.12f, 0.18f, 0.27f, 0.96f)
        batch.draw(fx.white, r.x, r.y, r.width, r.height)
        // Top accent bar.
        batch.setColor(GOLD)
        batch.draw(fx.white, r.x, r.y + r.height - 5f, r.width, 5f)
        batch.setColor(Color.WHITE)
    }

    private fun button(batch: SpriteBatch, r: Rectangle, label: String) {
        batch.setColor(0.22f, 0.45f, 0.72f, 1f)
        batch.draw(fx.white, r.x, r.y, r.width, r.height)
        batch.setColor(Color.WHITE)
        buttonFont.color = Color.WHITE
        layout.setText(buttonFont, label)
        buttonFont.draw(batch, layout, r.x + (r.width - layout.width) / 2f, r.y + (r.height + layout.height) / 2f)
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
            borderWidth = 1.5f
            borderColor = Color(0f, 0f, 0f, 0.5f)
        }
        return generator.generateFont(param)
    }

    override fun dispose() {
        titleFont.dispose(); bigFont.dispose(); buttonFont.dispose(); bodyFont.dispose(); smallFont.dispose()
    }

    companion object {
        private val GOLD = Color(1f, 0.84f, 0.3f, 1f)
    }
}
