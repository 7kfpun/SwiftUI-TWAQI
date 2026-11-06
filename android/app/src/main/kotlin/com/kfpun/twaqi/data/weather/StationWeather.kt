package com.kfpun.twaqi.data.weather

import com.kfpun.twaqi.data.model.TaiwanTime
import com.kfpun.twaqi.ui.main.GeoPoint
import com.kfpun.twaqi.ui.main.NearestStations
import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull

/** The weather file wasn't the JSON the Worker writes. */
class WeatherFormatException(message: String) : Exception(message)

/**
 * `weather/latest.json` on the webcam host, written hourly by the Worker from two Central Weather
 * Administration (CWA) open-data sets (iOS `WeatherFile`, FOX-11):
 *
 * - [forecast]: F-C0032-001, the 36-hour forecast per county (縣市), in 12-hour periods: CWA
 *   weather code and text, chance of rain, min/max °C.
 * - [observations]: O-A0003-001, the latest readings of CWA's staffed stations, with their WGS84
 *   position.
 *
 * Either section is null until its first good sync; the Worker keeps a section's last good copy
 * when a later fetch fails. Free text (Wx descriptions, station names) is zh-Hant as CWA publishes
 * it.
 */
data class WeatherFile(val updatedAt: String, val forecast: Forecast?, val observations: Observations?) {
    /** County name as CWA writes it (`臺北市`, 臺 not 台) → its periods, oldest first. */
    data class Forecast(val counties: Map<String, List<WeatherPeriod>>)

    data class Observations(val stations: List<WeatherObservation>)

