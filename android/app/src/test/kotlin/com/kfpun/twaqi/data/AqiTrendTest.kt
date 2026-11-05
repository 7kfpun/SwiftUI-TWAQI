package com.kfpun.twaqi.data

import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AqiTrend
import com.kfpun.twaqi.data.model.AqiTrendDirection.IMPROVING
import com.kfpun.twaqi.data.model.AqiTrendDirection.STEADY
import com.kfpun.twaqi.data.model.AqiTrendDirection.WORSENING
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ported from iOS `AqiTrendTests`. */
class AqiTrendTest {
    private fun trend(vararg values: Double) = AqiTrend.from(values.toList())

    @Test
    fun tooLittleHistoryHasNoTrend() {
        assertNull(AqiTrend.from(emptyList()))
        assertNull(trend(65.0))
    }

    @Test
    fun fallingAqiIsImproving() {
        val t = trend(90.0, 88.0, 86.0, 84.0, 80.0, 76.0, 70.0, 64.0, 60.0, 56.0, 52.0, 50.0)
        assertEquals(IMPROVING, t?.direction)
        assertTrue(t!!.change > 0)
    }

    @Test
    fun risingAqiIsWorsening() {
        val t = trend(50.0, 52.0, 56.0, 60.0, 64.0, 70.0, 76.0, 80.0, 84.0, 86.0, 88.0, 90.0)
        assertEquals(WORSENING, t?.direction)
        assertTrue(t!!.change > 0)
    }

    @Test
    fun flatAqiIsSteady() {
        val t = AqiTrend.from(List(12) { 65.0 })
        assertEquals(STEADY, t?.direction)
        assertEquals(0, t?.change)
    }

    @Test
    fun movementBelowThresholdIsSteady() {
        assertEquals(STEADY, trend(60.0, 60.0, 60.0, 61.0, 61.0, 61.0, 62.0, 62.0, 62.0, 63.0, 63.0, 63.0)?.direction)
    }

    @Test
    fun movementPastThresholdIsNotSteady() {
        val t = trend(60.0, 60.0, 60.0, 60.0, 60.0, 60.0, 60.0, 60.0, 60.0, 66.0, 66.0, 66.0)
        assertEquals(WORSENING, t?.direction)
        assertEquals(6, t?.change)
    }

    /** One bad hour in an improving day must not flip the verdict. */
    @Test
    fun singleSpikeDoesNotFlipDirection() {
        val values = mutableListOf(90.0, 88.0, 86.0, 84.0, 80.0, 76.0, 70.0, 64.0, 60.0, 56.0, 52.0, 50.0)
        values[8] = 150.0
        assertEquals(IMPROVING, AqiTrend.from(values)?.direction)
    }

    @Test
    fun sustainedRiseAtTheEndIsWorsening() {
        assertEquals(
            WORSENING,
            trend(50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 120.0, 130.0, 140.0)?.direction
        )
    }

    @Test
    fun currentIsMeanOfMostRecentWindow() {
        assertEquals(
            40.0,
            trend(10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 30.0, 40.0, 50.0)!!.current,
            0.001
        )
    }

    @Test
    fun changeIsAbsoluteSoDirectionCarriesTheSign() {
        assertEquals(40, trend(80.0, 80.0, 80.0, 80.0, 80.0, 80.0, 80.0, 80.0, 80.0, 40.0, 40.0, 40.0)?.change)
        assertEquals(40, trend(40.0, 40.0, 40.0, 40.0, 40.0, 40.0, 40.0, 40.0, 40.0, 80.0, 80.0, 80.0)?.change)
    }

    /** Fewer than nine readings: compared against the oldest three. */
    @Test
    fun shortSeriesFallsBackToOldestReadings() {
        val t = trend(100.0, 100.0, 100.0, 50.0, 50.0, 50.0)
        assertEquals(IMPROVING, t?.direction)
        assertEquals(50, t?.change)
    }

    @Test
    fun twoReadingsProduceATrend() {
        assertNotNull(trend(100.0, 40.0))
    }

    @Test
    fun magnitudeSurvivesSubPointChanges() {
        val t = AqiTrend.from(listOf(0.20, 0.20, 0.20, 0.20, 0.20, 0.20, 0.16, 0.16, 0.16), steadyThreshold = 0.01)
        assertEquals(IMPROVING, t?.direction)
        assertEquals(0.04, t!!.magnitude, 0.0001)
        assertEquals("a 0.04 move rounds away in whole points", 0, t.change)
    }

    @Test
    fun changeIsMagnitudeRounded() {
        val t = trend(40.0, 40.0, 40.0, 40.0, 40.0, 40.0, 52.0, 52.0, 52.0)
        assertEquals(12, t?.change)
        assertEquals(12.0, t!!.magnitude, 0.0001)
    }

    @Test
    fun thresholdDecidesSteadyVersusMoving() {
        val values = listOf(10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 14.0, 14.0, 14.0)
        assertEquals(STEADY, AqiTrend.from(values, steadyThreshold = 5.0)?.direction)
        assertEquals(WORSENING, AqiTrend.from(values, steadyThreshold = 1.0)?.direction)
        assertEquals(
            AqiTrend.from(values, steadyThreshold = AqiTrend.STEADY_THRESHOLD)?.direction,
            AqiTrend.from(values)?.direction
        )
    }

    @Test
    fun relativeThresholdIsATenthOfTheAverage() {
        assertEquals(2.0, AqiTrend.relativeThreshold(listOf(10.0, 20.0, 30.0)), 0.0001)
        assertEquals(0.018, AqiTrend.relativeThreshold(listOf(0.16, 0.20, 0.18)), 0.0001)
        assertEquals(1.8, AqiTrend.relativeThreshold(listOf(16.0, 20.0, 18.0)), 0.0001)
    }

    /** A pollutant a station doesn't measure (all 0.0) is never "improving". */
    @Test
    fun allZeroReadingsAreNeverATrend() {
        val threshold = AqiTrend.relativeThreshold(listOf(0.0, 0.0, 0.0))
        assertEquals(STEADY, AqiTrend.from(listOf(0.0, 0.0, 0.0, 0.0), threshold)?.direction)
        assertEquals(Double.MAX_VALUE, AqiTrend.relativeThreshold(emptyList()), 0.0)
    }

    @Test
    fun indexTypePicksTheThreshold() {
        // CO: a 0.04 ppm fall on ~0.18 is past a tenth of the average.
        val co = listOf(0.20, 0.20, 0.20, 0.20, 0.20, 0.20, 0.16, 0.16, 0.16)
        assertEquals(IMPROVING, AqiTrend.from(co, AirIndexType.CO)?.direction)
        // AQI keeps the 5-point band.
        assertEquals(STEADY, AqiTrend.from(listOf(60.0, 60.0, 60.0, 63.0, 63.0, 63.0), AirIndexType.AQI)?.direction)
    }
}
