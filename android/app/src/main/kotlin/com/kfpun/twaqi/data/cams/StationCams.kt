package com.kfpun.twaqi.data.cams

import com.kfpun.twaqi.data.model.TaiwanTime
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject

/**
 * One MOENV station webcam, as listed in the public cam manifest (iOS `StationCam`).
 *
 * [siteId] is MOENV's zero-padded SiteId ("001" for 基隆). It is *not* the AQI API's station id
 * (基隆 is 91 there): the two numbering schemes are unrelated, so the only way from a station to
 * its cam is [StationCamMatcher].
 *
 * @property time capture time, e.g. `"2026-10-30T22:30:00+08:00"`.
 */
data class StationCam(val siteId: String, val name: String, val lat: Double, val lon: Double, val time: String?) {
    val capturedAt: Instant? get() = time?.let { runCatching { OffsetDateTime.parse(it).toInstant() }.getOrNull() }
}

/** `manifest.json`: `{ "updatedAt": …, "stations": { "001": { name, lat, lon, time, key } } }`. */
object StationCamManifest {
    private val json = Json { ignoreUnknownKeys = true }

    /** The cams, sorted by site id; null when [text] isn't a manifest. Entries missing a field are skipped. */
    fun parse(text: String): List<StationCam>? {
        val stations = runCatching { json.parseToJsonElement(text).jsonObject["stations"] as? JsonObject }
            .getOrNull() ?: return null
        return stations.mapNotNull { (siteId, value) ->
            val entry = value as? JsonObject ?: return@mapNotNull null
            val name = (entry["name"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return@mapNotNull null
            val lat = (entry["lat"] as? JsonPrimitive)?.doubleOrNull ?: return@mapNotNull null
            val lon = (entry["lon"] as? JsonPrimitive)?.doubleOrNull ?: return@mapNotNull null
            val time = (entry["time"] as? JsonPrimitive)?.takeIf { it.isString }?.content
            StationCam(siteId, name, lat, lon, time)
        }.sortedBy { it.siteId }
    }
}

/** Joins an AQI station to its MOENV cam (iOS `StationCamMatcher`). */
object StationCamMatcher {
    /**
     * How far a station may sit from a cam and still be matched by position alone. Deliberately
     * tight: the closest pair of distinct cam sites is ~530 m apart (林森 / 臺南), and at 1.5 km 復興
     * (no cam) picked up 前鎮's cam 610 m away. Stations whose coordinates drift further than this
     * from their cam's are still caught by name, which is checked first.
     */
    const val MAX_DISTANCE_KM = 0.5

    /** Name first, then the nearest cam within [MAX_DISTANCE_KM], else null. */
    fun match(name: String, lat: Double, lon: Double, cams: List<StationCam>): StationCam? {
        val key = normalize(name)
        if (key.isNotEmpty()) {
            cams.firstOrNull { normalize(it.name) == key }?.let { return it }
        }
        if (lat == 0.0 && lon == 0.0) return null
        return cams
            .map { it to distanceKm(lat, lon, it.lat, it.lon) }
            .filter { it.second <= MAX_DISTANCE_KM }
            .minByOrNull { it.second }
            ?.first
    }

    /** The API and the manifest disagree on trivia: `屏東(琉球)` vs `屏東（琉球）`, and 臺 vs 台. */
    fun normalize(name: String): String = name
        .replace('（', '(')
        .replace('）', ')')
        .replace('臺', '台')
        .filterNot { it.isWhitespace() }

    /** Great-circle distance. */
    fun distanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val rad = Math.PI / 180
        val dLat = (lat2 - lat1) * rad
        val dLon = (lon2 - lon1) * rad
        val a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1 * rad) * cos(lat2 * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 6371 * 2 * asin(min(1.0, sqrt(a)))
    }
}

/** What the station page knows about its cam (iOS `StationCamState`). */
sealed interface StationCamState {
    /** Station or manifest not loaded yet. */
    data object Loading : StationCamState

    data class Available(val cam: StationCam) : StationCamState

    /** No cam joins to this station: most micro-sensor sites. */
    data object Missing : StationCamState
}

/**
 * One clock hour of a cam's history: `stations/{siteId}/{yyyy-MM-dd}/{HH}.jpg` (iOS
 * `StationCamHour`).
 *
 * The Worker files the first frame of each Taiwan clock hour under that key and keeps a week of
 * them, so the app builds the URL itself; nothing lists the bucket. Two hours are equal when they
 * are the same cam and the same clock hour, whatever the minute they were made from.
 */
class StationCamHour(val siteId: String, hour: Instant) {
    /** Start of the hour. */
    val hour: Instant = startOfHour(hour)

    /** `"2026-10-30"`, the Taiwan date. */
    val day: String get() = DAY.format(hour.atZone(ZONE))

    /** `"22"`, the Taiwan hour. */
    val hourOfDay: String get() = HOUR.format(hour.atZone(ZONE))

    /** `"2026-10-30/22"`: the hour key. */
    val key: String get() = "$day/$hourOfDay"

    /** `stations/001/2026-10-30/22.jpg`: the object key. */
    val objectKey: String get() = "stations/$siteId/$key.jpg"

    /** `001-2026-10-30-22.jpg`: flat, one file per cam and hour. */
    val cacheFileName: String get() = "$siteId-$day-$hourOfDay.jpg"

    override fun equals(other: Any?): Boolean = other is StationCamHour && other.siteId == siteId && other.hour == hour

    override fun hashCode(): Int = 31 * siteId.hashCode() + hour.hashCode()

    override fun toString(): String = "StationCamHour($objectKey)"

    companion object {
        /** MOENV capture times are Taiwan clock time (UTC+8, no DST), never the device zone. */
        val ZONE: ZoneId = TaiwanTime.zone

        /** The 24 hours the scrubber offers. */
        const val COUNT = 24

        /** Slots fetched around the one on screen: it and two either side. */
        const val NEIGHBORS = 2

        private val DAY: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
        private val HOUR: DateTimeFormatter = DateTimeFormatter.ofPattern("HH")

        fun startOfHour(instant: Instant): Instant = instant.atZone(ZONE).truncatedTo(ChronoUnit.HOURS).toInstant()

        /**
         * The 24 clock hours up to and including the one [anchor] falls in, oldest first.
         *
         * The anchor is the live frame's capture time rather than the clock: MOENV frames land
         * about half an hour late, so the hour that's just begun would almost always be empty.
         */
        fun slots(siteId: String, anchor: Instant): List<StationCamHour> {
            val last = startOfHour(anchor).atZone(ZONE)
            return (COUNT - 1 downTo 0).map { StationCamHour(siteId, last.minusHours(it.toLong()).toInstant()) }
        }

        /**
         * Indices to load around [index], nearest first: it, then ±1, then ±2, clamped to
         * `0 until count`. Nothing further out is fetched or decoded.
         */
        fun window(index: Int, count: Int = COUNT, radius: Int = NEIGHBORS): List<Int> {
            if (index !in 0 until count) return emptyList()
            val around = (0 until maxOf(radius, 0)).flatMap { listOf(index - it - 1, index + it + 1) }
            return listOf(index) + around.filter { it in 0 until count }
        }
    }
}
