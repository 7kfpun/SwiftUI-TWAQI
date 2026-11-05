package com.kfpun.twaqi.widget

import com.kfpun.twaqi.data.cache.CacheStore
import com.kfpun.twaqi.data.model.HistoricalPollutant
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.put

/**
 * The station detail widget's last good 24 hours per station (iOS `WidgetStationDetailCache`),
 * so it still draws its trend offline. A failed or empty fetch keeps the saved copy; a week-old
 * copy is ignored and purged like every offline cache, since it lives under the cache root
 * ([CacheStore], `OfflineCacheRetention`).
 */
class WidgetHistoryCache(private val store: CacheStore) {
    fun read(stationId: Int): List<HistoricalPollutant>? {
        val text = store.read(fileName(stationId))?.value ?: return null
        val array = runCatching { kotlinx.serialization.json.Json.parseToJsonElement(text) as? JsonArray }
            .getOrNull() ?: return null
        return array.mapNotNull { (it as? JsonObject)?.let(::decode) }.takeIf { it.isNotEmpty() }
    }

    /** Saves [readings] (oldest first); an empty list is a failed fetch and keeps the saved copy. */
    fun save(stationId: Int, readings: List<HistoricalPollutant>) {
        if (readings.isEmpty()) return
        store.write(fileName(stationId), buildJsonArray { readings.forEach { add(encode(it)) } }.toString())
    }

    private fun encode(reading: HistoricalPollutant): JsonObject = buildJsonObject {
        put("aqi", reading.aqi)
        put("pm25", reading.pm25)
        put("pm10", reading.pm10)
        put("no2", reading.no2)
        put("so2", reading.so2)
        put("co", reading.co)
        put("o3", reading.o3)
        put("wind_direction", reading.windDirection)
        put("wind_speed", reading.windSpeed)
        put("publish_time", reading.publishTime)
    }

    private fun decode(json: JsonObject): HistoricalPollutant? {
        fun number(key: String): Double = (json[key] as? JsonPrimitive)?.doubleOrNull ?: 0.0
        val time = (json["publish_time"] as? JsonPrimitive)?.contentOrNull ?: return null
        return HistoricalPollutant(
            aqi = number("aqi"),
            pm25 = number("pm25"),
            pm10 = number("pm10"),
            no2 = number("no2"),
            so2 = number("so2"),
            co = number("co"),
            o3 = number("o3"),
            windDirection = number("wind_direction"),
            windSpeed = number("wind_speed"),
            publishTime = time
        )
    }

    companion object {
        fun fileName(stationId: Int) = "widget-history-$stationId.json"
    }
}
