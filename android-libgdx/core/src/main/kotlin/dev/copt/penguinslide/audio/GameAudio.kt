package dev.copt.penguinslide.audio

import com.badlogic.gdx.Gdx
import com.badlogic.gdx.audio.Music
import com.badlogic.gdx.audio.Sound
import com.badlogic.gdx.utils.Disposable

/**
 * Audio wrapper — looping background [Music] plus one-shot [Sound]s, ported from the iOS
 * `SKAudioNode`/`playSoundFileNamed` usage. Per-play volume mirrors the iOS attenuation:
 * crack at 0.18-ish bed, landing shatter by distance, cry at 0.9 on damage.
 *
 * Source files are the OGGs converted from the iOS `.caf` assets (see
 * `scripts/convert-audio.sh`).
 */
class GameAudio : Disposable {

    private val music: Music = Gdx.audio.newMusic(Gdx.files.internal("audio/bg_music.ogg")).apply {
        isLooping = true
        volume = MUSIC_VOLUME
    }
    private val crack: Sound = sound("icicle_crack.ogg")
    private val shatter: Sound = sound("icicle_shatter.ogg")
    private val cry: Sound = sound("penguin_cry.ogg")
    private val gameOver: Sound = sound("game_over.ogg")

    private fun sound(name: String): Sound = Gdx.audio.newSound(Gdx.files.internal("audio/$name"))

    fun startMusic() = music.play()
    fun pauseMusic() = music.pause()
    fun resumeMusic() { if (!music.isPlaying) music.play() }

    /** Spawn telegraph crack (rate-limited by the spawn cadence itself). */
    fun playCrack() { crack.play(0.25f) }

    /** Landing shatter at a distance-attenuated [volume]. */
    fun playShatter(volume: Float) { shatter.play(volume.coerceIn(0f, 1f)) }

    /** Penguin yelp on a damaging hit (skipped on i-frame saves by the caller). */
    fun playCry() { cry.play(0.9f) }

    fun playGameOver() { gameOver.play() }

    override fun dispose() {
        music.dispose(); crack.dispose(); shatter.dispose(); cry.dispose(); gameOver.dispose()
    }

    companion object {
        private const val MUSIC_VOLUME = 0.18f
    }
}
