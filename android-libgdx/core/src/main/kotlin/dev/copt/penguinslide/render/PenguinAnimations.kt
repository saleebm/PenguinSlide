package dev.copt.penguinslide.render

import com.badlogic.gdx.graphics.g2d.Animation
import com.badlogic.gdx.graphics.g2d.TextureRegion
import com.badlogic.gdx.utils.Array as GdxArray

/** Penguin animation states — mirrors the iOS `PenguinAnimState`. */
enum class PenguinAnimState { IDLE, SLIDE, HURT, VICTORY }

/**
 * Slices the SpriteCook horizontal spritesheets into per-state [Animation]s.
 * Frame counts / fps / loop flags come from `spritecook-assets.json`:
 *   idle 12@8 loop · slide 8@8 loop · hurt 6@8 once · victory 10@8 once.
 */
class PenguinAnimations(catalog: SpriteCatalog) {

    val idle: Animation<TextureRegion> =
        build(catalog, Sprite.PENGUIN_IDLE, count = 12, fps = 8f, Animation.PlayMode.LOOP)
    val slide: Animation<TextureRegion> =
        build(catalog, Sprite.PENGUIN_SLIDE, count = 8, fps = 8f, Animation.PlayMode.LOOP)
    val hurt: Animation<TextureRegion> =
        build(catalog, Sprite.PENGUIN_HURT, count = 6, fps = 8f, Animation.PlayMode.NORMAL)
    val victory: Animation<TextureRegion> =
        build(catalog, Sprite.PENGUIN_VICTORY, count = 10, fps = 8f, Animation.PlayMode.NORMAL)

    fun forState(state: PenguinAnimState): Animation<TextureRegion> = when (state) {
        PenguinAnimState.IDLE -> idle
        PenguinAnimState.SLIDE -> slide
        PenguinAnimState.HURT -> hurt
        PenguinAnimState.VICTORY -> victory
    }

    private fun build(
        catalog: SpriteCatalog,
        sprite: Sprite,
        count: Int,
        fps: Float,
        mode: Animation.PlayMode,
    ): Animation<TextureRegion> {
        val frames = GdxArray<TextureRegion>(count)
        catalog.frames(sprite, count).forEach(frames::add)
        return Animation(1f / fps, frames).apply { playMode = mode }
    }
}

/**
 * The icicle shatter burst: 8 frames @ 14 fps, one-shot. Kept separate from the penguin
 * sheet (different fps), matching the iOS `IcicleAnimations`.
 */
class IcicleAnimations(catalog: SpriteCatalog) {
    val shatter: Animation<TextureRegion> = run {
        val frames = GdxArray<TextureRegion>(8)
        catalog.frames(Sprite.ICICLE_SHATTER, 8).forEach(frames::add)
        Animation(1f / 14f, frames).apply { playMode = Animation.PlayMode.NORMAL }
    }
}
