package com.kfpun.twaqi.ui.main

import com.kfpun.twaqi.data.model.HistoricalPollutant
import java.util.TimeZone
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** The timeline's hours are Taiwan's (`Asia/Taipei`), whatever zone the phone is in. */
class MapTimelineTest {
    private lateinit var deviceZone: TimeZone

    @Before
    fun setUp() {
        deviceZone = TimeZone.getDefault()
        // A device far from Taiwan, with daylight saving: none of it may leak into the hours.
        TimeZone.setDefault(TimeZone.getTimeZone("America/Los_Angeles"))
    }

    @After
    fun tearDown() {
        TimeZone.setDefault(deviceZone)
    }

    @Test
    fun publishTimesSnapToTheirTaiwanHour() {
        assertEquals("2026-11-06T14:00:00", MapTimeline.hourKey("2026-11-06T14:00:00"))
        assertEquals("2026-11-06T14:00:00", MapTimeline.hourKey("2026-11-06 14:37:12"))
        assertEquals("2026-11-06T14:00:00", MapTimeline.hourKey("2026-11-06T14:59"))
        // Fractional seconds or a suffix: the first 19 characters are the wall-clock time.
        assertEquals("2026-11-06T14:00:00", MapTimeline.hourKey("2026-11-06T14:05:00.000"))
        assertNull(MapTimeline.hourKey("yesterday"))
    }

    @Test
    fun hourArithmeticCrossesMidnight() {
        assertEquals("2026-11-05T23:00:00", MapTimeline.publishTime("2026-11-06T00:00:00", 1))
        assertEquals("2026-11-05T22:00:00", MapTimeline.publishTime("2026-11-06T01:30:00", 3))
        assertEquals("2026-11-05T01:00:00", MapTimeline.publishTime("2026-11-06T01:00:00", 24))
        // Across a month and a year.
        assertEquals("2026-10-31T23:00:00", MapTimeline.publishTime("2026-11-01T00:00:00", 1))
        assertEquals("2026-12-31T22:00:00", MapTimeline.publishTime("2027-01-01T02:00:00", 4))
        assertEquals("2026-11-06T09:00:00", MapTimeline.publishTime("2026-11-06T09:00:00", 0))
    }

    /** US daylight saving ends on 2026-11-01; Taiwan has none, so every step is one hour. */
    @Test
    fun deviceDaylightSavingDoesNotSkipOrRepeatHours() {
        val hours = MapTimeline.hours("2026-11-01T20:00:00")
        assertEquals(hours.size, hours.toSet().size)
        assertEquals("2026-10-31T20:00:00", hours.first())
    }

    @Test
    fun hourListRunsOldestToLatest() {
        val hours = MapTimeline.hours("2026-11-06T02:00:00")
        assertEquals(MapTimeline.HOURS + 1, hours.size)
        assertEquals("2026-11-05T02:00:00", hours[0])
        assertEquals("2026-11-05T23:00:00", hours[21])
        assertEquals("2026-11-06T00:00:00", hours[22])
        assertEquals("2026-11-06T02:00:00", hours[MapTimeline.HOURS])
        // Every position names the hour publishTime gives for it.
        hours.forEachIndexed { index, hour ->
            assertEquals(MapTimeline.publishTime("2026-11-06T02:00:00", MapTimeline.hoursAgo(index)), hour)
        }
        assertTrue(MapTimeline.hours("not a time").isEmpty())
    }

    @Test
    fun indexAndHoursAgoMirror() {
        assertEquals(24, MapTimeline.index(0))
        assertEquals(0, MapTimeline.index(24))
        assertEquals(21, MapTimeline.index(3))
        assertEquals(3, MapTimeline.hoursAgo(21))
        assertEquals(0, MapTimeline.hoursAgo(30))
        assertEquals(24, MapTimeline.hoursAgo(-2))
    }

    @Test
    fun describeFlagsTheDayBeforeInTaiwan() {
        assertEquals(
            TimelineHour("02:00", yesterday = false, hoursAgo = 0),
            MapTimeline.describe("2026-11-06T02:00:00", 0)
        )
        assertEquals(
            TimelineHour("00:00", yesterday = false, hoursAgo = 2),
            MapTimeline.describe("2026-11-06T02:00:00", 2)
        )
        assertEquals(
            TimelineHour("23:00", yesterday = true, hoursAgo = 3),
            MapTimeline.describe("2026-11-06T02:00:00", 3)
        )
        assertEquals(
            TimelineHour("17:00", yesterday = true, hoursAgo = 24),
            MapTimeline.describe("2026-11-06T17:00:00", 24)
        )
        assertNull(MapTimeline.describe("", 1))
    }

    @Test
    fun tickLabelsEverySixHoursWithTheDateAtMidnight() {
        // Anchor 14:00: index i is 24 - i hours back.
        val ticks = MapTimeline.tickLabels("2026-11-06T14:00:00")
        assertEquals(
            listOf(
                TimelineTick(4, "18:00"),
                TimelineTick(10, "11/6"),
                // 12:00 at index 22 is too close to "Now".
                TimelineTick(16, "06:00")
            ),
            ticks
        )
        // Nothing within three hours of either end, where it would overlap "Now" or the edge.
        val nearEnds = MapTimeline.tickLabels("2026-11-06T00:00:00")
        assertTrue(nearEnds.all { it.index in 3..21 })
        assertEquals(listOf(6, 12, 18), nearEnds.map { it.index })
        assertFalse(nearEnds.any { it.text == "11/6" })
    }

    @Test
    fun anchorIsTheLatestPublishTime() {
        val stations = listOf(
            pollutant(1).copy(publishTime = "2026-11-06T13:00:00"),
            pollutant(2).copy(publishTime = "2026-11-06 14:00:00"),
            pollutant(3).copy(publishTime = "")
        )
        assertEquals("2026-11-06 14:00:00", MapTimeline.anchor(stations))
        assertNull(MapTimeline.anchor(emptyList()))
    }

    @Test
    fun anEarlierHourTakesItsValuesFromHistory() {
        val live = pollutant(7, aqi = 40.0).copy(windDirection = 90.0, windSpeed = 3.0)
        val reading = HistoricalPollutant(120.0, 30.0, 50.0, 8.0, 2.0, 0.5, 40.0, 200.0, 5.5, "2026-11-06T10:00:00")
        val then = live.at("2026-11-06T10:00:00", reading)
        assertEquals(120.0, then.aqi, 0.0)
        assertEquals(200.0, then.windDirection, 0.0)
        assertEquals(5.5, then.windSpeed, 0.0)
        assertEquals("2026-11-06T10:00:00", then.publishTime)
        assertEquals(live.name, then.name)
        assertEquals(live.lat, then.lat, 0.0)

        // No reading: every value 0, a grey "-", stamped with the hour.
        val missing = live.at("2026-11-06T09:00:00", null)
        assertEquals(0.0, missing.aqi, 0.0)
        assertEquals(0.0, missing.windSpeed, 0.0)
        assertEquals("2026-11-06T09:00:00", missing.publishTime)
    }
}
