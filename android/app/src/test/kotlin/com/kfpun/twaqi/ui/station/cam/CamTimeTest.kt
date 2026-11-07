package com.kfpun.twaqi.ui.station.cam

import java.time.Instant
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Test

class CamTimeTest {
    private val now = Instant.parse("2026-10-30T15:06:00Z")

    /** The capture time is Taiwan clock time, whatever the phone's zone. */
    @Test
    fun clockIsTaiwanTime() {
        val zone = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("America/Los_Angeles"))
            assertEquals("22:30", CamTime.clock(Instant.parse("2026-10-30T14:30:00Z")))
            assertEquals("00:05", CamTime.clock(Instant.parse("2026-10-31T16:05:00Z")))
        } finally {
            TimeZone.setDefault(zone)
        }
    }

    @Test
    fun relativeUnitIsTheLargestWholeOne() {
        assertEquals(CamTime.Unit.NOW to 0L, CamTime.relativeUnit(now.minusSeconds(30), now))
        assertEquals(CamTime.Unit.MINUTES to 36L, CamTime.relativeUnit(Instant.parse("2026-10-30T14:30:00Z"), now))
        assertEquals(CamTime.Unit.HOURS to 23L, CamTime.relativeUnit(now.minusSeconds(23 * 3_600 + 59 * 60), now))
        assertEquals(CamTime.Unit.DAYS to 1L, CamTime.relativeUnit(now.minusSeconds(86_400), now))
        assertEquals(CamTime.Unit.MINUTES to -5L, CamTime.relativeUnit(now.plusSeconds(300), now))
    }
}
