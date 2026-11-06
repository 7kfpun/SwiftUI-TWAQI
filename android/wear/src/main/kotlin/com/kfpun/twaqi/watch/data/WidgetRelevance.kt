package com.kfpun.twaqi.watch.data

import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirLevel
import java.time.Duration
import java.time.Instant

/**
 * How relevant a reading makes the complication (iOS `WidgetRelevance`, FOX-75): one 0–100 scale
 * for every TWAQI surface, so a score means the same on the phone and the watch.
 *
 * | Reading                                      | Score |
 * |----------------------------------------------|-------|
 * | No reading, no level, locked, or stale data  | 0     |
 * | Good                                         | 10    |
 * | Moderate                                     | 25    |
 * | Unhealthy for sensitive groups               | 50    |
 * | Unhealthy                                    | 70    |
 * | Very unhealthy                               | 85    |
 * | Hazardous                                    | 90    |
 * | Worse than the previous publish              | +5    |
 * | AQI at or over the station's alert threshold | 100   |
 *
 * Wear OS has no Smart Stack or relevance API to hand the score to (iOS
 * `TimelineEntryRelevance`, `SmartStackHints`), so nothing on the watch reads it yet: it is
 * ported, with its tests, so the scale stays the same once Wear OS offers one. Pure.
 */
object WidgetRelevance {
    const val MAX_SCORE = 100f

    /** Data older than this says nothing about the air now, so it scores 0. */
    val MAX_DATA_AGE: Duration = Duration.ofHours(3)

    /** Less than the gap between two levels, so worsening never outranks the next level up. */
    const val WORSENING_BOOST = 5f

    /** Two publishes each for a few stations is all a complication needs. */
    const val HISTORY_LIMIT = 12

    fun levelScore(level: AirLevel): Float = when (level) {
        AirLevel.GOOD -> 10f
        AirLevel.MODERATE -> 25f
        AirLevel.UNHEALTHY_FOR_SENSITIVE_GROUP -> 50f
        AirLevel.UNHEALTHY -> 70f
        AirLevel.VERY_UNHEALTHY -> 85f
        AirLevel.HAZARDOUS -> 90f
        AirLevel.UNKNOWN -> 0f
    }

    /**
     * The score for [reading] on a complication showing [type]. [previous] is the same station's
     * reading from an earlier publish ([previous]); [alertThreshold] its "above" alert (AQI).
     */
    fun score(
        reading: WatchReading?,
        type: AirIndexType,
        previous: WatchReading? = null,
        alertThreshold: Int? = null,
        isLocked: Boolean = false,
        now: Instant = Instant.now()
    ): Float {
        if (reading == null || isLocked || !isFresh(reading, now)) return 0f
        val level = reading.level(type)
        if (level == AirLevel.UNKNOWN) return 0f
        if (alertThreshold != null && reading.aqi >= alertThreshold) return MAX_SCORE

        var score = levelScore(level)
        if (previous != null && previous.stationId == reading.stationId && reading.value(type) > previous.value(type)) {
            score += WORSENING_BOOST
        }
        return minOf(score, MAX_SCORE)
    }

    /** Published no more than [MAX_DATA_AGE] ago; false when the publish time doesn't parse. */
    fun isFresh(reading: WatchReading, now: Instant = Instant.now()): Boolean {
        val published = reading.publishedAt ?: return false
        return Duration.between(published, now) <= MAX_DATA_AGE
    }

    /**
     * [history] with [reading] added, keeping each station's latest publish and the one before it.
     * A reading of a publish already held replaces it; an older one is ignored. Most recent last.
     */
    fun recording(reading: WatchReading, history: List<WatchReading>): List<WatchReading> {
        val sameStation = history.filter { it.stationId == reading.stationId }
        val others = history.filter { it.stationId != reading.stationId }
        val latest = sameStation.lastOrNull()
        if (latest != null && isOlder(reading, latest)) return history
        val kept = sameStation.filter { it.publishTime != reading.publishTime }.takeLast(1)
        return (others + kept + reading).takeLast(HISTORY_LIMIT)
    }

    /** The reading [history] holds for [reading]'s station from an earlier publish, if any. */
    fun previous(reading: WatchReading, history: List<WatchReading>): WatchReading? =
        history.lastOrNull { it.stationId == reading.stationId && it.publishTime != reading.publishTime }
            ?.takeIf { isOlder(it, reading) }

    /** Compared by publish time; unreadable times count as not older. */
    private fun isOlder(lhs: WatchReading, rhs: WatchReading): Boolean {
        val left = lhs.publishedAt ?: return false
        val right = rhs.publishedAt ?: return false
        return left < right
    }
}
