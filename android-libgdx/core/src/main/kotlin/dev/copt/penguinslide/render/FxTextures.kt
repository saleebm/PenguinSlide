package dev.copt.penguinslide.render

import com.badlogic.gdx.graphics.Color
import com.badlogic.gdx.graphics.Pixmap
import com.badlogic.gdx.graphics.Texture
import com.badlogic.gdx.utils.Disposable

/**
 * Small procedurally-generated textures for impact FX — the libGDX analogue of the iOS
 * `UIGraphicsImageRenderer` caches in `IcicleSystem` (puff dot, under-icicle shadow,
 * shatter shard). Built once via [Pixmap], reused for every particle.
 */
class FxTextures : Disposable {

    /** White dot for snow puffs. */
    val dot: Texture = circlePixmap(16, 1f, 1f, 1f, 1f)

    /** Solid 4x4 white, stretched for the death flash and other full-screen fills. */
    val white: Texture = run {
        val pm = Pixmap(4, 4, Pixmap.Format.RGBA8888)
        pm.setColor(Color.WHITE)
        pm.fill()
        Texture(pm).also { pm.dispose() }
    }

    /** White rounded-rect bases for ninepatch panels (large radius) and buttons (small). */
    val roundedLarge: Texture = roundedSquare(72, 24)
    val roundedSmall: Texture = roundedSquare(44, 15)

    /** White heart (tinted red/gray at draw time) for the HUD hearts. */
    val heart: Texture = run {
        val s = 32
        val pm = Pixmap(s, s, Pixmap.Format.RGBA8888)
        pm.setColor(Color.WHITE)
        pm.fillCircle(10, 12, 8)
        pm.fillCircle(22, 12, 8)
        pm.fillTriangle(2, 15, 30, 15, 16, 30)
        Texture(pm).also { it.setFilter(Texture.TextureFilter.Linear, Texture.TextureFilter.Linear); pm.dispose() }
    }

    /** Soft dark ellipse for the under-icicle shadow (drawn stretched). */
    val shadow: Texture = run {
        val w = 64; val h = 18
        val pm = Pixmap(w, h, Pixmap.Format.RGBA8888)
        pm.setColor(0f, 0f, 0f, 0.45f)
        pm.fillCircle(w / 2, h / 2, h / 2)          // base soft blob
        pm.setColor(0f, 0f, 0f, 0.55f)
        pm.fillCircle(w / 2, h / 2, (h / 2) - 4)    // denser core
        Texture(pm).also { it.setFilter(Texture.TextureFilter.Linear, Texture.TextureFilter.Linear); pm.dispose() }
    }

    /** Icy-blue triangular chip for shatter shards. */
    val shard: Texture = run {
        val s = 8
        val pm = Pixmap(s, s, Pixmap.Format.RGBA8888)
        pm.setColor(0.78f, 0.92f, 1f, 1f)
        pm.fillTriangle(s / 2, 0, s - 1, s - 1, 0, s - 1)
        Texture(pm).also { it.setFilter(Texture.TextureFilter.Linear, Texture.TextureFilter.Linear); pm.dispose() }
    }

    /** A white rounded square, supersampled 4x then downscaled for anti-aliased corners. */
    private fun roundedSquare(size: Int, radius: Int): Texture {
        val ss = 4
        val w = size * ss; val h = size * ss; val r = radius * ss
        val big = Pixmap(w, h, Pixmap.Format.RGBA8888)
        big.setColor(Color.WHITE)
        big.fillRectangle(r, 0, w - 2 * r, h)
        big.fillRectangle(0, r, w, h - 2 * r)
        big.fillCircle(r, r, r)
        big.fillCircle(w - 1 - r, r, r)
        big.fillCircle(r, h - 1 - r, r)
        big.fillCircle(w - 1 - r, h - 1 - r, r)
        val small = Pixmap(size, size, Pixmap.Format.RGBA8888)
        small.filter = Pixmap.Filter.BiLinear
        small.drawPixmap(big, 0, 0, w, h, 0, 0, size, size)
        big.dispose()
        return Texture(small).also {
            it.setFilter(Texture.TextureFilter.Linear, Texture.TextureFilter.Linear)
            small.dispose()
        }
    }

    private fun circlePixmap(size: Int, r: Float, g: Float, b: Float, a: Float): Texture {
        val pm = Pixmap(size, size, Pixmap.Format.RGBA8888)
        pm.setColor(r, g, b, a)
        pm.fillCircle(size / 2, size / 2, size / 2)
        return Texture(pm).also {
            it.setFilter(Texture.TextureFilter.Linear, Texture.TextureFilter.Linear)
            pm.dispose()
        }
    }

    override fun dispose() {
        dot.dispose(); shadow.dispose(); shard.dispose(); white.dispose(); heart.dispose()
        roundedLarge.dispose(); roundedSmall.dispose()
    }
}
