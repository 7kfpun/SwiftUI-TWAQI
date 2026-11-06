package com.kfpun.twaqi.watch

import com.kfpun.twaqi.data.model.TaiwanTime
import com.kfpun.twaqi.watch.data.KeyValueStore
import com.kfpun.twaqi.watch.data.WatchReading
import java.time.Instant
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

/** Preferences in memory. */
class MapKeyValueStore : KeyValueStore {
    val values = mutableMapOf<String, String>()

    override fun get(key: String): String? = values[key]

    override fun set(key: String, value: String?) {
        if (value == null) values.remove(key) else values[key] = value
    }
}

/** A Taiwan wall-clock time as an instant. */
fun taipei(year: Int, month: Int, day: Int, hour: Int, minute: Int): Instant =
    LocalDateTime.of(year, month, day, hour, minute).atZone(TaiwanTime.zone).toInstant()

/** `publish_time` as the API sends it: Taiwan local time, no zone. */
fun publishTime(instant: Instant): String =
    DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss").format(instant.atZone(TaiwanTime.zone))

fun reading(
    stationId: Int = 1,
    aqi: Double,
    pm25: Double = 10.0,
    publishTime: String = "",
    latitude: Double? = null,
    longitude: Double? = null
) = WatchReading(
    stationId = stationId, code = "S$stationId", name = "Station", nameLocal = "測站",
    aqi = aqi, pm25 = pm25, pm10 = 20.0, o3 = 30.0, co = 0.3, so2 = 1.0, no2 = 10.0,
    windDirection = 0.0, windSpeed = 1.0, publishTime = publishTime, latitude = latitude, longitude = longitude
)
