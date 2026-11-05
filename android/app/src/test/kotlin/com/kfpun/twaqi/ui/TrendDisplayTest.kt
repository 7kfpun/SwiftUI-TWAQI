package com.kfpun.twaqi.ui

import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.AqiTrendDirection
import com.kfpun.twaqi.data.model.HistoricalPollutant
import com.kfpun.twaqi.ui.station.HistoryChart
import com.kfpun.twaqi.ui.station.TrendDisplay
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `TrendVerdict` and the `DetailsHistoryView` numbers. */
class TrendDisplayTest {
    @Test
    fun fewerThanTwoReadingsIsSteadyWithNoDetail() {
        val display = TrendDisplay.of(listOf(40.0), AirIndexType.AQI)
        assertEquals(AqiTrendDirection.STEADY, display.direction)
        assertEquals(R.string.details_trend_steady, display.title)
        assertEquals(TrendDisplay.Detail.None, display.detail)
        assertNull(display.tint)
    }

    @Test
    fun aqiImprovingIsGreenWithWholePoints() {
        val display = TrendDisplay.of(listOf(80.0, 80.0, 80.0, 60.0, 60.0, 60.0), AirIndexType.AQI)
        assertEquals(AqiTrendDirection.IMPROVING, display.direction)
        assertEquals(R.string.details_trend_improving, display.title)
        assertEquals(TrendDisplay.Detail.Points(R.string.details_trend_improving_detail, 20), display.detail)
        assertEquals(AirStatus.GOOD.color, display.tint)
    }

    @Test
    fun aqiWorseningTakesTheCurrentBandColour() {
        val display = TrendDisplay.of(listOf(90.0, 90.0, 90.0, 160.0, 160.0, 160.0), AirIndexType.AQI)
        assertEquals(AqiTrendDirection.WORSENING, display.direction)
        assertEquals(R.string.details_trend_worsening, display.title)
        assertEquals(TrendDisplay.Detail.Points(R.string.details_trend_worsening_detail, 70), display.detail)
        assertEquals(AirStatus.UNHEALTHY.color, display.tint)
    }

    @Test
    fun aqiSteadySaysWhereItIsHolding() {
        val display = TrendDisplay.of(listOf(42.0, 43.0, 44.0, 44.0), AirIndexType.AQI)
        assertEquals(AqiTrendDirection.STEADY, display.direction)
        assertEquals(TrendDisplay.Detail.Points(R.string.details_trend_steady_detail, 44), display.detail)
        assertNull(display.tint)
    }

    @Test
    fun pollutantChangeIsAShareOfTheEarlierReading() {
        // PM2.5 from 20 to 15: down 25%.
        val improving = TrendDisplay.of(listOf(20.0, 20.0, 20.0, 15.0, 15.0, 15.0), AirIndexType.PM25)
        assertEquals(AqiTrendDirection.IMPROVING, improving.direction)
        assertEquals(TrendDisplay.Detail.Text("−25%"), improving.detail)

        val worsening = TrendDisplay.of(listOf(0.2, 0.2, 0.2, 0.3, 0.3, 0.3), AirIndexType.CO)
        assertEquals(AqiTrendDirection.WORSENING, worsening.direction)
        assertEquals(TrendDisplay.Detail.Text("+50%"), worsening.detail)
    }

    @Test
    fun pollutantSteadyShowsTheValueInItsUnit() {
        val display = TrendDisplay.of(listOf(41.0, 41.2, 41.1), AirIndexType.O3)
        assertEquals(AqiTrendDirection.STEADY, display.direction)
        assertEquals(TrendDisplay.Detail.Text("41.1 ppb"), display.detail)
    }

    @Test
    fun chartKeepsTheLast24HoursNewestLast() {
        val history = (1..30).map { reading(it.toDouble(), "2026-11-05T%02d:00:00".format(it % 24)) }
        val chart = HistoryChart.of(history, AirIndexType.AQI)
        assertEquals(24, chart.values.size)
        assertEquals(7.0, chart.values.first(), 0.0)
        assertEquals(30.0, chart.values.last(), 0.0)
        assertEquals(7.0, chart.lowest, 0.0)
        assertEquals(30.0, chart.highest, 0.0)
        assertEquals(18.5, chart.average, 1e-9)
        assertTrue(chart.hasTrend)
    }

    @Test
    fun barsAreScaledToTheDaysOwnRange() {
        val chart = HistoryChart(listOf(60.0, 75.0, 89.0), listOf("", "", ""))
        val low = chart.barFraction(60.0)
        val high = chart.barFraction(89.0)
        assertTrue(low >= HistoryChart.MIN_BAR)
        assertTrue(high <= 1.0)
        // Not a flat wall: the lowest bar is well under half the highest.
        assertTrue(low < high / 2)
        // A flat day still draws visible bars.
        val flat = HistoryChart(listOf(0.33, 0.33), listOf("", ""))
        assertTrue(flat.barFraction(0.33) > HistoryChart.MIN_BAR)
        assertFalse(HistoryChart(listOf(1.0), listOf("")).hasTrend)
    }

    private fun reading(aqi: Double, time: String) =
        HistoricalPollutant(aqi, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, time)
}