    companion object {
        /** Under the webcam host (`STATION_CAMS_URL`), as iOS `StationCam.baseURL`. */
        const val PATH = "weather/latest.json"

        private val json = Json { ignoreUnknownKeys = true }

        /**
         * Reads the file as iOS decodes it: `updatedAt` is required, a section may be null, and a
         * period or station missing a required field fails the file, so a half-written body is a
         * failed refresh rather than a card with gaps.
         */
        fun parse(body: String): WeatherFile {
            val root = try {
                json.parseToJsonElement(body)
            } catch (e: IllegalArgumentException) {
                throw WeatherFormatException("not JSON: ${e.message}")
            } as? JsonObject ?: throw WeatherFormatException("not an object")

            val forecast = root.objectOrNull("forecast")?.let { section ->
                val counties = section["counties"] as? JsonObject ?: throw WeatherFormatException("no counties")
                Forecast(
                    counties.mapValues { (_, periods) ->
                        (periods as? JsonArray ?: throw WeatherFormatException("periods")).map(::period)
                    }
                )
            }
            val observations = root.objectOrNull("observations")?.let { section ->
                val stations = section["stations"] as? JsonArray ?: throw WeatherFormatException("no stations")
                Observations(stations.map(::observation))
            }
            return WeatherFile(
                updatedAt = root.string("updatedAt") ?: throw WeatherFormatException("no updatedAt"),
                forecast = forecast,
                observations = observations
            )
        }

        private fun period(element: JsonElement): WeatherPeriod {
            val item = element as? JsonObject ?: throw WeatherFormatException("period")
            return WeatherPeriod(
                start = item.string("start") ?: throw WeatherFormatException("period start"),
                end = item.string("end") ?: throw WeatherFormatException("period end"),
                wx = item.number("wx")?.toInt(),
                text = item.string("text"),
                pop = item.number("pop"),
                minT = item.number("minT"),
                maxT = item.number("maxT")
            )
        }

        private fun observation(element: JsonElement): WeatherObservation {
            val item = element as? JsonObject ?: throw WeatherFormatException("station")
            return WeatherObservation(
                id = item.string("id") ?: throw WeatherFormatException("station id"),
                name = item.string("name") ?: throw WeatherFormatException("station name"),
                county = item.string("county"),
                lat = item.number("lat") ?: throw WeatherFormatException("station lat"),
                lon = item.number("lon") ?: throw WeatherFormatException("station lon"),
                time = item.string("time") ?: throw WeatherFormatException("station time"),
                temp = item.number("temp"),
                humidity = item.number("humidity"),
                rain = item.number("rain"),
                wind = item.number("wind")
            )
        }

        private fun JsonObject.objectOrNull(key: String): JsonObject? = when (val value = get(key)) {
            null -> null
            is JsonObject -> value
            is JsonPrimitive -> if (value.contentOrNull == null) null else throw WeatherFormatException(key)
            else -> throw WeatherFormatException(key)
        }

        private fun JsonObject.string(key: String): String? =
            (get(key) as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull

        private fun JsonObject.number(key: String): Double? =
            (get(key) as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull
    }
}

/** One period of the county forecast, usually 12 hours (06–18, 18–06); the first can be shorter. */
data class WeatherPeriod(
    /** ISO 8601 with the Taiwan offset, e.g. `2026-11-05T18:00:00+08:00`. */
    val start: String,
    val end: String,
    /** CWA weather code, 1–42 ([WeatherCode]). */
    val wx: Int?,
    /** CWA's own description, zh-Hant (「多雲短暫雨」). */
    val text: String?,
    /** Chance of rain, %. */
    val pop: Double?,
    val minT: Double?,
    val maxT: Double?
) {
    val startInstant: Instant? get() = WeatherDates.parse(start)
    val endInstant: Instant? get() = WeatherDates.parse(end)

    /** Starts in the evening or before dawn, Taiwan time: the icon shows a moon. */
    val isNight: Boolean
        get() {
            val hour = startInstant?.atZone(TaiwanTime.zone)?.hour ?: return false
            return hour >= 18 || hour < 6
        }
}

/** One CWA weather station's latest reading. */
data class WeatherObservation(
    /** CWA station id (`466920`), unrelated to MOENV's or the AQI API's. */
    val id: String,
    /** zh-Hant (`臺北`). */
    val name: String,
    val county: String?,
    val lat: Double,
    val lon: Double,
    /** ISO 8601 with offset. */
    val time: String,
    /** °C */
    val temp: Double?,
    /** % */
    val humidity: Double?,
    /** mm since local midnight. */
    val rain: Double?,
    /** m/s */
    val wind: Double?
) {
    val observedAt: Instant? get() = WeatherDates.parse(time)
}

/**
 * What the station page's weather card shows. Built by [StationWeatherMatcher], which returns null
 * rather than an empty one.
 *
 * @property now null when no CWA station with a recent reading is within range.
 * @property county the CWA county the periods are for (zh-Hant).
 * @property periods up to [StationWeatherMatcher.PERIOD_COUNT] periods that haven't ended.
 */
data class StationWeather(val now: Now?, val county: String?, val periods: List<WeatherPeriod>) {
    /** @property distanceKm from the AQI station to the CWA station. */
    data class Now(val observation: WeatherObservation, val distanceKm: Double, val observedAt: Instant)
}

/**
 * Joins an AQI station to CWA weather (iOS `StationWeatherMatcher`). CWA station ids have nothing
 * to do with MOENV's, so the join is by position (observations) and county name (forecast).
 */
object StationWeatherMatcher {
    /** Further than this, a reading says little about the station's weather. */
    const val MAX_DISTANCE_KM = 20.0

    /**
     * CWA's staffed stations report every 10 minutes and the Worker syncs hourly; a reading older
     * than this means the station or the sync has stopped, and is not shown as "now".
     */
    val maxObservationAge: Duration = Duration.ofHours(3)

    /** A few minutes ahead of the device clock is tolerated; further ahead is a bad timestamp. */
    private val maxClockSkew: Duration = Duration.ofMinutes(10)

    /** The 36-hour forecast is three 12-hour periods. */
    const val PERIOD_COUNT = 3

    /**
     * What to show for a station at [lat]/[lon] in [countyLocal], or null when there is nothing:
     * the card is then hidden.
     */
    fun weather(
        lat: Double,
        lon: Double,
        countyLocal: String?,
        file: WeatherFile,
        now: Instant = Instant.now()
    ): StationWeather? {
        val stations = file.observations?.stations.orEmpty()
        val reading = nearest(lat, lon, stations, now)

        val counties = file.forecast?.counties.orEmpty()
        val county = county(countyLocal, nearest(lat, lon, stations, null)?.observation, counties.keys)
        val periods = county?.let { counties[it] }?.let { upcoming(it, now) }.orEmpty()

        if (reading == null && periods.isEmpty()) return null
        return StationWeather(now = reading, county = if (periods.isEmpty()) null else county, periods = periods)
    }

    /**
     * The closest station within [MAX_DISTANCE_KM] with a reading. With [now], only readings no
     * older than [maxObservationAge] (and not from the future) count, so a dead station gives way
     * to a live one further off. A station without a position (0, 0) has no nearest.
     */
    fun nearest(lat: Double, lon: Double, stations: List<WeatherObservation>, now: Instant?): StationWeather.Now? {
        if (lat == 0.0 && lon == 0.0) return null
        return stations
            .mapNotNull { station ->
                val observedAt = station.observedAt ?: return@mapNotNull null
                if (now != null && !isFresh(observedAt, now)) return@mapNotNull null
                val km = NearestStations.distanceKm(GeoPoint(lat, lon), GeoPoint(station.lat, station.lon))
                if (km > MAX_DISTANCE_KM) return@mapNotNull null
                StationWeather.Now(station, km, observedAt)
            }
            .minByOrNull { it.distanceKm }
    }

    /** A reading from the last [maxObservationAge], or at most a few minutes ahead. */
    fun isFresh(observedAt: Instant, now: Instant): Boolean {
        val age = Duration.between(observedAt, now)
        return age <= maxObservationAge && age >= maxClockSkew.negated()
    }

    /**
     * The station's own county when the forecast has it, else the nearest CWA station's (a station
     * whose record has no county).
     */
    fun county(countyLocal: String?, nearest: WeatherObservation?, counties: Set<String>): String? =
        listOf(countyLocal, nearest?.county).firstNotNullOfOrNull { candidate ->
            candidate?.let(::normalizeCounty)?.takeIf { it in counties }
        }

    /** Periods that haven't ended, oldest first, at most [PERIOD_COUNT]. */
    fun upcoming(periods: List<WeatherPeriod>, now: Instant): List<WeatherPeriod> = periods
        .filter { (it.endInstant ?: Instant.MIN) > now }
        .sortedBy { it.start }
        .take(PERIOD_COUNT)

    /** CWA writes 臺; MOENV and the AQI API sometimes 台. */
    fun normalizeCounty(name: String): String = name.replace("台", "臺").trim()
}

/** Weather times are Taiwan time; the file carries ISO 8601 with an offset (iOS `WeatherDates`). */
object WeatherDates {
    private val local: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss")
    private val day: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")

    /** `2026-11-05T18:00:00+08:00` or `…Z`; a value without an offset is read as Taiwan time. */
    fun parse(value: String): Instant? {
        runCatching { return OffsetDateTime.parse(value).toInstant() }
        val text = value.replace(' ', 'T').take(19)
        return runCatching { LocalDateTime.parse(text, local).atZone(TaiwanTime.zone).toInstant() }.getOrNull()
    }

    /** The Taiwan calendar day [instant] falls on, `yyyy-MM-dd`, for [TaiwanTime.daysFromToday]. */
    fun day(instant: Instant): String = day.format(instant.atZone(TaiwanTime.zone))
}
