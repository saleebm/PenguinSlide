package dev.copt.penguinslide.data

/** One leaderboard entry. `date` is epoch millis (ties break toward the earliest run). */
data class HighScore(
    var name: String = "",
    var score: Int = 0,
    var date: Long = 0L,
    var id: String = "",
)

/**
 * Pure leaderboard logic — board is best-first, capped at [MAX], ties broken by earliest
 * date. Mirrors the iOS `HighScores` rules. Kept free of `Gdx` so it's unit-testable; the
 * persistence/serialisation side lives in [dev.copt.penguinslide.data.Persistence].
 */
object HighScores {
    const val MAX = 5

    /** Insert an entry and return the trimmed, sorted board. */
    fun insert(existing: List<HighScore>, entry: HighScore): List<HighScore> =
        (existing + entry)
            .sortedWith(compareByDescending<HighScore> { it.score }.thenBy { it.date })
            .take(MAX)

    /** A score qualifies if positive AND (board has room OR it beats the current lowest). */
    fun qualifies(existing: List<HighScore>, score: Int): Boolean =
        score > 0 && (existing.size < MAX || score > (existing.minOfOrNull { it.score } ?: 0))
}
