package dev.copt.penguinslide.systems

import com.badlogic.gdx.graphics.Color
import com.badlogic.gdx.graphics.g2d.SpriteBatch
import com.badlogic.gdx.math.Circle
import com.badlogic.gdx.math.Intersector
import com.badlogic.gdx.math.MathUtils
import com.badlogic.gdx.math.Rectangle
import dev.copt.penguinslide.Tuning
import dev.copt.penguinslide.audio.GameAudio
import dev.copt.penguinslide.entities.Penguin
import dev.copt.penguinslide.render.FxTextures
import dev.copt.penguinslide.render.IcicleAnimations
import dev.copt.penguinslide.render.Sprite
import dev.copt.penguinslide.render.SpriteCatalog
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sign
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Owns the icicle lifecycle: spawn cadence, warning telegraph, per-icicle gravity, landing
 * detection, shatter shards/bursts, under-icicle shadow, camera shake, and impact audio.
 * Faithful port of the iOS `IcicleSystem`, but with manual integration + timers replacing
 * SpriteKit's physics bodies and `SKAction` sequences (so update ordering is fully ours).
 *
 * Contact with the penguin is resolved here each frame via circle×rect overlap, replacing
 * SpriteKit's `didBegin`. The system holds a [penguin] reference for targeting/severity,
 * exactly as the Swift original did.
 */
