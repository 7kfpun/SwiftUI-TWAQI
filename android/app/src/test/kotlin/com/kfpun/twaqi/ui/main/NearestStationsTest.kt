package com.kfpun.twaqi.ui.main

import com.kfpun.twaqi.data.model.Country
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NearestStationsTest {
    private val keelung = pollutant(1, lat = 25.129167, lon = 121.760056, name = "Keelung")
    private val songshan = pollutant(2, lat = 25.050000, lon = 121.578611, name = "Songshan")
    private val kaohsiung = pollutant(3, lat = 22.632567, lon = 120.288086, name = "Qianjin")
    private val all = listOf(kaohsiung, keelung, songshan)

    @Test
    fun sortsNearestFirst() {
        val taipei101 = GeoPoint(25.033964, 121.564468)
        val sorted = NearestStations.sortedByNearest(all, taipei101)
        assertEquals(listOf(2, 1, 3), sorted.map { it.first.stationId })
        assertEquals(2.28, sorted.first().second!!, 0.05)
    }

    @Test
    fun withoutAPointKeepsTheApiOrderAndNoDistance() {
        val sorted = NearestStations.sortedByNearest(all, null)
        assertEquals(listOf(3, 1, 2), sorted.map { it.first.stationId })
        assertEquals(listOf(null, null, null), sorted.map { it.second })
    }

    @Test
    fun tiesKeepTheApiOrder() {
        val a = pollutant(10, lat = 24.0, lon = 121.0)
        val b = pollutant(11, lat = 24.0, lon = 121.0)
        assertEquals(
            listOf(10, 11),
            NearestStations.sortedByNearest(listOf(a, b), GeoPoint(23.0, 120.0)).map {
                it.first.stationId
            }
        )
    }

    @Test
    fun closestStationIsTheOneNearestTheMapCentre() {
        assertEquals(3, NearestStations.closest(all, GeoPoint(22.6, 120.3))?.stationId)
        assertEquals(1, NearestStations.closest(all, GeoPoint(25.2, 121.8))?.stationId)
        assertNull(NearestStations.closest(emptyList(), GeoPoint(25.0, 121.0)))
    }

    @Test
    fun closestStationLooksAcrossCountries() {
        val state = MainUiState(
            supportedCountryCode = "twn",
            countryPollutants = mapOf(
                "twn" to listOf(keelung, songshan),
                "jpn" to listOf(pollutant(1, lat = 26.2, lon = 127.7, name = "Naha"))
            ),
            center = GeoPoint(26.0, 127.5)
        )
        val closest = state.closest!!
        assertEquals("Naha", closest.name)
        // Same id as Keelung, but from another country: context only.
        assertEquals(false, state.isInteractive(closest))
        assertEquals(true, state.isInteractive(keelung))
    }

    @Test
    fun closestCountrySkipsPlaceholderRows() {
        val countries = listOf(
            Country(1, "xxx", 0.0, 0.0, 0f, "", ""),
            Country(3, "twn", 23.7, 121.0, 7.9f, "Taiwan", "臺灣"),
            Country(4, "jpn", 36.2, 138.2, 5f, "Japan", "日本")
        )
        assertEquals("twn", NearestStations.closestCountry(countries, GeoPoint(1.0, 1.0))?.code)
        assertEquals("jpn", NearestStations.closestCountry(countries, GeoPoint(35.0, 139.0))?.code)
    }

    @Test
    fun distancesReadTheSameInBothLanguages() {
        assertEquals("850 m", formatDistance(0.8504))
        assertEquals("10 m", formatDistance(0.001))
        assertEquals("3.4 km", formatDistance(3.42))
        assertEquals("120 km", formatDistance(120.6))
    }
}
