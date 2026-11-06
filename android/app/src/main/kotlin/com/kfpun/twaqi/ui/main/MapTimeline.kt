package com.kfpun.twaqi.ui.main

import com.kfpun.twaqi.data.model.HistoricalPollutant
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.model.TaiwanTime
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/**
 * Hour arithmetic on the API's publish times, for the map timeline (iOS `MapTimeline`).
 *
 * Publish times are Taiwan wall-clock strings without a zone (`2026-10-31T17:00:00`, or with a
 * space). They are read in `Asia/Taipei`, never the device zone, so "three hours before" and
 * "yesterday" are Taiwan's, wherever the phone is.
 *
 * The scrubber has [HOURS] + 1 positions: index 0 is [HOURS] hours before the latest reading (the
 * anchor) at the left, index [HOURS] is the anchor at the right. There is no forecast, so nothing
 * lies to the right of "now".
 */
object MapTimeline {
    /** How far back the scrubber reaches. */
    const val HOURS = 24

    private val key: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss")
    private val clock: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")
    private val day: DateTimeFormatter = DateTimeFormatter.ofPattern("M/d")

    /** The publish time's hour in Taiwan, or null when it doesn't parse. */
    fun hour(publishTime: String): ZonedDateTime? =
        TaiwanTime.parsePublishTime(publishTime)?.atZone(TaiwanTime.zone)?.truncatedTo(ChronoUnit.HOURS)

    /** The publish time snapped to its hour, `"2026-11-06T14:00:00"`: the history cache key. */
    fun hourKey(publishTime: String): String? = hour(publishTime)?.let(::hourKey)

    fun hourKey(hour: ZonedDateTime): String = key.format(hour.withZoneSameInstant(TaiwanTime.zone))

    /** The publish hour [hoursAgo] before [anchor], as an [hourKey]. */
    fun publishTime(anchor: String, hoursAgo: Int): String? =
        hour(anchor)?.minusHours(hoursAgo.toLong())?.let(::hourKey)

    /** Every hour on the scrubber, oldest first: index 0 is [HOURS] ago, the last is [anchor]'s hour. */
    fun hours(anchor: String): List<String> {
        val latest = hour(anchor) ?: return emptyList()
        return (HOURS downTo 0).map { hourKey(latest.minusHours(it.toLong())) }
    }

    /** Scrubber index for [hoursAgo], and back. */
    fun index(hoursAgo: Int): Int = HOURS - hoursAgo.coerceIn(0, HOURS)

    fun hoursAgo(index: Int): Int = HOURS - index.coerceIn(0, HOURS)

    /**
     * How the timeline names an hour: its clock time, flagged [TimelineHour.yesterday] when it falls
     * on the day before [anchor] in Taiwan, and how far back it is.
     */
    fun describe(anchor: String, hoursAgo: Int): TimelineHour? {
        val latest = hour(anchor) ?: return null
        val shown = latest.minusHours(hoursAgo.toLong())
        return TimelineHour(
            clock = clock.format(shown),
            yesterday = shown.toLocalDate() != latest.toLocalDate(),
            hoursAgo = hoursAgo
        )
    }

    /**
     * Labels under the track: one every six hours on the clock, the date (`11/6`) at midnight.
     * Hours within three of either end are left unlabelled so nothing overlaps the "Now" label the
     * bar puts at index [HOURS].
     */
    fun tickLabels(anchor: String): List<TimelineTick> {
        val latest = hour(anchor) ?: return emptyList()
        return (3..HOURS - 3).mapNotNull { index ->
            val shown = latest.minusHours((HOURS - index).toLong())
            when {
                shown.hour % 6 != 0 -> null
                shown.hour == 0 -> TimelineTick(index, day.format(shown))
                else -> TimelineTick(index, clock.format(shown))
            }
        }
    }

    /** The latest publish time among a country's stations: "now" on the timeline. */
    fun anchor(pollutants: Collection<Pollutant>): String? =
        pollutants.mapNotNull { p -> p.publishedAt?.let { it to p.publishTime } }.maxByOrNull { it.first }?.second
}

/** An hour on the timeline: `"17:00"`, whether it is the day before the latest reading, and how far back. */
data class TimelineHour(val clock: String, val yesterday: Boolean, val hoursAgo: Int)

/** A labelled tick under the timeline's track. */
data class TimelineTick(val index: Int, val text: String)

/**
 * This station as it read at an earlier [hour] (iOS `Pollutant(_:reading:publishTime:)`): identity,
 * name and place from the live reading, values (wind included) from [reading].
 *
 * No reading means no data for that hour: every value is 0, which the markers and the closest
 * card already show as a grey "-".
 */
fun Pollutant.at(hour: String, reading: HistoricalPollutant?): Pollutant = copy(
    aqi = reading?.aqi ?: 0.0,
    pm25 = reading?.pm25 ?: 0.0,
    pm10 = reading?.pm10 ?: 0.0,
    no2 = reading?.no2 ?: 0.0,
    so2 = reading?.so2 ?: 0.0,
    co = reading?.co ?: 0.0,
    o3 = reading?.o3 ?: 0.0,
    windDirection = reading?.windDirection ?: 0.0,
    windSpeed = reading?.windSpeed ?: 0.0,
    publishTime = reading?.publishTime ?: hour
)
