package dev.copt.penguinslide.data

import com.badlogic.gdx.Gdx
import com.badlogic.gdx.Preferences
import com.badlogic.gdx.utils.Json
import com.badlogic.gdx.utils.JsonReader
import dev.copt.penguinslide.PenguinTuning

/**
 * On-device persistence over libGDX [Preferences] — the Android/desktop analogue of the
 * iOS `UserDefaults` usage. No accounts, no network.
 *
 * Keys mirror the iOS app so intent is obvious: `best_score`, `playerName`,
 * `highScores` (a JSON list), plus `tiltIntensity` (the one persisted feel knob — the rest
 * of [PenguinTuning] is derived/fixed, so we store only the slider value, exactly the
 * user-tunable surface the iOS Settings screen exposed).
 */
object Persistence {
    private const val PREFS = "penguinslide"
    private const val KEY_BEST = "best_score"
    private const val KEY_NAME = "playerName"
    private const val KEY_TILT = "tiltIntensity"
    private const val KEY_HIGH = "highScores"

    private val prefs: Preferences get() = Gdx.app.getPreferences(PREFS)
    private val json = Json()

    fun bestScore(): Int = prefs.getInteger(KEY_BEST, 0)

    fun setBestScore(value: Int) {
        prefs.putInteger(KEY_BEST, value)
        prefs.flush()
    }

    fun playerName(): String = prefs.getString(KEY_NAME, "")

    fun setPlayerName(name: String) {
        prefs.putString(KEY_NAME, name.trim())
        prefs.flush()
    }

    fun loadPenguinTuning(): PenguinTuning =
        PenguinTuning().also {
            it.applyTiltIntensity(prefs.getFloat(KEY_TILT, PenguinTuning.tiltIntensityDefault))
        }

    fun savePenguinTuning(tuning: PenguinTuning) {
        prefs.putFloat(KEY_TILT, tuning.tiltIntensity)
        prefs.flush()
    }

    fun highScores(): List<HighScore> {
        val raw = prefs.getString(KEY_HIGH, "")
        if (raw.isBlank()) return emptyList()
        return try {
            val root = JsonReader().parse(raw)
            buildList {
                root.forEach { node ->
                    add(
                        HighScore(
                            name = node.getString("name", ""),
                            score = node.getInt("score", 0),
                            date = node.getLong("date", 0L),
                            id = node.getString("id", ""),
                        )
                    )
                }
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /** Add a run to the board (best-first, capped) and persist. Returns the new board. */
    fun addHighScore(entry: HighScore): List<HighScore> {
        val updated = HighScores.insert(highScores(), entry)
        prefs.putString(KEY_HIGH, json.toJson(updated.toTypedArray(), Array<HighScore>::class.java))
        prefs.flush()
        return updated
    }
}
