package com.kfpun.twaqi.data.model

import java.time.Instant

/**
 * One station's current reading from `/v1/current-pollutants` (iOS `Pollutant`).
 *
 * [publishTime] is Taiwan local time without a zone, as the API sends it; [publishedAt] reads it
 * in `Asia/Taipei`.
 */
data class Pollutant(
    val stationId: Int,
    val code: String,
    val lat: Double,
    val lon: Double,
    val aqi: Double,
    val pm25: Double,
    val pm10: Double,
    val no2: Double,
    val so2: Double,
    val co: Double,
    val o3: Double,
    val windDirection: Double,
    val windSpeed: Double,
    val publishTime: String,
    val name: String,
    val nameLocal: String,
    val address: String? = null,
    val area: String? = null,
    val areaLocal: String? = null,
    val county: String? = null,
    val countyLocal: String? = null,
    val township: String? = null,
    val stationType: StationType = StationType.UNKNOWN,
    val imageUrl: String? = null
) {
    fun value(type: AirIndexType): Double = when (type) {
        AirIndexType.AQI -> aqi
        AirIndexType.PM25 -> pm25
        AirIndexType.PM10 -> pm10
        AirIndexType.NO2 -> no2
        AirIndexType.SO2 -> so2
        AirIndexType.CO -> co
        AirIndexType.O3 -> o3
    }

    fun status(type: AirIndexType = AirIndexType.AQI): AirStatus = AirStatus.of(type, value(type))

    val publishedAt: Instant? get() = TaiwanTime.parsePublishTime(publishTime)

    fun displayName(chinese: Boolean = AppLocale.isChinese()): String =
        StationText.displayName(if (chinese) nameLocal else name, code, stationId)

    fun displayLocality(chinese: Boolean = AppLocale.isChinese(), translate: (String) -> String = { it }): String? =
        StationText.locality(township?.let(translate), if (chinese) countyLocal else county)

    fun displayArea(chinese: Boolean = AppLocale.isChinese()): String? =
        (if (chinese) areaLocal else area)?.takeIf { it.isNotEmpty() }

    /** `"25.129167, 121.760056"` */
    val coordinateText: String get() = String.format(java.util.Locale.US, "%.6f, %.6f", lat, lon)
}

/** One hour of a station's history from `/v1/historical-pollutants` (iOS `HistoricalPollutant`). */
data class HistoricalPollutant(
    val aqi: Double,
    val pm25: Double,
    val pm10: Double,
    val no2: Double,
    val so2: Double,
    val co: Double,
    val o3: Double,
    val windDirection: Double,
    val windSpeed: Double,
    val publishTime: String
) {
    fun value(type: AirIndexType): Double = when (type) {
        AirIndexType.AQI -> aqi
        AirIndexType.PM25 -> pm25
        AirIndexType.PM10 -> pm10
        AirIndexType.NO2 -> no2
        AirIndexType.SO2 -> so2
        AirIndexType.CO -> co
        AirIndexType.O3 -> o3
    }

    val publishedAt: Instant? get() = TaiwanTime.parsePublishTime(publishTime)
}

/** `/v1/historical-pollutants`: the station and its readings, oldest first. */
data class StationHistory(val station: Station, val readings: List<HistoricalPollutant>)
