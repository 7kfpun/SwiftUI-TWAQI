package com.kfpun.twaqi.data

import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ported from iOS `AirStatusesTests`: band edges colour every marker, badge and chart bar. */
class AirStatusTest {
    private fun aqi(value: Double) = AirStatus.of(AirIndexType.AQI, value)

    @Test
    fun aqiBandMidpoints() {
        assertEquals(AirStatus.GOOD, aqi(25.0))
        assertEquals(AirStatus.MODERATE, aqi(75.0))
        assertEquals(AirStatus.UNHEALTHY_FOR_SENSITIVE_GROUP, aqi(125.0))
        assertEquals(AirStatus.UNHEALTHY, aqi(175.0))
        assertEquals(AirStatus.VERY_UNHEALTHY, aqi(250.0))
        assertEquals(AirStatus.HAZARDOUS, aqi(400.0))
    }

    /** Each boundary belongs to the higher band. */
    @Test
    fun aqiBandBoundaries() {
        assertEquals(AirStatus.GOOD, aqi(50.0))
        assertEquals(AirStatus.MODERATE, aqi(51.0))
        assertEquals(AirStatus.MODERATE, aqi(100.0))
        assertEquals(AirStatus.UNHEALTHY_FOR_SENSITIVE_GROUP, aqi(101.0))
        assertEquals(AirStatus.UNHEALTHY_FOR_SENSITIVE_GROUP, aqi(150.0))
        assertEquals(AirStatus.UNHEALTHY, aqi(151.0))
        assertEquals(AirStatus.UNHEALTHY, aqi(200.0))
        assertEquals(AirStatus.VERY_UNHEALTHY, aqi(201.0))
        assertEquals(AirStatus.VERY_UNHEALTHY, aqi(300.0))
        assertEquals(AirStatus.HAZARDOUS, aqi(301.0))
    }

    /** Zero means "no reading", not perfect air. */
    @Test
    fun zeroAndNegativeAreUnknown() {
        assertEquals(AirStatus.UNKNOWN, aqi(0.0))
        assertEquals(AirStatus.UNKNOWN, aqi(-5.0))
        assertEquals(AirStatus.UNKNOWN, aqi(1000.0))
    }

    @Test
    fun unknownHasNoFaceImageAndRealStatusesDo() {
        assertFalse(AirStatus.UNKNOWN.hasFaceImage)
        assertNull(AirStatus.UNKNOWN.imageName)
        AirStatus.showAllCases.forEach { assertTrue("$it needs artwork", it.hasFaceImage) }
        assertEquals("status_unhealthyforsensitivegroup", AirStatus.UNHEALTHY_FOR_SENSITIVE_GROUP.imageName)
    }

    @Test
    fun legendIsTheSixRealBands() {
        assertFalse(AirStatus.UNKNOWN in AirStatus.showAllCases)
        assertEquals(6, AirStatus.showAllCases.size)
    }

    @Test
    fun pm25Bands() {
        fun pm25(value: Double) = AirStatus.of(AirIndexType.PM25, value)
        assertEquals(AirStatus.GOOD, pm25(10.0))
        assertEquals(AirStatus.MODERATE, pm25(20.0))
        assertEquals(AirStatus.UNHEALTHY_FOR_SENSITIVE_GROUP, pm25(40.0))
        assertEquals(AirStatus.UNHEALTHY, pm25(100.0))
        assertEquals(AirStatus.VERY_UNHEALTHY, pm25(200.0))
        assertEquals(AirStatus.HAZARDOUS, pm25(300.0))
        assertEquals(AirStatus.MODERATE, pm25(15.5))
        assertEquals(AirStatus.GOOD, pm25(15.4))
    }

