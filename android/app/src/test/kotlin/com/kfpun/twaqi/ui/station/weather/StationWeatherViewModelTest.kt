package com.kfpun.twaqi.ui.station.weather

import com.kfpun.twaqi.data.Fixtures
import com.kfpun.twaqi.data.weather.StationWeather
import com.kfpun.twaqi.data.weather.WeatherFile
import com.kfpun.twaqi.data.weather.WeatherPeriod
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

/** The card is there only when something is in range, and the first match stays (iOS `findWeather`). */
@OptIn(ExperimentalCoroutinesApi::class)
class StationWeatherViewModelTest {
    private val now = Instant.parse("2026-11-05T04:40:00Z")
    private val file = WeatherFile.parse(Fixtures.read("weather-latest.json"))
    private var loads = 0

    private val zhongshan = WeatherQuery(25.062361, 121.526528, "Taipei City", "臺北市")
    private val hualien = WeatherQuery(23.971306, 121.599769, "Hualien County", "花蓮縣")
    private val lanyu = WeatherQuery(22.03, 121.55, "Taitung County", "臺東縣")

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun viewModel(file: WeatherFile? = this.file) = StationWeatherViewModel(
        load = {
            loads += 1
            file
        },
        now = { now }
    )

    @Test
    fun nothingInRangeHidesTheCard() {
        val viewModel = viewModel()
        viewModel.find(listOf(lanyu))
        assertNull(viewModel.card.value)
    }

    @Test
    fun noFileHidesTheCard() {
        val viewModel = viewModel(file = null)
        viewModel.find(listOf(zhongshan))
        assertNull(viewModel.card.value)
    }

    @Test
    fun firstMatchWinsAndStays() {
        val viewModel = viewModel()
        viewModel.find(listOf(lanyu, zhongshan))
        val card = viewModel.card.value!!
        assertEquals("466920", card.weather.now?.observation?.id)
        assertEquals("Taipei City", card.countyTitle(chinese = false))
        assertEquals("臺北市", card.countyTitle(chinese = true))

        viewModel.find(listOf(hualien))
        assertEquals(card, viewModel.card.value)
        assertEquals(1, loads)
    }

    @Test
    fun headingNamesTheCountyOnlyOverAForecast() {
        val card = viewModel().apply { find(listOf(zhongshan)) }.card.value!!
        assertEquals("Taipei City", headingCounty(card, chinese = false))
        assertEquals("臺北市", headingCounty(card, chinese = true))

        // No county name of its own: CWA's in Chinese, none in English.
        val unnamed = card.copy(county = null, countyLocal = null)
        assertEquals("臺北市", headingCounty(unnamed, chinese = true))
        assertNull(headingCounty(unnamed, chinese = false))

        // A reading without a forecast has no county to label.
        val readingOnly = card.copy(weather = StationWeather(card.weather.now, null, emptyList<WeatherPeriod>()))
        assertNull(headingCounty(readingOnly, chinese = true))
    }
}
