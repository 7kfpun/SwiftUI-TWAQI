package com.kfpun.twaqi.ui.station.cam

import android.icu.text.DisplayContext
import android.icu.text.RelativeDateTimeFormatter
import android.icu.util.ULocale
import com.kfpun.twaqi.data.cams.StationCamHour
import java.time.Duration
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.Locale

/** The cam's times as the station page shows them: Taiwan clock time, like every other time there. */
object CamTime {
    private val hourMinute: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")

    /** `"22:30"` in `Asia/Taipei`, whatever the phone's zone. */
    fun clock(instant: Instant): String = hourMinute.format(instant.atZone(StationCamHour.ZONE))

    enum class Unit { NOW, MINUTES, HOURS, DAYS }

    /**
     * The largest whole unit between [date] and [now], as iOS `RelativeDateTimeFormatter` picks
     * it: under a minute is "now". The count is negative for a date after [now].
     */
    fun relativeUnit(date: Instant, now: Instant): Pair<Unit, Long> {
        val seconds = Duration.between(date, now).seconds
        val magnitude = kotlin.math.abs(seconds)
        val sign = if (seconds < 0) -1 else 1
        return when {
            magnitude < 60 -> Unit.NOW to 0L
            magnitude < 3_600 -> Unit.MINUTES to sign * (magnitude / 60)
            magnitude < 86_400 -> Unit.HOURS to sign * (magnitude / 3_600)
            else -> Unit.DAYS to sign * (magnitude / 86_400)
        }
    }

    /** "36 min. ago" in [locale] (the in-app language), short style as on iOS. */
    fun relative(date: Instant, now: Instant, locale: Locale): String {
        val formatter = RelativeDateTimeFormatter.getInstance(
            ULocale.forLocale(locale),
            null,
            RelativeDateTimeFormatter.Style.SHORT,
            DisplayContext.CAPITALIZATION_NONE
        )
        val (unit, count) = relativeUnit(date, now)
        val relativeUnit = when (unit) {
            Unit.NOW -> return formatter.format(
                RelativeDateTimeFormatter.Direction.PLAIN,
                RelativeDateTimeFormatter.AbsoluteUnit.NOW
            )

            Unit.MINUTES -> RelativeDateTimeFormatter.RelativeUnit.MINUTES

            Unit.HOURS -> RelativeDateTimeFormatter.RelativeUnit.HOURS

            Unit.DAYS -> RelativeDateTimeFormatter.RelativeUnit.DAYS
        }
        val direction = when {
            count < 0 -> RelativeDateTimeFormatter.Direction.NEXT
            else -> RelativeDateTimeFormatter.Direction.LAST
        }
        return formatter.format(kotlin.math.abs(count).toDouble(), direction, relativeUnit)
    }
}