class IcicleSystem(
    private val worldH: Float,
    private val iceLandingY: Float,
    private val iceLeftX: Float,
    private val iceRightX: Float,
    private val catalog: SpriteCatalog,
    private val icicleAnims: IcicleAnimations,
    private val fx: FxTextures,
    private val audio: GameAudio,
    private val penguin: Penguin,
) {
    /** (severity 0..1, landingX) for a *survived* close-call landing. GameScreen scores it. */
    var onCloseCall: ((Float, Float) -> Unit)? = null
    /** A damaging or absorbed penguin hit (accepted = HP lost). GameScreen resets combo. */
    var onPenguinHit: ((accepted: Boolean) -> Unit)? = null
    /** Request a camera shake of the given amplitude (GameScreen owns the camera). */
    var onShake: ((amplitude: Float) -> Unit)? = null

    private enum class State { WARNING, FALLING, DYING }

    private class Icicle(
        var x: Float,
        val spawnY: Float,
        val width: Float,
        val height: Float,
        val gravity: Float,
    ) {
        var y = spawnY
        var vy = 0f
        var vxRecoil = 0f        // horizontal recoil velocity, only used in DYING
        var rotation = 0f
        var angularVel = 0f
        var age = 0f
        var state = State.WARNING
        var tint = 0f            // 0..0.45 darkening during telegraph
        var alpha = 1f
        var scale = 1f
        var dieAge = 0f
    }

    private class Shard(
        var x: Float, var y: Float, var vx: Float, var vy: Float,
        val gravity: Float, var rotation: Float, val angularVel: Float, val scale: Float,
    ) {
        var age = 0f
    }

    private class Puff(var x: Float, var y: Float, val vx: Float, val vy: Float, val scale: Float) {
        var age = 0f
    }

    private class Burst(val x: Float, val y: Float, val size: Float) {
        var age = 0f
    }

    private val icicles = ArrayList<Icicle>()
    private val shards = ArrayList<Shard>()
    private val puffs = ArrayList<Puff>()
    private val bursts = ArrayList<Burst>()

    private var timeSinceLastSpawn = 0f
    private var nextSpawnInterval = Tuning.Icicle.spawnIntervalStart
    private var frozen = false

    // Scratch geometry for contact tests (avoid per-frame allocation).
    private val penguinCircle = Circle()
    private val icicleRect = Rectangle()

    // ---- lifecycle ----

    fun update(dt: Float, elapsed: Float) {
        if (frozen) return
        timeSinceLastSpawn += dt
        if (elapsed > Tuning.Run.gracePeriod && timeSinceLastSpawn >= nextSpawnInterval) {
            spawnIcicle(elapsed)
            timeSinceLastSpawn = 0f
            nextSpawnInterval = currentSpawnInterval(elapsed)
        }
        integrateAndCheckLandings(dt)
        checkPenguinContacts()
        integrateShardsAndBursts(dt)
    }

    /** Freeze on game over — equivalent to `physicsWorld.speed = 0` + `pauseShardActions`. */
    fun freeze() { frozen = true }

    fun reset() {
        icicles.clear(); shards.clear(); puffs.clear(); bursts.clear()
        timeSinceLastSpawn = 0f
        nextSpawnInterval = Tuning.Icicle.spawnIntervalStart
        frozen = false
    }

    // ---- difficulty curve ----

    private fun progress(elapsed: Float): Float =
        ((elapsed - Tuning.Run.gracePeriod) / Tuning.Run.rampDuration).coerceIn(0f, 1f)

    private fun currentSpawnInterval(elapsed: Float): Float {
        val p = progress(elapsed)
        return Tuning.Icicle.spawnIntervalStart +
            (Tuning.Icicle.spawnIntervalEnd - Tuning.Icicle.spawnIntervalStart) * p
    }

    private fun gravityScale(elapsed: Float): Float {
        val p = progress(elapsed)
        val mean = Tuning.Icicle.gravityScaleStart +
            (Tuning.Icicle.gravityScaleEnd - Tuning.Icicle.gravityScaleStart) * p
        val jitter = Tuning.Icicle.gravityScaleVariance
        return mean * MathUtils.random(1f - jitter, 1f + jitter)
    }

    private fun targetedSpawnX(halfW: Float, predictedFallTime: Float, elapsed: Float): Float {
        val minX = iceLeftX + halfW
        val maxX = iceRightX - halfW
        if (MathUtils.random() < Tuning.Chase.randomChance) return MathUtils.random(minX, maxX)

        val leadTime = Tuning.Icicle.warningDuration + predictedFallTime
        val predicted = penguin.x + penguin.vx * leadTime * Tuning.Chase.leadFactor
        val p = progress(elapsed)
        val jitterFrac = Tuning.Chase.jitterStart + (Tuning.Chase.jitterEnd - Tuning.Chase.jitterStart) * p
        val jitter = jitterFrac * (iceRightX - iceLeftX)
        val raw = predicted + MathUtils.random(-jitter, jitter)
        return MathUtils.clamp(raw, minX, maxX)
    }

    // ---- spawn ----

    private fun spawnIcicle(elapsed: Float) {
        val width = MathUtils.random(36f, 54f)
        val height = width * MathUtils.random(2.4f, 3.4f)
        val perIcicleGravity = Tuning.Icicle.sceneGravity * gravityScale(elapsed)
        val spawnY = worldH - height / 2f - 4f
        val h = spawnY - (iceLandingY + height / 2f)
        val v0 = Tuning.Icicle.initialDownVelocity
        val g = perIcicleGravity
        val predictedFallTime = if (h > 0f && g > 0f) (-v0 + sqrt(v0 * v0 + 2f * g * h)) / g else 0f
        val spawnX = targetedSpawnX(width / 2f, predictedFallTime, elapsed)

        icicles.add(Icicle(spawnX, spawnY, width, height, perIcicleGravity))
        audio.playCrack()
    }

    // ---- integration + landing ----

    private fun integrateAndCheckLandings(dt: Float) {
        val it = icicles.iterator()
        while (it.hasNext()) {
            val ic = it.next()
            ic.age += dt
            when (ic.state) {
                State.WARNING -> {
                    // Telegraph: darken toward 0.45, shake in place ~6 cycles over the window.
                    ic.tint = (ic.age / Tuning.Icicle.warningDuration).coerceIn(0f, 1f) * 0.45f
                    if (ic.age >= Tuning.Icicle.warningDuration) {
                        spawnPuff(ic.x, ic.y)
                        ic.state = State.FALLING
                        ic.vy = -Tuning.Icicle.initialDownVelocity
                        ic.tint = 0f
                    }
                }
                State.FALLING -> {
                    ic.vy -= ic.gravity * dt
                    ic.y += ic.vy * dt
                    val bottom = ic.y - ic.height / 2f
                    if (bottom <= iceLandingY) {
                        landIcicle(ic)
                        it.remove()
                    } else if (ic.y < -ic.height) {
                        it.remove()
                    }
                }
                State.DYING -> {
                    // Penguin-contact recoil + fade-out (ports the SKAction tail).
                    ic.dieAge += dt
                    ic.vy -= ic.gravity * dt
                    ic.x += ic.vxRecoil * dt
                    ic.y += ic.vy * dt
                    ic.rotation += ic.angularVel * dt
                    if (ic.dieAge > 0.15f) {
                        val t = ((ic.dieAge - 0.15f) / 0.2f).coerceIn(0f, 1f)
                        ic.alpha = 1f - t
                        ic.scale = 1f - 0.4f * t
                    }
                    if (ic.dieAge >= 0.35f) it.remove()
                }
            }
        }
    }

    private fun landIcicle(ic: Icicle) {
        val dx = abs(ic.x - penguin.x)
        val severity = (1f - dx / Tuning.Feel.shakeRadius).coerceAtLeast(0f)
        shatter(ic.x, iceLandingY, severity, scale = ic.width / 45f)
        playLandingShatter(dx)
        if (severity > 0f) onShake?.invoke(Tuning.Feel.shakePeakAmplitude * severity)
        if (severity >= Tuning.Score.closeCallSeverity) onCloseCall?.invoke(severity, ic.x)
    }

    // ---- penguin contact (replaces didBegin) ----

    private fun checkPenguinContacts() {
        penguinCircle.set(penguin.shieldCx, penguin.shieldCy, penguin.shieldRadius)
        for (ic in icicles) {
            if (ic.state != State.FALLING) continue
            val hw = ic.width * 0.6f / 2f
            val hh = ic.height * 0.85f / 2f
            icicleRect.set(ic.x - hw, ic.y - hh, hw * 2f, hh * 2f)
            if (Intersector.overlaps(penguinCircle, icicleRect)) {
                val accepted = penguin.tryTakeHit(ic.x)
                onIcicleHitPenguin(ic, accepted)
                onPenguinHit?.invoke(accepted)
            }
        }
    }

    private fun onIcicleHitPenguin(ic: Icicle, accepted: Boolean) {
        // Recoil away from the penguin, then fade out (DYING). Drops out of landing checks.
        ic.state = State.DYING
        ic.dieAge = 0f
        ic.vxRecoil = (if (ic.x >= penguin.x) 1f else -1f) * 220f
        ic.vy = 360f
        ic.angularVel = MathUtils.random(-8f, 8f)

        if (accepted) {
            playLandingShatter(0f)
            audio.playCry()
            shatter(ic.x, ic.y, severity = 1f, scale = (ic.width / 45f).coerceAtLeast(1.2f),
                countOverride = Tuning.Feel.crackBurstShards, speedScaleOverride = Tuning.Feel.crackBurstSpeedScale)
            onShake?.invoke(Tuning.Feel.shakePeakAmplitude)
        } else {
            playLandingShatter(0f)
            shatter(ic.x, ic.y, severity = 0.6f, scale = ic.width / 45f,
                countOverride = Tuning.Feel.shardCountMax, speedScaleOverride = 1.2f)
        }
    }

    // ---- shatter (shards + animated burst) ----

    private fun shatter(
        px: Float, py: Float, severity: Float, scale: Float,
        countOverride: Int? = null, speedScaleOverride: Float? = null,
    ) {
        val s = severity.coerceIn(0f, 1f)
        val count = countOverride
            ?: (Tuning.Feel.shardCountMin +
                Math.round((Tuning.Feel.shardCountMax - Tuning.Feel.shardCountMin) * s))
        val speedScale = speedScaleOverride ?: (1f + Tuning.Feel.shardSeverityBoost * s)
        repeat(count) {
            val angle = MathUtils.random(MathUtils.PI * 0.15f, MathUtils.PI * 0.85f)
            val speed = Tuning.Feel.shardLaunchSpeed * speedScale * MathUtils.random(0.6f, 1.2f)
            shards.add(
                Shard(
                    x = px, y = py,
                    vx = cos(angle) * speed * (if (MathUtils.randomBoolean()) 1f else -1f),
                    vy = sin(angle) * speed,
                    gravity = Tuning.Icicle.sceneGravity,
                    rotation = MathUtils.random(0f, 360f),
                    angularVel = MathUtils.random(-8f, 8f) * MathUtils.radiansToDegrees,
                    scale = MathUtils.random(0.7f, 1.4f),
                )
            )
        }
        val burstSize = Tuning.Feel.shatterBaseSize *
            (Tuning.Feel.shatterMinScale + (1f - Tuning.Feel.shatterMinScale) * s) * scale
        bursts.add(Burst(px, py + burstSize * 0.35f, burstSize))
    }

    private fun spawnPuff(x: Float, y: Float) {
        repeat(5) {
            puffs.add(Puff(x, y, MathUtils.random(-20f, 20f), MathUtils.random(-10f, 10f), MathUtils.random(0.5f, 1f)))
        }
    }

    private fun integrateShardsAndBursts(dt: Float) {
        val sit = shards.iterator()
        while (sit.hasNext()) {
            val sh = sit.next()
            sh.age += dt
            sh.vy -= sh.gravity * dt
            sh.x += sh.vx * dt
            sh.y += sh.vy * dt
            sh.rotation += sh.angularVel * dt
            if (sh.age >= Tuning.Feel.shardLifetime) sit.remove()
        }
        val pit = puffs.iterator()
        while (pit.hasNext()) {
            val pf = pit.next()
            pf.age += dt
            pf.x += pf.vx * dt
            pf.y += pf.vy * dt
            if (pf.age >= 0.4f) pit.remove()
        }
        val bit = bursts.iterator()
        while (bit.hasNext()) {
            val b = bit.next()
            b.age += dt
            if (b.age >= icicleAnims.shatter.animationDuration) bit.remove()
        }
    }

    private fun playLandingShatter(dx: Float) {
        val t = (1f - dx / Tuning.Feel.landingAudioFalloffRadius).coerceAtLeast(0f)
        val vol = Tuning.Feel.landingAudioMinVolume +
            (Tuning.Feel.landingAudioMaxVolume - Tuning.Feel.landingAudioMinVolume) * t
        audio.playShatter(vol)
    }

    // ---- render (called before the penguin so shadows sit under it) ----

    fun render(batch: SpriteBatch) {
        val icicleTex = catalog.texture(Sprite.ICICLE)

        // Icicles (telegraph shake applied to draw x; tint darkens; recoil rotates/fades).
        for (ic in icicles) {
            val drawX = if (ic.state == State.WARNING) {
                ic.x + sin(ic.age * WARNING_SHAKE_FREQ) * 4f
            } else ic.x
            val k = 1f - ic.tint * 0.75f
            batch.setColor(k, k, k, ic.alpha)
            val w = ic.width * ic.scale
            val h = ic.height * ic.scale
            batch.draw(
                icicleTex, drawX - w / 2f, ic.y - h / 2f, w / 2f, h / 2f, w, h, 1f, 1f, ic.rotation,
                0, 0, icicleTex.width, icicleTex.height, false, false,
            )
        }
        batch.setColor(Color.WHITE)

        // Snow puffs.
        for (pf in puffs) {
            val a = (1f - pf.age / 0.4f).coerceIn(0f, 1f)
            batch.setColor(1f, 1f, 1f, a)
            val sz = 6f * pf.scale
            batch.draw(fx.dot, pf.x - sz / 2f, pf.y - sz / 2f, sz, sz)
        }
        batch.setColor(Color.WHITE)

        // Shards.
        for (sh in shards) {
            val a = (1f - sh.age / Tuning.Feel.shardLifetime).coerceIn(0f, 1f)
            batch.setColor(1f, 1f, 1f, a)
            val sz = 8f * sh.scale
            batch.draw(fx.shard, sh.x - sz / 2f, sh.y - sz / 2f, sz / 2f, sz / 2f, sz, sz, 1f, 1f, sh.rotation,
                0, 0, fx.shard.width, fx.shard.height, false, false)
        }
        batch.setColor(Color.WHITE)

        // Shatter bursts (animated).
        for (b in bursts) {
            val frame = icicleAnims.shatter.getKeyFrame(b.age, false)
            batch.draw(frame, b.x - b.size / 2f, b.y - b.size / 2f, b.size, b.size)
        }

        // Under-icicle shadows (drawn last so they sit on the ice, just beneath the penguin).
        for (ic in icicles) {
            if (ic.state != State.FALLING) continue
            val span = ic.spawnY - iceLandingY
            val p = if (span > 0f) (1f - ((ic.y - iceLandingY) / span).coerceIn(0f, 1f)) else 0f
            val scl = Tuning.Feel.shadowMinScale + (Tuning.Feel.shadowMaxScale - Tuning.Feel.shadowMinScale) * p
            val a = Tuning.Feel.shadowMinAlpha + (Tuning.Feel.shadowMaxAlpha - Tuning.Feel.shadowMinAlpha) * p
            batch.setColor(1f, 1f, 1f, a)
            val w = 64f * scl
            val h = 18f * scl
            batch.draw(fx.shadow, ic.x - w / 2f, iceLandingY - h / 2f, w, h)
        }
        batch.setColor(Color.WHITE)
    }

    companion object {
        // ~6 shake cycles across the 0.75 s telegraph.
        private val WARNING_SHAKE_FREQ = (6f * MathUtils.PI2) / Tuning.Icicle.warningDuration
    }
}
