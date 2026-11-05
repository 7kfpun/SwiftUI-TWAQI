package com.kfpun.twaqi.widget

import androidx.datastore.preferences.core.mutablePreferencesOf
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.ui.main.GeoPoint
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** FOX-59: a widget's settings, its saved state, and where "nearest" is measured from. */
class WidgetConfigTest {
    private val now = Instant.ofEpochSecond(1_793_000_000)

    @Test
    fun stationChoiceRoundTrips() {
        listOf(StationChoice.Nearest, StationChoice.FirstFavourite, StationChoice.Station(126)).forEach {
            assertEquals(it, StationChoice.fromId(it.id))
        }
    }

    @Test
    fun unknownChoiceIsNearest() {
        listOf(null, "", "bogus", "station:", "station:abc", "station:-3").forEach {
            assertEquals("$it", StationChoice.Nearest, StationChoice.fromId(it))
        }
    }

    @Test
    fun leadingStationFollowsTheChoice() {
        val favourites = listOf(5, 6)
        assertEquals(9, WidgetConfig(StationChoice.Nearest).leadingStationId(favourites, nearestId = 9))
        assertEquals(5, WidgetConfig(StationChoice.FirstFavourite).leadingStationId(favourites, nearestId = 9))
        // No favourite yet: the nearest station, as iOS falls back to the closest.
        assertEquals(9, WidgetConfig(StationChoice.FirstFavourite).leadingStationId(emptyList(), nearestId = 9))
        assertEquals(42, WidgetConfig(StationChoice.Station(42)).leadingStationId(favourites, nearestId = 9))
        assertNull(WidgetConfig(StationChoice.Nearest).leadingStationId(favourites, nearestId = null))
    }

    @Test
    fun onlyNearestNeedsAPosition() {
        assertTrue(WidgetConfig(StationChoice.Nearest).needsNearest(listOf(1)))
        assertFalse(WidgetConfig(StationChoice.FirstFavourite).needsNearest(listOf(1)))
        assertTrue(WidgetConfig(StationChoice.FirstFavourite).needsNearest(emptyList()))
        assertFalse(WidgetConfig(StationChoice.Station(3)).needsNearest(emptyList()))
    }

    @Test
    fun aNewWidgetIsNearestAndAqi() {
        assertEquals(
            WidgetConfig(StationChoice.Nearest, AirIndexType.AQI),
            WidgetStateKeys.config(mutablePreferencesOf())
        )
    }

    @Test
    fun savingSettingsStartsThePageAfreshButKeepsTheRefreshTime() {
        val prefs = mutablePreferencesOf()
        WidgetStateKeys.writePageState(
            prefs,
            WidgetPageState(stationId = 3, index = "o3", tappedAt = now, refreshedAt = now)
        )
        WidgetStateKeys.writeConfig(prefs, WidgetConfig(StationChoice.Station(7), AirIndexType.PM10))

        assertEquals(WidgetConfig(StationChoice.Station(7), AirIndexType.PM10), WidgetStateKeys.config(prefs))
        assertEquals(WidgetPageState(refreshedAt = now), WidgetStateKeys.pageState(prefs))
        assertEquals(true, prefs[WidgetStateKeys.CONFIGURED])
    }

    @Test
    fun pageStateRoundTrips() {
        val prefs = mutablePreferencesOf()
        val state = WidgetPageState(stationId = 3, index = "co", tappedAt = now, refreshedAt = now.minusSeconds(60))
        WidgetStateKeys.writePageState(prefs, state)
        assertEquals(state, WidgetStateKeys.pageState(prefs))
        WidgetStateKeys.writePageState(prefs, WidgetPageState())
        assertEquals(WidgetPageState(), WidgetStateKeys.pageState(prefs))
    }

    @Test
    fun everyRedrawBumpsTheVersion() {
        val prefs = mutablePreferencesOf()
        WidgetStateKeys.bumpVersion(prefs, now)
        val first = prefs[WidgetStateKeys.VERSION]!!
        // Twice in the same millisecond still changes it.
        WidgetStateKeys.bumpVersion(prefs, now)
        assertTrue(prefs[WidgetStateKeys.VERSION]!! > first)
    }

    @Test
    fun nearestIsMeasuredFromTheFixThenTheMapThenTaipei() {
        val saved = GeoPoint(25.02, 121.53)
        assertEquals(GeoPoint(24.1, 120.6), WidgetLocation.choose(GeoPoint(24.1, 120.6), saved, 22.6, 120.3))
        // In the background there's no last fix: the one the app saw in the foreground wins over the map.
        assertEquals(saved, WidgetLocation.choose(null, saved, 22.6, 120.3))
        assertEquals(GeoPoint(22.6, 120.3), WidgetLocation.choose(null, null, 22.6, 120.3))
        assertEquals(WidgetLocation.DEFAULT, WidgetLocation.choose(null, null, 0.0, 0.0))
    }
}
