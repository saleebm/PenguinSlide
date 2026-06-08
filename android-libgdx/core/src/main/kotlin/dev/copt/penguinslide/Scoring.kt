package dev.copt.penguinslide

import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Pure scoring math — extracted so it can be unit-tested headlessly (no `Gdx`).
 * Mirrors `GameScene.update`'s score line and `registerCloseCall`.
 */
object Scoring {

    /** Passive survival points: `floor(elapsed * survivalRate)`, truncating like Swift `Int(...)`. */
    fun survivalScore(elapsedSeconds: Float): Int =
        (elapsedSeconds * Tuning.Score.survivalRate).toInt()

    /**
     * Close-call bonus for a survived landing: `round(base * severity * min(combo, cap))`.
     * `combo` is the streak count (1-based on the dodge being scored).
     */
    fun closeCallBonus(severity: Float, combo: Int): Int {
        val multiplier = min(combo.toFloat(), Tuning.Score.comboMaxMultiplier)
        return (Tuning.Score.closeCallBase * severity * multiplier).roundToInt()
    }
}
