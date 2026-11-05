package com.kfpun.twaqi.data.cams

import com.kfpun.twaqi.data.Fixtures
import java.time.Duration
import java.time.Instant
import java.time.OffsetDateTime
import java.util.TimeZone
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ported from iOS `StationCamTests` (in the CI subset there): the manifest, the join, and the hour keys. */
class StationCamTest {
    private val cams: List<StationCam> = requireNotNull(StationCamManifest.parse(Fixtures.stationCamsManifest))
    private val endpoints = StationCamEndpoints("https://cams.example.com")
    private val deviceZone: TimeZone = TimeZone.getDefault()

    @After
    fun restoreZone() {
        TimeZone.setDefault(deviceZone)
    }

    /** Taiwan is UTC+8 with no DST; this reads any offset. */
    private fun date(iso: String): Instant = OffsetDateTime.parse(iso).toInstant()

    @Test
    fun decodesManifestKeyedBySiteId() {
        assertEquals(listOf("001", "057", "088", "204"), cams.map { it.siteId })
        assertEquals("基隆", cams.first().name)
        assertEquals(date("2026-10-30T22:30:00+08:00"), cams.first().capturedAt)
    }

    @Test
    fun anythingButAManifestIsNull() {
        assertNull(StationCamManifest.parse("<html>"))
        assertNull(StationCamManifest.parse("""{"updatedAt": "x"}"""))
    }

    /** 基隆 is station 91 in the AQI API and 001 at MOENV. The URL must carry 001. */
    @Test
    fun imageUrlUsesMoenvSiteId() {
        val cam = StationCamMatcher.match("基隆", 25.129167, 121.760056, cams)
        assertEquals("001", cam?.siteId)
        assertEquals("/stations/001.jpg", endpoints.latest(cam!!)?.encodedPath)
        assertEquals("cams.example.com", endpoints.latest(cam)?.host)
    }

    @Test
    fun imageUrlIsVersionedByCaptureTime() {
        val url = endpoints.latest(cams[0])!!
        assertEquals("2026-10-30T22:30:00+08:00", url.queryParameter("t"))
    }

    @Test
    fun noConfiguredHostMeansNoUrls() {
        val none = StationCamEndpoints("")
        assertNull(none.manifest)
        assertNull(none.latest(cams[0]))
        assertNull(none.hour(StationCamHour("001", date("2026-10-30T22:00:00+08:00"))))
    }

    @Test
    fun matchesByNameEvenWhenCoordinatesDisagree() {
        assertEquals("001", StationCamMatcher.match("基隆", 0.0, 0.0, cams)?.siteId)
    }

    /** The name wins even when another cam sits closer to the station's coordinates. */
    @Test
    fun nameIsCheckedBeforeDistance() {
        val keelung = cams.first { it.siteId == "001" }
        assertEquals("057", StationCamMatcher.match("前鎮", keelung.lat, keelung.lon, cams)?.siteId)
    }

    @Test
    fun nameMatchIgnoresParenthesisWidthAndTaiVariant() {
        assertEquals("204", StationCamMatcher.match("屏東(琉球)", 0.0, 0.0, cams)?.siteId)
        assertEquals("088", StationCamMatcher.match("台灣大道", 0.0, 0.0, cams)?.siteId)
        assertEquals("088", StationCamMatcher.match(" 臺灣 大道 ", 0.0, 0.0, cams)?.siteId)
    }

    @Test
    fun fallsBackToANearbyCamWhenTheNameDiffers() {
        assertEquals("001", StationCamMatcher.match("Keelung", 25.1292, 121.7601, cams)?.siteId)
    }

    /** 復興 has no cam; 前鎮's is 610 m away and shows a different street. */
    @Test
    fun doesNotBorrowANeighboursCam() {
        assertNull(StationCamMatcher.match("復興", 22.608711, 120.312017, cams))
    }

    @Test
    fun noCoordinatesAndNoNameMatchIsMissing() {
        assertNull(StationCamMatcher.match("", 0.0, 0.0, cams))
        assertNull(StationCamMatcher.match("Nowhere", 0.0, 0.0, cams))
    }

    // Hourly history

    @Test
    fun hourKeyIsTaiwanClockHour() {
        // 15:30 UTC is 23:30 in Taiwan.
        val hour = StationCamHour("001", date("2026-10-30T15:30:00Z"))
        assertEquals("2026-10-30", hour.day)
        assertEquals("23", hour.hourOfDay)
        assertEquals("2026-10-30/23", hour.key)
        assertEquals("stations/001/2026-10-30/23.jpg", hour.objectKey)
        assertEquals(date("2026-10-30T23:00:00+08:00"), hour.hour)
    }

    /** Just after midnight in Taiwan is still the previous day in UTC. */
    @Test
    fun hourKeyUsesTaiwanDateAcrossMidnight() {
        val hour = StationCamHour("204", date("2026-11-01T00:10:00+08:00"))
        assertEquals("stations/204/2026-11-01/00.jpg", hour.objectKey)
        assertEquals("2026-10-31T16:10:00Z", date("2026-11-01T00:10:00+08:00").toString())
    }

    /** The last minute before Taiwan midnight and the first after it are different days. */
    @Test
    fun hourKeysEitherSideOfTaiwanMidnight() {
        assertEquals("2026-12-31/23", StationCamHour("001", date("2026-12-31T15:59:59Z")).key)
        assertEquals("2027-01-01/00", StationCamHour("001", date("2026-12-31T16:00:00Z")).key)
    }

