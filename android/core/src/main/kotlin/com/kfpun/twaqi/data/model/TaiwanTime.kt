package com.kfpun.twaqi.data.model

import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/**
 * Taiwan-local times and days. MOENV publish times and forecast dates are Taiwan wall-clock
 * values without a zone, so they are always read in `Asia/Taipei`, never the device zone.
 */
object TaiwanTime {
    val zone: ZoneId = ZoneId.of("Asia/Taipei")

    private val day: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
    private val dateTime: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")

    /** Today in Taiwan, `YYYY-MM-DD`. */
    fun today(now: Instant = Instant.now()): String = day.format(now.atZone(zone))

    fun parseDay(value: String): LocalDate? = runCatching { LocalDate.parse(value.take(10), day) }.getOrNull()

    /**
     * `"2026-10-31 16:30:00"` or `"2026-11-06T00:00:00"`, tolerating missing seconds, in Taiwan
     * time. Null when it doesn't parse.
     */
    fun parsePublishTime(value: String): Instant? {
        var text = value.trim().replace('T', ' ')
        if (text.length == 16) text += ":00"
        if (text.length < 19) return null
        return runCatching { LocalDateTime.parse(text.take(19), dateTime).atZone(zone).toInstant() }.getOrNull()
    }

    /** Whole days from today to [date]: 0 today, 1 tomorrow. */
    fun daysFromToday(date: String, now: Instant = Instant.now()): Int? {
        val target = parseDay(date) ?: return null
        val today = parseDay(today(now)) ?: return null
        return ChronoUnit.DAYS.between(today, target).toInt()
    }
}
