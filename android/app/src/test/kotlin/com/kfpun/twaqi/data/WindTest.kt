package com.kfpun.twaqi.data

import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.Wind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * iOS `WindTests`. `wind_direction` is meteorological: degrees clockwise from north, naming the
 * direction the wind blows *from*.
 */
class WindTest {
    // Calm

    @Test
    fun zeroSpeedIsCalm() {
        assertTrue(Wind(0.0, 0.0).isCalm)
    }

    /** Stations with no anemometer report `0 / 0`: calm, not "due north". */
    @Test
    fun missingAnemometerReadsAsCalm() {
        assertTrue(Wind(0.0, 0.0).isCalm)
        assertEquals("—", Wind(0.0, 0.0).compassPoint)
    }

    @Test
    fun anyPositiveSpeedIsNotCalm() {
        assertFalse(Wind(180.0, 0.1).isCalm)
    }

    // Compass points

    @Test
    fun cardinalDirections() {
        assertEquals("N", Wind(0.0, 2.0).compassPoint)
        assertEquals("E", Wind(90.0, 2.0).compassPoint)
        assertEquals("S", Wind(180.0, 2.0).compassPoint)
        assertEquals("W", Wind(270.0, 2.0).compassPoint)
    }

    @Test
    fun intercardinalDirections() {
        assertEquals("NE", Wind(45.0, 2.0).compassPoint)
        assertEquals("SE", Wind(135.0, 2.0).compassPoint)
        assertEquals("SW", Wind(225.0, 2.0).compassPoint)
        assertEquals("NW", Wind(315.0, 2.0).compassPoint)
    }

    @Test
    fun westSouthWest() {
        assertEquals("WSW", Wind(247.0, 2.6).compassPoint)
    }

    @Test
    fun eachOfTheSixteenPointsIsReachable() {
        val points = (0 until 16).map { Wind(it * 22.5, 2.0).compassPoint }
        assertEquals("every 22.5° step should name a distinct point", 16, points.toSet().size)
    }

    /** 360 and 0 are the same bearing; the modulo must not index past the end. */
    @Test
    fun fullCircleWrapsToNorth() {
        assertEquals("N", Wind(360.0, 2.0).compassPoint)
        assertEquals("N", Wind(720.0, 2.0).compassPoint)
    }

    @Test
    fun justUnderFullCircleIsNorth() {
        assertEquals("N", Wind(350.0, 2.0).compassPoint)
    }

    @Test
    fun negativeBearingsNormalise() {
        assertEquals("W", Wind(-90.0, 2.0).compassPoint)
        assertEquals("NW", Wind(-45.0, 2.0).compassPoint)
    }

    // Beaufort descriptor

    @Test
    fun speedDescriptors() {
        assertEquals(R.string.wind_calm, Wind(0.0, 0.1).descriptor)
        assertEquals(R.string.wind_light_air, Wind(0.0, 1.0).descriptor)
        assertEquals(R.string.wind_light_breeze, Wind(0.0, 2.6).descriptor)
        assertEquals(R.string.wind_gentle_breeze, Wind(0.0, 4.0).descriptor)
        assertEquals(R.string.wind_moderate_breeze, Wind(0.0, 6.0).descriptor)
        assertEquals(R.string.wind_strong_breeze, Wind(0.0, 20.0).descriptor)
    }

    /** Each band is half-open, so the boundary value belongs to the band above. */
    @Test
    fun descriptorBoundaries() {
        assertEquals(R.string.wind_light_air, Wind(0.0, 0.3).descriptor)
        assertEquals(R.string.wind_light_breeze, Wind(0.0, 1.6).descriptor)
        assertEquals(R.string.wind_gentle_breeze, Wind(0.0, 3.4).descriptor)
        assertEquals(R.string.wind_moderate_breeze, Wind(0.0, 5.5).descriptor)
        assertEquals(R.string.wind_strong_breeze, Wind(0.0, 8.0).descriptor)
    }

    // Arrow

    @Test
    fun arrowRotationMatchesBearing() {
        assertEquals(247.0, Wind(247.0, 2.0).arrowRotation, 0.001)
    }

    // Strength

    @Test
    fun calmHasNoStrength() {
        assertEquals(0.0, Wind(0.0, 0.0).strengthFraction, 0.0)
    }

    @Test
    fun strengthIsProportionalWithinTheNamedRange() {
        assertEquals(0.25, Wind(0.0, 2.0).strengthFraction, 0.0001)
        assertEquals(0.5, Wind(0.0, 4.0).strengthFraction, 0.0001)
        assertEquals(0.75, Wind(0.0, 6.0).strengthFraction, 0.0001)
    }

    @Test
    fun strengthReachesOneAtStrongBreeze() {
        assertEquals(1.0, Wind(0.0, Wind.STRONG_BREEZE_THRESHOLD).strengthFraction, 0.0001)
    }

    /** A gale must not stretch the arrow past its marker. */
    @Test
    fun strengthClampsAboveStrongBreeze() {
        assertEquals(1.0, Wind(0.0, 25.0).strengthFraction, 0.0)
        assertEquals(1.0, Wind(0.0, 200.0).strengthFraction, 0.0)
    }

    @Test
    fun strengthNeverGoesNegative() {
        assertEquals(0.0, Wind(0.0, -5.0).strengthFraction, 0.0)
    }

    @Test
    fun strengthRisesMonotonicallyWithSpeed() {
        val fractions = listOf(0.0, 0.5, 1.4, 2.6, 4.0, 5.5, 8.0, 12.0).map { Wind(0.0, it).strengthFraction }
        fractions.zipWithNext().forEach { (lower, upper) -> assertTrue(lower <= upper) }
    }

    // Strength levels: the map's arrow bitmaps (FOX-91)

    @Test
    fun strengthLevelsBucketTheFractionForIconReuse() {
        assertEquals(0, Wind(0.0, 0.0).strengthLevel)
        assertEquals(5, Wind(0.0, 2.0).strengthLevel)
        assertEquals(Wind.STRENGTH_STEPS, Wind(0.0, 8.0).strengthLevel)
        assertEquals(Wind.STRENGTH_STEPS, Wind(0.0, 30.0).strengthLevel)
        // Any speed lands on one of STRENGTH_STEPS + 1 levels.
        val levels = (0..400).map { Wind(0.0, it / 20.0).strengthLevel }.toSet()
        assertEquals((0..Wind.STRENGTH_STEPS).toSet(), levels)
    }
}