    /** The phone's zone never moves the key: not New York's offset, nor London's. */
    @Test
    fun hourKeyIgnoresTheDeviceZone() {
        for (zone in listOf("America/New_York", "Europe/London", "Pacific/Kiritimati", "UTC")) {
            TimeZone.setDefault(TimeZone.getTimeZone(zone))
            val hour = StationCamHour("001", date("2026-10-30T15:30:00Z"))
            assertEquals(zone, "stations/001/2026-10-30/23.jpg", hour.objectKey)
        }
    }

    @Test
    fun hourUrlMatchesTheWorkerKeyWithNoVersion() {
        val hour = StationCamHour("001", date("2026-10-30T22:00:00+08:00"))
        assertEquals("https://cams.example.com/stations/001/2026-10-30/22.jpg", endpoints.hour(hour).toString())
        assertNull(endpoints.hour(hour)?.query)
    }

    @Test
    fun cacheFileNameIsFlatAndPerCamAndHour() {
        val hour = StationCamHour("001", date("2026-10-30T22:40:00+08:00"))
        assertEquals("001-2026-10-30-22.jpg", hour.cacheFileName)
        assertTrue(!hour.cacheFileName.contains("/"))
        assertNotEquals(hour.cacheFileName, StationCamHour("057", hour.hour).cacheFileName)
        assertNotEquals(hour.cacheFileName, StationCamHour("001", hour.hour.minus(Duration.ofDays(1))).cacheFileName)
    }

    @Test
    fun sameHourIsOneSlotWhateverTheMinute() {
        assertEquals(
            StationCamHour("001", date("2026-10-30T22:00:00+08:00")),
            StationCamHour("001", date("2026-10-30T22:59:59+08:00"))
        )
        assertEquals(
            StationCamHour("001", date("2026-10-30T22:00:00+08:00")).hashCode(),
            StationCamHour("001", date("2026-10-30T22:59:59+08:00")).hashCode()
        )
    }

    @Test
    fun twentyFourWholeHourSlotsEndingAtTheAnchorsHour() {
        val slots = StationCamHour.slots("001", date("2026-10-31T21:40:00+08:00"))

        assertEquals(24, slots.size)
        assertEquals("stations/001/2026-10-31/21.jpg", slots.last().objectKey)
        assertEquals("stations/001/2026-10-30/22.jpg", slots.first().objectKey)
        assertEquals(24, slots.toSet().size)
        slots.zipWithNext().forEach { (earlier, later) ->
            assertEquals(Duration.ofHours(1), Duration.between(earlier.hour, later.hour))
        }
    }

    @Test
    fun slotsCrossMidnightInTaiwanTime() {
        val slots = StationCamHour.slots("001", date("2026-11-01T02:05:00+08:00"))
        assertEquals(
            listOf(
                "stations/001/2026-10-31/23.jpg",
                "stations/001/2026-11-01/00.jpg",
                "stations/001/2026-11-01/01.jpg",
                "stations/001/2026-11-01/02.jpg"
            ),
            slots.takeLast(4).map { it.objectKey }
        )
    }

    /**
     * DST-free: on the nights clocks change in New York (1 Nov 2026) and London (25 Oct 2026),
     * a phone there still gets 24 distinct Taiwan hours, one hour apart, none doubled or skipped.
     */
    @Test
    fun slotsAreDstFreeWhateverTheDeviceZone() {
        val cases = listOf(
            "America/New_York" to "2026-11-01T06:30:00Z", // 01:30 EST repeats here; 14:30 in Taiwan
            "Europe/London" to "2026-10-25T01:30:00Z", // 01:00 BST falls back; 09:30 in Taiwan
            "America/New_York" to "2026-03-08T07:30:00Z" // 02:00 EST springs forward; 15:30 in Taiwan
        )
        for ((zone, anchor) in cases) {
            TimeZone.setDefault(TimeZone.getTimeZone(zone))
            val slots = StationCamHour.slots("001", Instant.parse(anchor))
            assertEquals(zone, 24, slots.map { it.key }.toSet().size)
            slots.zipWithNext().forEach { (earlier, later) ->
                assertEquals(zone, Duration.ofHours(1), Duration.between(earlier.hour, later.hour))
            }
            val taiwanHour = Instant.parse(anchor).atZone(StationCamHour.ZONE).hour
            assertEquals(zone, "%02d".format(taiwanHour), slots.last().hourOfDay)
            // Every hour of the Taiwan day appears exactly once.
            assertEquals(zone, (0..23).map { "%02d".format(it) }.toSet(), slots.map { it.hourOfDay }.toSet())
        }
    }

    /** Lazy loading: the slot on screen first, then ±1, ±2, never the day. */
    @Test
    fun loadWindowIsTheSlotAndTwoNeighboursNearestFirst() {
        assertEquals(listOf(10, 9, 11, 8, 12), StationCamHour.window(10))
        assertEquals(listOf(0, 1, 2), StationCamHour.window(0))
        assertEquals(listOf(23, 22, 21), StationCamHour.window(23))
        assertEquals(listOf(5, 4, 6), StationCamHour.window(5, radius = 1))
        assertEquals(emptyList<Int>(), StationCamHour.window(24))
    }
}
