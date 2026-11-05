package com.kfpun.twaqi.ui.main

import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import org.junit.Assert.assertEquals
import org.junit.Test

class MarkerAppearanceTest {
    @Test
    fun everyLevelOfEveryIndexGetsItsBandColour() {
        for (type in AirIndexType.entries) {
            for (band in AirStatus.bands.getValue(type)) {
                for (value in listOf(band.from, (band.from + band.until) / 2)) {
                    val look = MarkerAppearance.of(reading(type, value), type, isInteractive = true)
                    assertEquals("$type $value", band.status, look.status)
                    assertEquals("$type $value", band.status.color, look.color)
                    assertEquals("$type $value", band.status.foregroundColor, look.foregroundColor)
                }
            }
        }
    }

    @Test
    fun aqiLevelsMatchIos() {
        val expected = listOf(
            25.0 to 0x009866,
            75.0 to 0xFEDE33,
            125.0 to 0xFE9833,
            175.0 to 0xCC0033,
            250.0 to 0x660098,
            400.0 to 0x7E2200
        )
        for ((aqi, color) in expected) {
            assertEquals("AQI $aqi", color, MarkerAppearance.of(pollutant(1, aqi = aqi), AirIndexType.AQI, true).color)
        }
    }

    @Test
    fun noReadingIsAGreyDash() {
        val look = MarkerAppearance.of(pollutant(1, aqi = 0.0), AirIndexType.AQI, isInteractive = true)
        assertEquals("-", look.text)
        assertEquals(AirStatus.UNKNOWN, look.status)
        assertEquals(0x676767, look.color)
    }

    @Test
    fun textUsesTheIndexDecimals() {
        assertEquals("54", MarkerAppearance.of(pollutant(1, aqi = 54.0), AirIndexType.AQI, true).text)
        assertEquals("0.30", MarkerAppearance.of(pollutant(1), AirIndexType.CO, true).text)
        assertEquals("30.0", MarkerAppearance.of(pollutant(1), AirIndexType.O3, true).text)
    }

    @Test
    fun otherCountriesAreMutedAndMissingHoursFaded() {
        assertEquals(1f, MarkerAppearance.of(pollutant(1), AirIndexType.AQI, isInteractive = true).alpha)
        assertEquals(0.4f, MarkerAppearance.of(pollutant(1), AirIndexType.AQI, isInteractive = false).alpha)
        assertEquals(
            0.55f,
            MarkerAppearance.of(pollutant(1), AirIndexType.AQI, isInteractive = true, hasData = false).alpha
        )
        assertEquals(
            0.4f,
            MarkerAppearance.of(pollutant(1), AirIndexType.AQI, isInteractive = false, hasData = false).alpha
        )
    }

    @Test
    fun onlyTheSupportedCountryOpens() {
        val stations = MarkerSource.stations(
            countryPollutants = mapOf("twn" to listOf(pollutant(1)), "jpn" to listOf(pollutant(1))),
            supportedCountryCode = "twn",
            type = AirIndexType.AQI,
            chinese = false
        )
        assertEquals(mapOf("twn" to true, "jpn" to false), stations.associate { it.countryCode to it.isInteractive })
        // Same station id in two countries: two markers.
        assertEquals(2, stations.toSet().size)
    }

    @Test
    fun indexRecoloursTheMarkers() {
        val reading = mapOf("twn" to listOf(pollutant(1, aqi = 40.0, pm25 = 40.0)))
        val aqi = MarkerSource.stations(reading, "twn", AirIndexType.AQI, chinese = false).single()
        val pm25 = MarkerSource.stations(reading, "twn", AirIndexType.PM25, chinese = false).single()
        assertEquals(AirStatus.GOOD, aqi.appearance.status)
        assertEquals(AirStatus.UNHEALTHY_FOR_SENSITIVE_GROUP, pm25.appearance.status)
        // Same station: the renderer restyles the marker it has.
        assertEquals(aqi, pm25)
    }

    @Test
    fun timelineHourShowsThatHoursReadingOrFadesTheLiveOne() {
        val live = mapOf("twn" to listOf(pollutant(1, aqi = 40.0), pollutant(2, aqi = 40.0)))
        val stations = MarkerSource.stations(
            live,
            "twn",
            AirIndexType.AQI,
            chinese = false,
            hour = "2026-11-06 10:00:00",
            readingAt = { p, _ -> if (p.stationId == 1) p.copy(aqi = 160.0) else null }
        )
        assertEquals(AirStatus.UNHEALTHY, stations[0].appearance.status)
        assertEquals(1f, stations[0].appearance.alpha)
        assertEquals(AirStatus.GOOD, stations[1].appearance.status)
        assertEquals(0.55f, stations[1].appearance.alpha)
    }

    @Test
    fun clusterTakesTheWorstBand() {
        val stations = MarkerSource.stations(
            mapOf("twn" to listOf(pollutant(1, aqi = 40.0), pollutant(2, aqi = 160.0), pollutant(3, aqi = 0.0))),
            "twn",
            AirIndexType.AQI,
            chinese = false
        )
        assertEquals(AirStatus.UNHEALTHY, StationClusterRenderer.clusterStatus(stations))
        assertEquals(AirStatus.UNKNOWN, StationClusterRenderer.clusterStatus(listOf(stations[2])))
    }

    private fun reading(type: AirIndexType, value: Double) = when (type) {
        AirIndexType.AQI -> pollutant(1).copy(aqi = value)
        AirIndexType.PM25 -> pollutant(1).copy(pm25 = value)
        AirIndexType.PM10 -> pollutant(1).copy(pm10 = value)
        AirIndexType.O3 -> pollutant(1).copy(o3 = value)
        AirIndexType.CO -> pollutant(1).copy(co = value)
        AirIndexType.SO2 -> pollutant(1).copy(so2 = value)
        AirIndexType.NO2 -> pollutant(1).copy(no2 = value)
    }
}
