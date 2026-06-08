package dev.copt.penguinslide

/**
 * Gameplay-tuning constants and physics category ids — a faithful port of the iOS
 * `Tuning` enum. Knobs are grouped by subsystem to mirror the README's "Where to tweak
 * difficulty" table. Values are kept identical to the Swift source so difficulty and feel
 * carry over 1:1. All distances are in virtual points (see [GameScreen]).
 */
object Tuning {

    /** Penguin input + feel. Mutable + persisted (see [PenguinTuning]); reassigned at
     *  startup from saved prefs. Call sites read `Tuning.penguin.maxSpeed` etc. */
    @JvmField
    var penguin: PenguinTuning = PenguinTuning()

    /** Icicle physics: telegraph + per-icicle gravity. */
    object Icicle {
        const val warningDuration = 0.75f
        const val spawnIntervalStart = 1.10f
        const val spawnIntervalEnd = 0.34f
        const val sceneGravity = 700f
        const val gravityScaleStart = 0.53f
        const val gravityScaleEnd = 1.30f
        const val gravityScaleVariance = 0.20f
        const val initialDownVelocity = 50f
        const val massKg = 0.5f
        const val restitution = 0.15f
    }

    /** "Chase" aim algorithm — how aggressively spawns target the penguin. */
    object Chase {
        const val leadFactor = 0.2f
        const val jitterStart = 0.35f
        const val jitterEnd = 0.10f
        const val randomChance = 0.20f
    }

    /** Skill-based scoring. A "close-call" is a *survived* landing whose severity clears
     *  [closeCallSeverity]; severity is the single source of truth for "how close". */
    object Score {
        const val survivalRate = 10f
        const val closeCallSeverity = 0.5f
        const val closeCallBase = 50
        const val comboWindow = 2.5f
        const val comboMaxMultiplier = 5.0f
    }

    /** Visual feedback on impact: shatter shards + camera shake + audio falloff. */
    object Feel {
        const val shardCountMin = 2
        const val shardCountMax = 5
        const val shardLaunchSpeed = 220f
        const val shardSeverityBoost = 0.30f
        const val shardLifetime = 0.6f
        const val shakePeakAmplitude = 8f
        const val shakeRadius = 140f
        const val crackBurstShards = 8
        const val crackBurstSpeedScale = 1.6f
        const val shadowMinScale = 0.35f
        const val shadowMaxScale = 1.0f
        const val shadowMinAlpha = 0.15f
        const val shadowMaxAlpha = 0.55f
        const val shatterAnimFps = 14f
        const val shatterBaseSize = 110f
        const val shatterMinScale = 0.55f
        const val landingAudioFalloffRadius = 600f
        const val landingAudioMinVolume = 0.025f
        const val landingAudioMaxVolume = 0.22f
    }

    /** Round-level pacing. */
    object Run {
        const val rampDuration = 90f
        const val gracePeriod = 1.2f
        const val playWidthFraction = 0.82f
    }

    /** Contact-detection group ids. With manual physics these tag overlap groups rather
     *  than driving any engine collision response. */
    object Category {
        const val penguin = 1 shl 0
        const val icicle = 1 shl 1
        const val shard = 1 shl 2
    }
}
