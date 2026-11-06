package com.kfpun.twaqi.ui.main

import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.HistoricalPollutant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * FOX-110: the map's markers must follow the index, wind mode and timeline hour. Each case pins
 * that the new list is *equal* to the old one (stations are equal by id, which is all maps-compose's
 * `Clustering`, Compose effect keys and `rememberUpdatedState` compare, so they all skip it) and that
 * [MarkerSync] still asks for the push.
 */
class MarkerSyncTest {
    private val live = mapOf(
        "twn" to listOf(
            pollutant(1, aqi = 42.0, pm25 = 11.0).copy(
                windDirection = 90.0,
                windSpeed = 3.0,
                publishTime = "2026-11-06T11:00:00"
            ),
            pollutant(2, aqi = 47.0, pm25 = 14.0).copy(publishTime = "2026-11-06T11:00:00")
        ),
        "jpn" to listOf(pollutant(1, aqi = 30.0))
    )

    private fun stations(
        type: AirIndexType = AirIndexType.AQI,
        mode: MapMode = MapMode.POLLUTANT,
        hoursAgo: Int = 0,
        chinese: Boolean = false,
        readingAt: (Int, String) -> HistoricalPollutant? = { _, _ -> null }
    ) = MarkerSource.stations(live, "twn", type, chinese, mode, hoursAgo, readingAt)

    @Test
    fun theFirstListIsPushed() {
        assertTrue(MarkerSync.needsPush(null, stations()))
    }

    @Test
    fun anotherIndexRestylesTheMarkers() {
        val aqi = stations(AirIndexType.AQI)
        val pm25 = stations(AirIndexType.PM25)
        assertEquals(aqi, pm25)
        assertEquals("42", aqi[0].appearance.text)
        assertEquals("11", pm25[0].appearance.text)
        assertTrue(MarkerSync.needsPush(aqi, pm25))
    }

    @Test
    fun windModeTurnsTheMarkersIntoArrows() {
        val pills = stations()
        val wind = stations(mode = MapMode.WIND)
        assertEquals(pills, wind)
        assertTrue(wind[0].appearance.shape is MarkerShape.Arrow)
        assertTrue(MarkerSync.needsPush(pills, wind))
    }

    @Test
    fun anEarlierHourShowsThatHoursReading() {
        val now = stations()
        val reading = HistoricalPollutant(73.0, 20.0, 30.0, 5.0, 1.0, 0.3, 30.0, 0.0, 0.0, "2026-11-05T19:00:00")
        val yesterday = stations(hoursAgo = 16) { id, _ -> if (id == 1) reading else null }
        assertEquals(now, yesterday)
        assertEquals("73", yesterday[0].appearance.text)
        assertTrue(MarkerSync.needsPush(now, yesterday))
    }

    @Test
    fun theLanguageRelabelsTheMarkers() {
        assertTrue(MarkerSync.needsPush(stations(chinese = false), stations(chinese = true)))
    }

    /** History arriving for another hour rebuilds the list but draws the same: no restyle pass. */
    @Test
    fun anUnchangedLookIsNotPushedAgain() {
        assertFalse(MarkerSync.needsPush(stations(AirIndexType.PM25), stations(AirIndexType.PM25)))
        assertFalse(MarkerSync.needsPush(stations(mode = MapMode.WIND), stations(mode = MapMode.WIND)))
    }

    @Test
    fun addedOrRemovedStationsArePushed() {
        val all = stations()
        assertTrue(MarkerSync.needsPush(all, all.drop(1)))
        assertTrue(MarkerSync.needsPush(all.drop(1), all))
    }

    /** What the map sees: AQI, PM2.5, the same PM2.5 again (a history tick), then wind mode. */
    @Test
    fun takePushesEachNewLookOnce() {
        val sync = MarkerSync()
        assertTrue(sync.take(stations(AirIndexType.AQI)))
        assertTrue(sync.take(stations(AirIndexType.PM25)))
        assertFalse(sync.take(stations(AirIndexType.PM25)))
        assertTrue(sync.take(stations(AirIndexType.PM25, MapMode.WIND)))
        assertFalse(sync.take(stations(AirIndexType.PM25, MapMode.WIND)))
    }
}
