package com.kfpun.twaqi.ui.station.wind

import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.Wind
import com.kfpun.twaqi.ui.main.pollutant
import com.kfpun.twaqi.ui.station.StationDetailsUiState
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

/**
 * The station page's wind section (FOX-101, iOS `WindView`): the direction and speed text in both
 * languages, the calm state, when it is hidden and how the arrow is tinted.
 */
class StationWindTest {
    private val english = strings("values")
    private val chinese = strings("values-zh-rTW")

    // Speed and direction text

    @Test
    fun speedHasOneDecimal() {
        assertEquals("2.6", StationWind.speed(Wind(247.0, 2.6)))
        assertEquals("1.0", StationWind.speed(Wind(120.0, 1.0)))
        assertEquals("9.0", StationWind.speed(Wind(30.0, 9.0)))
        assertEquals("1.4", StationWind.speed(Wind(30.0, 1.44)))
    }

    /** iOS formats with `%.1f` in the POSIX locale: never a decimal comma. */
    @Test
    fun speedKeepsAFullStopInEveryLocale() {
        val saved = java.util.Locale.getDefault()
        try {
            java.util.Locale.setDefault(java.util.Locale.GERMANY)
            assertEquals("2.6", StationWind.speed(Wind(247.0, 2.6)))
        } finally {
            java.util.Locale.setDefault(saved)
        }
    }

    /** The compass point is the same abbreviation in both languages (iOS `Text(verbatim:)`). */
    @Test
    fun directionAndDescriptorInEnglish() {
        val wind = Wind(247.0, 2.6)
        assertEquals("WSW", wind.compassPoint)
        assertEquals("Light breeze", english.getValue(name(wind.descriptor)))
        assertEquals("Wind", english.getValue("details_wind"))
    }

    @Test
    fun directionAndDescriptorInChinese() {
        val wind = Wind(247.0, 2.6)
        assertEquals("WSW", wind.compassPoint)
        assertEquals("輕風", chinese.getValue(name(wind.descriptor)))
        assertEquals("風向風速", chinese.getValue("details_wind"))
    }

    @Test
    fun everyDescriptorReadsLikeIos() {
        val expected = listOf(
            Triple(0.1, "Calm", "無風"),
            Triple(1.0, "Light air", "軟風"),
            Triple(2.6, "Light breeze", "輕風"),
            Triple(4.0, "Gentle breeze", "微風"),
            Triple(6.0, "Moderate breeze", "和風"),
            Triple(9.0, "Strong breeze", "清勁風")
        )
        for ((speed, en, zh) in expected) {
            val key = name(Wind(90.0, speed).descriptor)
            assertEquals(en, english.getValue(key))
            assertEquals(zh, chinese.getValue(key))
        }
    }

    // Calm

    /** `0 / 0` (still air, or no anemometer) is shown as calm, not hidden and not "due north". */
    @Test
    fun zeroWindReadsAsCalm() {
        val wind = StationWind.of(state(direction = 0.0, speed = 0.0))!!
        assertTrue(wind.isCalm)
        assertEquals("—", wind.compassPoint)
        assertEquals("Calm", english.getValue("wind_calm"))
        assertEquals("無風", chinese.getValue("wind_calm"))
    }

    // Hidden when missing

    @Test
    fun hiddenWithoutACurrentReading() {
        assertNull(StationWind.of(StationDetailsUiState(stationId = 1)))
    }

    @Test
    fun shownWithTheReadingsWind() {
        assertEquals(Wind(247.0, 2.6), StationWind.of(state(direction = 247.0, speed = 2.6)))
    }

    // Arrow

    /** The arrow takes the selected pollutant's band, as iOS `selectedTint` does. */
    @Test
    fun tintFollowsTheSelectedPollutant() {
        val reading = pollutant(1, aqi = 30.0, pm25 = 60.0)
        assertEquals(AirStatus.of(AirIndexType.AQI, 30.0).color, StationWind.tint(reading, AirIndexType.AQI))
        assertEquals(AirStatus.of(AirIndexType.PM25, 60.0).color, StationWind.tint(reading, AirIndexType.PM25))
        assertNotEquals(StationWind.tint(reading, AirIndexType.AQI), StationWind.tint(reading, AirIndexType.PM25))
    }

    @Test
    fun arrowLengthRunsFromStubToNearlyTheRing() {
        assertEquals(18f, StationWind.arrowLength(Wind(0.0, 0.0)), 0.001f)
        assertEquals(32f, StationWind.arrowLength(Wind(0.0, 4.0)), 0.001f)
        assertEquals(46f, StationWind.arrowLength(Wind(0.0, 20.0)), 0.001f)
    }

    @Test
    fun strongerWindWaversFasterAndWider() {
        assertEquals(2.4, StationWind.driftDuration(Wind(0.0, 0.5)), 0.1)
        assertEquals(1.4, StationWind.driftDuration(Wind(0.0, 8.0)), 0.001)
        assertEquals(4.0, StationWind.wobble(Wind(0.0, 8.0)), 0.001)
        assertTrue(StationWind.wobble(Wind(0.0, 1.0)) < StationWind.wobble(Wind(0.0, 6.0)))
    }

    private fun state(direction: Double, speed: Double) = StationDetailsUiState(
        stationId = 1,
        pollutant = pollutant(1).copy(windDirection = direction, windSpeed = speed)
    )

    private fun name(id: Int): String = when (id) {
        R.string.wind_calm -> "wind_calm"
        R.string.wind_light_air -> "wind_light_air"
        R.string.wind_light_breeze -> "wind_light_breeze"
        R.string.wind_gentle_breeze -> "wind_gentle_breeze"
        R.string.wind_moderate_breeze -> "wind_moderate_breeze"
        R.string.wind_strong_breeze -> "wind_strong_breeze"
        else -> error("not a wind descriptor: $id")
    }

    /** Unit tests run from the module directory (android/app). */
    private fun strings(folder: String): Map<String, String> {
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder()
            .parse(File("src/main/res/$folder/strings.xml"))
        val nodes = doc.getElementsByTagName("string")
        return (0 until nodes.length).associate {
            val element = nodes.item(it) as Element
            element.getAttribute("name") to element.textContent
        }
    }
}
