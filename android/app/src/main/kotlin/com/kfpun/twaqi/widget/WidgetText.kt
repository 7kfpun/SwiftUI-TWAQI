package com.kfpun.twaqi.widget

import android.content.Context
import androidx.annotation.StringRes
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.model.TaiwanTime
import com.kfpun.twaqi.locale.AppLocale
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Every piece of widget text, in the app's language (FOX-56): a widget has no activity, so it
 * reads its strings from [AppLocale.localizedContext], or it would show the phone's language
 * below Android 13 (the iOS widget bug FOX-42).
 */
class WidgetText(private val localized: Context, val chinese: Boolean) {
    fun string(@StringRes id: Int): String = localized.getString(id)

    fun string(@StringRes id: Int, vararg args: Any): String = localized.getString(id, *args)

    fun status(status: AirStatus): String = string(status.label)

    fun name(reading: Pollutant): String = reading.displayName(chinese)

    /** "Updated 11/6 14:00" (Taiwan time, as published), or "Offline · saved 11/6 14:05" after a failed refresh. */
    fun updatedLine(reading: Pollutant, offline: Boolean, savedAt: Instant?): String? {
        if (offline && savedAt != null) {
            return string(com.kfpun.twaqi.R.string.widget_offline_saved_at, WidgetFormat.dateTime(savedAt))
        }
        val published = reading.publishedAt ?: return reading.publishTime.takeIf { it.isNotBlank() }
        return string(com.kfpun.twaqi.R.string.widget_updated_at, WidgetFormat.dateTime(published))
    }

    companion object {
        fun of(context: Context): WidgetText =
            WidgetText(AppLocale.localizedContext(context), AppLocale.isChinese(context))
    }
}

/** Numbers and times as widgets show them. Taiwan-local values are shown in `Asia/Taipei`, whatever the phone's zone. */
object WidgetFormat {
    private val dateTime: DateTimeFormatter = DateTimeFormatter.ofPattern(
        "M/d HH:mm",
        Locale.US
    ).withZone(TaiwanTime.zone)
    private val hour: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm", Locale.US).withZone(TaiwanTime.zone)
    private val day: DateTimeFormatter = DateTimeFormatter.ofPattern("M/d", Locale.US)

    fun dateTime(instant: Instant): String = dateTime.format(instant)

    fun hour(instant: Instant): String = hour.format(instant)

    /** "M/d" of a `YYYY-MM-DD` forecast date. */
    fun day(date: String): String = TaiwanTime.parseDay(date)?.let(day::format) ?: date

    /** The value in its index's decimals; a station that doesn't measure it reads 0 and shows a dash. */
    fun value(reading: Pollutant, type: AirIndexType): String {
        val value = reading.value(type)
        return if (value > 0) type.format(value) else "—"
    }

    /** Below this, in m/s, the wind is calm (Beaufort 0). */
    const val CALM_WIND = 0.5
}
