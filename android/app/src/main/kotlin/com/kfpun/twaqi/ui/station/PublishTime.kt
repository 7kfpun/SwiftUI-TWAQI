package com.kfpun.twaqi.ui.station

import android.text.format.DateUtils
import com.kfpun.twaqi.data.model.TaiwanTime
import java.time.Instant
import java.time.chrono.IsoChronology
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

/**
 * MOENV publish times as the station page shows them (iOS `asPublishTime`, `asPublishDateTime`,
 * `asRelativeAge`). They are Taiwan wall-clock times, so they are shown in `Asia/Taipei`.
 */
object PublishTime {
    private val hourMinute: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")

    /** `"2026-08-07T22:00:00"` → `"22:00"`; the raw text when it doesn't parse. */
    fun time(publishTime: String): String {
        val instant = TaiwanTime.parsePublishTime(publishTime) ?: return publishTime
        return hourMinute.format(instant.atZone(TaiwanTime.zone))
    }

    /**
     * `"Aug 7, 2026, 22:00"` in [locale], always on the Gregorian calendar (iOS showed 佛曆 2569 to
     * readers on the Buddhist calendar until it was pinned).
     */
    fun dateTime(publishTime: String, locale: Locale): String {
        val instant = TaiwanTime.parsePublishTime(publishTime) ?: return publishTime
        val formatter = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
            .withLocale(locale)
            .withChronology(IsoChronology.INSTANCE)
        return formatter.format(instant.atZone(TaiwanTime.zone))
    }

    /** "2 hours ago"; empty when the time doesn't parse. */
    fun age(publishTime: String, now: Instant = Instant.now()): String {
        val instant = TaiwanTime.parsePublishTime(publishTime) ?: return ""
        return DateUtils.getRelativeTimeSpanString(
            instant.toEpochMilli(),
            now.toEpochMilli(),
            DateUtils.MINUTE_IN_MILLIS,
            DateUtils.FORMAT_ABBREV_RELATIVE
        ).toString()
    }
}
