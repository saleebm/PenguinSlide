package dev.copt.penguinslide.render

import com.badlogic.gdx.Gdx
import com.badlogic.gdx.graphics.Texture
import com.badlogic.gdx.graphics.g2d.TextureRegion
import com.badlogic.gdx.utils.Disposable

/**
 * Every art asset, keyed by [Sprite]. Source PNGs live under `assets/sprites/`.
 *
 * Port of the iOS `SpriteCatalog`: the single entry point for textures, with
 * nearest-neighbour filtering for crisp pixel art, lazy caching, a [tiled] helper for
 * the ice field, and [frames] to slice the SpriteCook horizontal spritesheets.
 */
enum class Sprite(val path: String) {
    SKY("sprites/sky.png"),
    ICE_TILE("sprites/icetile.png"),
    PENGUIN("sprites/penguin.png"),
    PENGUIN_IDLE("sprites/penguin_idle.png"),
    PENGUIN_SLIDE("sprites/penguin_slide.png"),
    PENGUIN_HURT("sprites/penguin_hurt.png"),
    PENGUIN_VICTORY("sprites/penguin_victory.png"),
    ICICLE("sprites/icicle.png"),
    ICICLE_SHATTER("sprites/icicle_shatter.png"),
}

class SpriteCatalog : Disposable {

    private val textures = HashMap<Sprite, Texture>()

    /** Lazily load + cache a texture with nearest-neighbour filtering (crisp pixel art). */
    fun texture(sprite: Sprite): Texture = textures.getOrPut(sprite) {
        Texture(Gdx.files.internal(sprite.path)).apply {
            setFilter(Texture.TextureFilter.Nearest, Texture.TextureFilter.Nearest)
        }
    }

    /** Whole-image region for single sprites. */
    fun region(sprite: Sprite): TextureRegion = TextureRegion(texture(sprite))

    /**
     * Slice a horizontal spritesheet into [count] equal-width frames.
     * Mirrors `SpriteCatalog.slicedFrames` — frames share the source atlas memory.
     */
    fun frames(sprite: Sprite, count: Int): Array<TextureRegion> {
        val tex = texture(sprite)
        val fw = tex.width / count
        val fh = tex.height
        return Array(count) { i -> TextureRegion(tex, i * fw, 0, fw, fh) }
    }

    /**
     * A region that repeats the sprite to cover [widthPx] x [heightPx] — used to tile the
     * ice field. Relies on GL texture-wrap REPEAT (source tiles are power-of-two-friendly).
     */
    fun tiled(sprite: Sprite, widthPx: Int, heightPx: Int): TextureRegion {
        val tex = texture(sprite)
        tex.setWrap(Texture.TextureWrap.Repeat, Texture.TextureWrap.Repeat)
        return TextureRegion(tex, 0, 0, widthPx, heightPx)
    }

    /** Warm the cache so the first gameplay frame doesn't stutter on texture upload. */
    fun preload() = Sprite.entries.forEach { texture(it) }

    override fun dispose() {
        textures.values.forEach(Texture::dispose)
        textures.clear()
    }
}
