package com.kfpun.twaqi.ui.main

import android.text.format.DateUtils
import com.kfpun.twaqi.data.model.TaiwanTime
import java.time.Instant
import java.time.format.DateTimeFormatter

/** How a reading's publish time is shown. Taiwan wall-clock time, never the device zone. */
object PublishTimes {
    private val clock = DateTimeFormatter.ofPattern("HH:mm").withZone(TaiwanTime.zone)

    /** "14:00" */
    fun clock(instant: Instant): String = clock.format(instant)

    /** "2 hr. ago", in the app language. */
    fun relativeAge(instant: Instant, now: Instant = Instant.now()): String = DateUtils.getRelativeTimeSpanString(
        instant.toEpochMilli(),
        now.toEpochMilli(),
        DateUtils.MINUTE_IN_MILLIS,
        DateUtils.FORMAT_ABBREV_RELATIVE
    ).toString()
}
