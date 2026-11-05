package com.kfpun.twaqi.data.model

import org.junit.Assert.assertEquals
import org.junit.Test

/** The levels both apps colour by (FOX-62); the phone's `AirStatusTest` covers the edges in full. */
class AirLevelTest {
    @Test
    fun everyIndexHasSixBandsInLevelOrder() {
        assertEquals(AirIndexType.entries.toSet(), AirLevel.bands.keys)
        for ((type, bands) in AirLevel.bands) {
            assertEquals("$type", AirLevel.showAllCases, bands.map { it.level })
            bands.zipWithNext { lower, upper -> assertEquals("$type", lower.until, upper.from, 0.0) }
        }
    }

    @Test
    fun boundariesBelongToTheHigherLevel() {
        assertEquals(AirLevel.GOOD, AirLevel.of(AirIndexType.AQI, 50.0))
        assertEquals(AirLevel.MODERATE, AirLevel.of(AirIndexType.AQI, 51.0))
        assertEquals(AirLevel.UNHEALTHY, AirLevel.of(AirIndexType.PM25, 54.5))
        assertEquals(AirLevel.UNKNOWN, AirLevel.of(AirIndexType.AQI, 0.0))
    }

    /** The phone's colours (iOS `AirStatuses.getColor`). */
    @Test
    fun coloursMatchThePhone() {
        assertEquals(
            listOf(0x009866, 0xFEDE33, 0xFE9833, 0xCC0033, 0x660098, 0x7E2200, 0x676767),
            AirLevel.entries.map { it.color }
        )
    }
}
