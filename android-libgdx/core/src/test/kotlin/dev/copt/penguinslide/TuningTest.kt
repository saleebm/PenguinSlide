package dev.copt.penguinslide

import dev.copt.penguinslide.data.HighScore
import dev.copt.penguinslide.data.HighScores
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

private const val EPS = 1e-4f

class PenguinTuningTest {

    @Test
    fun `fresh tuning seeds the derived trio from the default intensity, not raw defaults`() {
        val t = PenguinTuning()
        assertEquals(0.25f, t.tiltIntensity, EPS)
        assertEquals(1125f, t.maxSpeed, EPS)          // 850 + 0.25*1100
        assertEquals(4.5f, t.tiltResponseRate, EPS)   // 4 + 0.25*2  (NOT the raw 5.0 default)
        assertEquals(1.45f, t.tiltCurve, EPS)         // 1.5 - 0.25*0.2 (NOT the raw 1.5)
    }

    @Test
    fun `derived endpoints match the Swift formula`() {
        val (s0, r0, c0) = PenguinTuning.derived(0f)
        assertEquals(850f, s0, EPS); assertEquals(4f, r0, EPS); assertEquals(1.5f, c0, EPS)

        val (s1, r1, c1) = PenguinTuning.derived(1f)
        assertEquals(1950f, s1, EPS); assertEquals(6f, r1, EPS); assertEquals(1.3f, c1, EPS)

        val (sHalf, rHalf, cHalf) = PenguinTuning.derived(0.5f)
        assertEquals(1400f, sHalf, EPS); assertEquals(5f, rHalf, EPS); assertEquals(1.4f, cHalf, EPS)
    }

    @Test
    fun `applyTiltIntensity clamps out-of-range input`() {
        val t = PenguinTuning()
        t.applyTiltIntensity(2f)
        assertEquals(1f, t.tiltIntensity, EPS)
        assertEquals(1950f, t.maxSpeed, EPS)
        t.applyTiltIntensity(-3f)
        assertEquals(0f, t.tiltIntensity, EPS)
        assertEquals(850f, t.maxSpeed, EPS)
    }
}

class ScoringTest {

    @Test
    fun `survival score truncates toward zero`() {
        assertEquals(25, Scoring.survivalScore(2.5f))
        assertEquals(0, Scoring.survivalScore(0.09f))
        assertEquals(901, Scoring.survivalScore(90.15f))
    }

    @Test
    fun `close-call bonus scales by severity and combo`() {
        assertEquals(50, Scoring.closeCallBonus(severity = 1.0f, combo = 1))   // 50*1*1
        assertEquals(25, Scoring.closeCallBonus(severity = 0.5f, combo = 1))   // 50*0.5*1
        assertEquals(250, Scoring.closeCallBonus(severity = 1.0f, combo = 5))  // 50*1*5
        assertEquals(65, Scoring.closeCallBonus(severity = 0.65f, combo = 2))  // round(50*0.65*2)
    }

    @Test
    fun `combo multiplier is capped at five`() {
        // combo 7 must score the same as combo 5 (cap = comboMaxMultiplier).
        assertEquals(
            Scoring.closeCallBonus(severity = 1.0f, combo = 5),
            Scoring.closeCallBonus(severity = 1.0f, combo = 7),
        )
    }
}

class HighScoresTest {

    private fun entry(score: Int, date: Long, name: String = "P") =
        HighScore(name = name, score = score, date = date, id = "$name-$score-$date")

    @Test
    fun `board is best-first and capped at five`() {
        var board = emptyList<HighScore>()
        listOf(10, 50, 30, 90, 20, 70, 5).forEachIndexed { i, s ->
            board = HighScores.insert(board, entry(s, date = i.toLong()))
        }
        assertEquals(5, board.size)
        assertEquals(listOf(90, 70, 50, 30, 20), board.map { it.score })
    }

    @Test
    fun `score ties break toward the earlier date`() {
        var board = emptyList<HighScore>()
        board = HighScores.insert(board, entry(50, date = 200, name = "late"))
        board = HighScores.insert(board, entry(50, date = 100, name = "early"))
        assertEquals(listOf("early", "late"), board.map { it.name })
    }

    @Test
    fun `qualifies respects positivity, open slots, and the lowest entry`() {
        assertFalse(HighScores.qualifies(emptyList(), 0))
        assertTrue(HighScores.qualifies(emptyList(), 1))

        val full = (1..5).map { entry(it * 10, date = it.toLong()) } // lowest = 10
        assertTrue(HighScores.qualifies(full, 11))
        assertFalse(HighScores.qualifies(full, 10))  // must strictly beat the lowest
        assertFalse(HighScores.qualifies(full, 5))
    }
}
