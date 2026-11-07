package com.kfpun.twaqi.ui.forecast

import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.TaiwanTime
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

/**
 * How the forecast cards write their dates (iOS `AreaForecastView`'s static formatters). Every
 * date is a Taiwan day or a Taiwan wall-clock time, never the device zone.
 */
object ForecastFormat {
    private val hourMinute: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm", Locale.US)
    private val monthDayTime: DateTimeFormatter = DateTimeFormatter.ofPattern("M/d HH:mm", Locale.US)

    /** 今天 / 明天 / 後天, else the weekday. [getString] is the app-language `Context.getString`. */
    fun dayTitle(forecastDate: String, now: Instant, locale: Locale, getString: (Int) -> String): String =
        when (TaiwanTime.daysFromToday(forecastDate, now)) {
            0 -> getString(R.string.forecast_today)

            1 -> getString(R.string.forecast_tomorrow)

            2 -> getString(R.string.forecast_day_after_tomorrow)

            else -> TaiwanTime.parseDay(forecastDate)?.dayOfWeek?.getDisplayName(TextStyle.FULL, locale)
                ?: forecastDate
        }

    /** 「11/1（日）」 / "Sun, 11/1": the month, day and short weekday in the app's language. */
    fun dateSubtitle(forecastDate: String, locale: Locale): String {
        val day = TaiwanTime.parseDay(forecastDate) ?: return forecastDate
        return if (locale.language == "zh") {
            "${day.monthValue}/${day.dayOfMonth}（${day.dayOfWeek.getDisplayName(TextStyle.NARROW, locale)}）"
        } else {
            "${day.dayOfWeek.getDisplayName(TextStyle.SHORT, locale)}, ${day.monthValue}/${day.dayOfMonth}"
        }
    }

    /** "16:30" when published today (Taiwan time), else "10/30 22:30". */
    fun publishedText(published: Instant, now: Instant): String {
        val at = published.atZone(TaiwanTime.zone)
        return if (at.toLocalDate() == now.atZone(TaiwanTime.zone).toLocalDate()) {
            hourMinute.format(at)
        } else {
            monthDayTime.format(at)
        }
    }
}
