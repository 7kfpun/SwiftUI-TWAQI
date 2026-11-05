package com.kfpun.twaqi.ui.forecast

import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.ForecastTabArea
import java.time.Instant
import java.util.Locale
import java.util.TimeZone
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

/** The cards' dates are Taiwan days and Taiwan times, whatever zone the phone is in (iOS `AreaForecastView`). */
class ForecastFormatTest {
    private val original = TimeZone.getDefault()

    private val strings = mapOf(
        R.string.forecast_today to "Today",
        R.string.forecast_tomorrow to "Tomorrow",
        R.string.forecast_day_after_tomorrow to "In 2 days"
    )

    @Before
    fun setUp() {
        // A phone in California: its own day would be a day behind Taiwan's in these tests.
        TimeZone.setDefault(TimeZone.getTimeZone("America/Los_Angeles"))
    }

    @After
    fun tearDown() {
        TimeZone.setDefault(original)
    }

    private fun title(date: String, now: Instant) = ForecastFormat.dayTitle(date, now, Locale.ENGLISH) { strings[it]!! }

    @Test
    fun dayTitlesTurnOverAtTaiwanMidnight() {
        // 23:59 on 5 November in Taiwan.
        val before = Instant.parse("2026-11-05T15:59:00Z")
        assertEquals("Today", title("2026-11-05", before))
        assertEquals("Tomorrow", title("2026-11-06", before))
        assertEquals("In 2 days", title("2026-11-07", before))
        assertEquals("Sunday", title("2026-11-08", before))

        // A minute later it is 6 November in Taiwan, still the 5th in California.
        val after = Instant.parse("2026-11-05T16:00:00Z")
        assertEquals("Today", title("2026-11-06", after))
        assertEquals("Tomorrow", title("2026-11-07", after))
        assertEquals("In 2 days", title("2026-11-08", after))
    }

    @Test
    fun weekdayInTheAppLanguage() {
        val now = Instant.parse("2026-11-05T04:00:00Z")
        assertEquals("星期日", ForecastFormat.dayTitle("2026-11-08", now, Locale.TRADITIONAL_CHINESE) { "" })
        // Not a date: shown as sent.
        assertEquals("soon", title("soon", now))
    }

    @Test
    fun dateSubtitleInEachLanguage() {
        assertEquals("Sun, 11/1", ForecastFormat.dateSubtitle("2026-11-01", Locale.ENGLISH))
        assertEquals("11/1（日）", ForecastFormat.dateSubtitle("2026-11-01", Locale.TRADITIONAL_CHINESE))
        assertEquals("bad", ForecastFormat.dateSubtitle("bad", Locale.ENGLISH))
    }

    @Test
    fun publishedTimeIsTaiwanTimeAndOnlyTheTimeWhenToday() {
        // Published 22:00 on 5 November, Taiwan time.
        val published = Instant.parse("2026-11-05T14:00:00Z")
        assertEquals("22:00", ForecastFormat.publishedText(published, Instant.parse("2026-11-05T15:59:00Z")))
        // Past Taiwan midnight it was yesterday's, though still the 5th in California.
        assertEquals("11/5 22:00", ForecastFormat.publishedText(published, Instant.parse("2026-11-05T16:00:00Z")))
    }

    @Test
    fun onlyTheReaderAndFavouriteZonesAreTagged() {
        assertEquals(R.string.forecast_your_area, tag(ForecastTabArea.Pin.READER))
        assertEquals(R.string.forecast_favourite_area, tag(ForecastTabArea.Pin.FAVOURITE))
        assertNull(tag(ForecastTabArea.Pin.FALLBACK))
        assertNull(tag(ForecastTabArea.Pin.NONE))
    }

    @Test
    fun translationLanguageIsNoneInChinese() {
        assertNull(translationLanguage(chinese = true, locale = Locale.TRADITIONAL_CHINESE))
        assertEquals("en", translationLanguage(chinese = false, locale = Locale.US))
    }
}
