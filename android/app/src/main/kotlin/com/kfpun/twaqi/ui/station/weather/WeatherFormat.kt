package com.kfpun.twaqi.ui.station.weather

import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.TaiwanTime
import com.kfpun.twaqi.data.weather.WeatherDates
import com.kfpun.twaqi.data.weather.WeatherPeriod
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.roundToInt

/**
 * How the weather card writes its values (iOS `StationWeatherView`'s static formatters). Times are
 * Taiwan time, never the device zone.
 */
object WeatherFormat {
    private val hourMinute: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm", Locale.US)
    private val monthDay: DateTimeFormatter = DateTimeFormatter.ofPattern("M/d", Locale.US)

    /**
     * 今天 / 明天 / 後天, else the weekday, for the Taiwan day the period starts on. The period
     * running now is 今天, even between 00:00 and 06:00 when the 18:00–06:00 period started the
     * day before. [getString] is the app-language `Context.getString`.
     */
    fun dayTitle(period: WeatherPeriod, now: Instant, locale: Locale, getString: (Int) -> String): String {
        val start = period.startInstant ?: return ""
        val end = period.endInstant
        if (start <= now && end != null && now < end) return getString(R.string.forecast_today)
        return when (TaiwanTime.daysFromToday(WeatherDates.day(start), now)) {
            0 -> getString(R.string.forecast_today)
            1 -> getString(R.string.forecast_tomorrow)
            2 -> getString(R.string.forecast_day_after_tomorrow)
            else -> start.atZone(TaiwanTime.zone).dayOfWeek.getDisplayName(TextStyle.FULL, locale)
        }
    }

    /**
     * 「18:00–06:00」, Taiwan time. A period that ends on another Taiwan day than it starts gets the
     * start date in front (「11/4 18:00–06:00」), so the night in progress reads differently from
     * tonight's.
     */
    fun timeRange(period: WeatherPeriod): String {
        val from = period.startInstant?.atZone(TaiwanTime.zone)
        val to = period.endInstant?.atZone(TaiwanTime.zone)
        val text = "${from?.let(hourMinute::format) ?: "—"}–${to?.let(hourMinute::format) ?: "—"}"
        return if (from != null && to != null && from.toLocalDate() != to.toLocalDate()) {
            "${monthDay.format(from)} $text"
        } else {
            text
        }
    }

    /** 「24°」, rounded; 「—」 when missing. */
    fun temperature(value: Double?): String = value?.let { "${roundHalfAwayFromZero(it)}°" } ?: "—"

    /** 「21–27°」; one side missing shows just the other. */
    fun temperatureRange(min: Double?, max: Double?): String = when {
        min != null && max != null -> "${roundHalfAwayFromZero(min)}–${roundHalfAwayFromZero(max)}°"
        else -> temperature(min ?: max)
    }

    fun percent(value: Double?): String = value?.let { "${roundHalfAwayFromZero(it)}%" } ?: "—"

    fun millimetres(value: Double?): String = value?.let { String.format(Locale.US, "%.1f mm", it) } ?: "—"

    fun windSpeed(value: Double?): String = value?.let { String.format(Locale.US, "%.1f m/s", it) } ?: "—"

    /** Swift's `rounded()`: halves away from zero (-2.5 → -3); -0.4 is 「0」, as an Int has no -0. */
    private fun roundHalfAwayFromZero(value: Double): Int =
        if (value < 0) -(-value).roundToInt() else value.roundToInt()
}
