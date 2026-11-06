package com.kfpun.twaqi.watch.data

import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirLevel
import com.kfpun.twaqi.data.model.TaiwanTime
import java.time.Instant
import java.time.format.DateTimeFormatter
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull

/**
 * One station's latest reading, as the watch app, its complication and its tile keep it (iOS
 * `WatchReading`). The county fields are for the station picker only.
 *
 * [publishTime] is Taiwan local time without a zone, as the API sends it.
 */
data class WatchReading(
    val stationId: Int,
    val code: String,
    val name: String,
    val nameLocal: String,
    val aqi: Double,
    val pm25: Double,
    val pm10: Double,
    val o3: Double,
    val co: Double,
    val so2: Double,
    val no2: Double,
    val windDirection: Double,
    val windSpeed: Double,
    val publishTime: String,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val county: String? = null,
    val countyLocal: String? = null,
    val township: String? = null
) {
    /** Name in the reader's language, never blank. */
    fun displayName(chinese: Boolean): String = displayName(if (chinese) nameLocal else name, code, stationId)

    /** The county in the reader's language, for the picker; null when unknown. */
    fun locality(chinese: Boolean): String? = (if (chinese) countyLocal else county)?.takeIf { it.isNotEmpty() }

    fun value(type: AirIndexType): Double = when (type) {
        AirIndexType.AQI -> aqi
        AirIndexType.PM25 -> pm25
        AirIndexType.PM10 -> pm10
        AirIndexType.O3 -> o3
        AirIndexType.CO -> co
        AirIndexType.SO2 -> so2
        AirIndexType.NO2 -> no2
    }

    fun level(type: AirIndexType = AirIndexType.AQI): AirLevel = AirLevel.of(type, value(type))

    fun formatted(type: AirIndexType): String = type.format(value(type))

    val wind: Wind get() = Wind(windDirection, windSpeed)

    /** When it was published; null when the publish time doesn't parse (the placeholders). */
    val publishedAt: Instant? get() = TaiwanTime.parsePublishTime(publishTime)

    fun toJson(): JsonObject = JsonObject(
        buildMap {
            put("stationId", JsonPrimitive(stationId))
            put("code", JsonPrimitive(code))
            put("name", JsonPrimitive(name))
            put("nameLocal", JsonPrimitive(nameLocal))
            put("aqi", JsonPrimitive(aqi))
            put("pm25", JsonPrimitive(pm25))
            put("pm10", JsonPrimitive(pm10))
            put("o3", JsonPrimitive(o3))
            put("co", JsonPrimitive(co))
            put("so2", JsonPrimitive(so2))
            put("no2", JsonPrimitive(no2))
            put("windDirection", JsonPrimitive(windDirection))
            put("windSpeed", JsonPrimitive(windSpeed))
            put("publishTime", JsonPrimitive(publishTime))
            latitude?.let { put("latitude", JsonPrimitive(it)) }
            longitude?.let { put("longitude", JsonPrimitive(it)) }
            county?.let { put("county", JsonPrimitive(it)) }
            countyLocal?.let { put("countyLocal", JsonPrimitive(it)) }
            township?.let { put("township", JsonPrimitive(it)) }
        }
    )

    companion object {
        private val HOUR_MINUTE: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")

        /** `"2026-08-07T22:00:00"` → `"22:00"`, Taiwan time (iOS `asPublishTime`); the raw text when it doesn't parse. */
        fun hourMinute(publishTime: String): String {
            val instant = TaiwanTime.parsePublishTime(publishTime) ?: return publishTime
            return HOUR_MINUTE.format(instant.atZone(TaiwanTime.zone))
        }

        fun displayName(preferred: String, code: String, id: Int): String =
            preferred.ifEmpty { code.ifEmpty { "#$id" } }

        /** Shown in the complication picker before any real reading exists (iOS `placeholder`). */
        val placeholder = WatchReading(
            stationId = 0, code = "Songshan", name = "Songshan", nameLocal = "松山",
            aqi = 42.0, pm25 = 9.0, pm10 = 21.0, o3 = 31.2, co = 0.32, so2 = 1.4, no2 = 12.5,
            windDirection = 247.0, windSpeed = 2.6, publishTime = ""
        )

        /** A reading saved by [toJson]; null when a required field is missing. */
        fun fromJson(element: JsonElement?): WatchReading? {
            val o = element as? JsonObject ?: return null
            return WatchReading(
                stationId = o.int("stationId") ?: return null,
                code = o.string("code") ?: "",
                name = o.string("name") ?: "",
                nameLocal = o.string("nameLocal") ?: "",
                aqi = o.double("aqi") ?: return null,
                pm25 = o.double("pm25") ?: return null,
                pm10 = o.double("pm10") ?: return null,
                o3 = o.double("o3") ?: return null,
                co = o.double("co") ?: return null,
                so2 = o.double("so2") ?: return null,
                no2 = o.double("no2") ?: return null,
                windDirection = o.double("windDirection") ?: 0.0,
                windSpeed = o.double("windSpeed") ?: 0.0,
                publishTime = o.string("publishTime") ?: "",
                latitude = o.double("latitude"),
                longitude = o.double("longitude"),
                county = o.string("county"),
                countyLocal = o.string("countyLocal"),
                township = o.string("township")
            )
        }

        fun listToJson(readings: List<WatchReading>): String = JsonArray(readings.map { it.toJson() }).toString()

        fun listFromJson(text: String?): List<WatchReading> =
            (WatchJson.parse(text) as? JsonArray)?.mapNotNull(::fromJson).orEmpty()
    }
}

/** Wind as the API reports it (iOS `Wind`): the bearing it blows from, in m/s. */
data class Wind(val direction: Double, val speed: Double) {
    /** The API reports `0 / 0` for calm air and for stations without an anemometer alike. */
    val isCalm: Boolean get() = speed <= 0

    /** 16-point compass abbreviation, `297°` → `WNW`; a dash when calm. */
    val compassPoint: String
        get() {
            if (isCalm) return "—"
            val normalised = ((direction % 360) + 360) % 360
            return POINTS[Math.round(normalised / 22.5).toInt() % 16]
        }

    private companion object {
        val POINTS =
            listOf("N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW")
    }
}

/** One hour of a station's history (iOS `HistoricalPollutant`). */
data class HistoryPoint(
    val aqi: Double,
    val pm25: Double,
    val pm10: Double,
    val o3: Double,
    val co: Double,
    val so2: Double,
    val no2: Double,
    val publishTime: String
) {
    fun value(type: AirIndexType): Double = when (type) {
        AirIndexType.AQI -> aqi
        AirIndexType.PM25 -> pm25
        AirIndexType.PM10 -> pm10
        AirIndexType.O3 -> o3
        AirIndexType.CO -> co
        AirIndexType.SO2 -> so2
        AirIndexType.NO2 -> no2
    }
}

internal fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject

internal fun JsonObject.primitive(key: String): JsonPrimitive? = (this[key] as? JsonPrimitive)?.takeIf {
    it !is JsonNull
}

internal fun JsonObject.string(key: String): String? = primitive(key)?.takeIf { it.isString }?.content

internal fun JsonObject.double(key: String): Double? = primitive(key)?.takeIf { !it.isString }?.doubleOrNull

internal fun JsonObject.int(key: String): Int? = primitive(key)?.takeIf { !it.isString }?.let { p ->
    p.intOrNull ?: p.doubleOrNull?.takeIf { it % 1.0 == 0.0 }?.toInt()
}
