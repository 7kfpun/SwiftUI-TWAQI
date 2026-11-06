package com.kfpun.twaqi.widget

import com.kfpun.twaqi.data.model.AqiForecast
import com.kfpun.twaqi.data.model.HistoricalPollutant
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.model.TaiwanTime
import java.time.Duration
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * The made-up stations the widget picker's previews draw (FOX-120, iOS `WatchReading.placeholder`,
 * `placeholderFavourites` and `WidgetStationDetail.placeholder`): bundled here, never fetched, so
 * a preview is there before the app has ever loaded a reading. Each station carries its English and
 * Chinese names, as the API's readings do, so the preview follows the app language.
 *
 * The ids are not real station ids (iOS uses the same 0, -1, -2, -3), so nothing here can be
 * mistaken for a saved reading.
 */
object WidgetPreviewData {
    /** The station the preview leads with: 松山, AQI 42 (Good). */
    val leading: Pollutant = Pollutant(
        stationId = 0, code = "Songshan", lat = 25.05, lon = 121.578,
        aqi = 42.0, pm25 = 9.0, pm10 = 21.0, no2 = 12.5, so2 = 1.4, co = 0.32, o3 = 31.2,
        windDirection = 247.0, windSpeed = 2.6, publishTime = "",
        name = "Songshan", nameLocal = "松山",
        area = "North", areaLocal = "北部空品區", county = "Taipei City", countyLocal = "臺北市"
    )

    /** The favourites listed under it, in the reader's order: Moderate, Good, and Unhealthy for sensitive groups. */
    val favourites: List<Pollutant> = listOf(
        Pollutant(
            stationId = -1, code = "Banqiao", lat = 25.013, lon = 121.459,
            aqi = 58.0, pm25 = 17.0, pm10 = 34.0, no2 = 16.1, so2 = 1.9, co = 0.41, o3 = 38.5,
            windDirection = 210.0, windSpeed = 1.8, publishTime = "",
            name = "Banqiao", nameLocal = "板橋",
            area = "North", areaLocal = "北部空品區", county = "New Taipei City", countyLocal = "新北市"
        ),
        Pollutant(
            stationId = -2, code = "Hsinchu", lat = 24.806, lon = 120.972,
            aqi = 35.0, pm25 = 8.0, pm10 = 19.0, no2 = 9.4, so2 = 1.1, co = 0.25, o3 = 29.7,
            windDirection = 30.0, windSpeed = 4.2, publishTime = "",
            name = "Hsinchu", nameLocal = "新竹",
            area = "Chu-Miao", areaLocal = "竹苗空品區", county = "Hsinchu City", countyLocal = "新竹市"
        ),
        Pollutant(
            stationId = -3, code = "Tainan", lat = 22.985, lon = 120.202,
            aqi = 104.0, pm25 = 37.0, pm10 = 61.0, no2 = 18.8, so2 = 2.6, co = 0.48, o3 = 52.3,
            windDirection = 340.0, windSpeed = 2.1, publishTime = "",
            name = "Tainan", nameLocal = "臺南",
            area = "Yun-Chia-Nan", areaLocal = "雲嘉南空品區", county = "Tainan City", countyLocal = "臺南市"
        )
    )

    /** 松山's AQI over the last 24 hours, oldest first, easing down to the 42 it reads now. */
    private val historyAqi = listOf(
        61, 64, 66, 63, 60, 58, 55, 54, 52, 50, 49, 51,
        53, 52, 50, 48, 47, 46, 45, 44, 43, 42, 42, 42
    )

    private val hourFormat: DateTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:00:00", Locale.US).withZone(TaiwanTime.zone)

    /** The leading station's last 24 hours, ending at the hour [now] is in (Taiwan time). */
    fun history(now: Instant): List<HistoricalPollutant> = historyAqi.mapIndexed { hour, aqi ->
        val value = aqi.toDouble()
        HistoricalPollutant(
            aqi = value, pm25 = value * 0.25, pm10 = value * 0.5, no2 = value * 0.3, so2 = 1.4,
            co = 0.32, o3 = value * 0.7, windDirection = 247.0, windSpeed = 2.6,
            publishTime = hourFormat.format(now.minus(Duration.ofHours((historyAqi.size - 1 - hour).toLong())))
        )
    }

    /** Today's and tomorrow's 北部 forecast (Taiwan days of [now]): Good, then Moderate with PM2.5. */
    fun forecasts(now: Instant): List<AqiForecast> = listOf(
        AqiForecast(area = "北部", forecastDate = TaiwanTime.today(now), aqi = 48),
        AqiForecast(
            area = "北部",
            forecastDate = TaiwanTime.today(now.plus(Duration.ofDays(1))),
            aqi = 72,
            majorPollutant = "細懸浮微粒"
        )
    )

    /**
     * What a preview draws from: the sample stations, as a free user (the preview unlocks the Pro
     * sizes by itself, [entry]), with the forecast and, for station detail, the history. No cam:
     * there is no frame to show (as on iOS).
     */
    fun snapshot(now: Instant): WidgetSnapshot {
        val readings = (listOf(leading) + favourites).associateBy { it.stationId }
        return WidgetSnapshot(
            config = WidgetConfig(),
            leadingId = leading.stationId,
            favouriteIds = favourites.map { it.stationId },
            readings = readings,
            savedAt = emptyMap(),
            isPro = false,
            forecasts = forecasts(now),
            history = history(now)
        )
    }

    /**
     * The entry a preview of [family] draws: [WidgetEntry.make] with `isPreview`, so the Pro sizes
     * show what they do rather than the locked placeholder (iOS `context.isPreview`).
     */
    fun entry(family: WidgetFamily, snapshot: WidgetSnapshot, now: Instant): WidgetEntry = WidgetEntry.make(
        family = family,
        leading = snapshot.leading,
        config = snapshot.config,
        favouriteIds = snapshot.favouriteIds,
        readings = snapshot.readings,
        isPro = snapshot.isPro,
        state = WidgetPageState(),
        now = now,
        isPreview = true
    )
}