    /** The same thresholds as iOS `AirStatuses.bands`, lowest edge of each band. */
    @Test
    fun everyIndexHasTheIosThresholds() {
        val expected = mapOf(
            AirIndexType.AQI to listOf(1.0, 51.0, 101.0, 151.0, 201.0, 301.0, 1000.0),
            AirIndexType.PM25 to listOf(0.1, 15.5, 35.5, 54.5, 150.5, 250.5, 5005.0),
            AirIndexType.PM10 to listOf(1.0, 55.0, 126.0, 255.0, 355.0, 425.0, 6050.0),
            AirIndexType.O3 to listOf(1.0, 55.0, 125.0, 165.0, 205.0, 405.0, 605.0),
            AirIndexType.CO to listOf(0.1, 4.5, 9.5, 12.5, 15.5, 30.5, 50.5),
            AirIndexType.SO2 to listOf(1.0, 36.0, 76.0, 186.0, 305.0, 605.0, 1005.0),
            AirIndexType.NO2 to listOf(1.0, 54.0, 101.0, 361.0, 650.0, 1250.0, 2050.0)
        )
        assertEquals(AirIndexType.entries.toSet(), AirStatus.bands.keys)
        for ((type, edges) in expected) {
            val bands = AirStatus.bands.getValue(type)
            assertEquals(type.name, edges.dropLast(1), bands.map { it.from })
            assertEquals(type.name, edges.drop(1), bands.map { it.until })
            assertEquals(type.name, AirStatus.showAllCases, bands.map { it.status })
            // Contiguous: each band starts where the last one ended.
            bands.zipWithNext().forEach { (a, b) -> assertEquals(a.until, b.from, 0.0) }
            assertEquals(AirStatus.UNKNOWN, AirStatus.of(type, edges.last()))
        }
    }

    @Test
    fun coBandsUsePpm() {
        assertEquals(AirStatus.GOOD, AirStatus.of(AirIndexType.CO, 0.33))
        assertEquals(AirStatus.MODERATE, AirStatus.of(AirIndexType.CO, 4.5))
        assertEquals(AirStatus.UNKNOWN, AirStatus.of(AirIndexType.CO, 0.05))
    }

    @Test
    fun colorsMatchIos() {
        assertEquals(0x009866, AirStatus.GOOD.color)
        assertEquals(0xFEDE33, AirStatus.MODERATE.color)
        assertEquals(0xFE9833, AirStatus.UNHEALTHY_FOR_SENSITIVE_GROUP.color)
        assertEquals(0xCC0033, AirStatus.UNHEALTHY.color)
        assertEquals(0x660098, AirStatus.VERY_UNHEALTHY.color)
        assertEquals(0x7E2200, AirStatus.HAZARDOUS.color)
        assertEquals(0x676767, AirStatus.UNKNOWN.color)
    }

    /** Dark text on the two light bands, white elsewhere. */
    @Test
    fun foregroundColorsMatchIos() {
        val black = setOf(AirStatus.MODERATE, AirStatus.UNHEALTHY_FOR_SENSITIVE_GROUP)
        AirStatus.entries.forEach {
            assertEquals(it.name, if (it in black) 0x000000 else 0xFFFFFF, it.foregroundColor)
        }
    }

    @Test
    fun guidanceForRealBandsOnly() {
        AirStatus.showAllCases.forEach {
            assertTrue(it.generalPublicGuidance != null && it.sensitiveGroupGuidance != null)
        }
        assertNull(AirStatus.UNKNOWN.generalPublicGuidance)
    }

    @Test
    fun indexLabelsUnitsAndFormats() {
        assertEquals(listOf("AQI", "PM2.5", "PM10", "O3", "CO", "SO2", "NO2"), AirIndexType.entries.map { it.label })
        assertEquals("μg/m3", AirIndexType.PM25.unit)
        assertEquals("ppm", AirIndexType.CO.unit)
        assertEquals("ppb", AirIndexType.O3.unit)
        assertEquals("54", AirIndexType.AQI.format(54.0))
        assertEquals("0.33", AirIndexType.CO.format(0.33))
        assertEquals("52.0", AirIndexType.O3.format(52.0))
        assertEquals(AirIndexType.PM25, AirIndexType.fromKey("pm25"))
    }
}
