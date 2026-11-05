package com.kfpun.twaqi.ui.station.forecast

import com.kfpun.twaqi.data.model.AqiForecast
import com.kfpun.twaqi.data.model.Station
import com.kfpun.twaqi.ui.main.pollutant
import com.kfpun.twaqi.ui.station.StationDetailsUiState
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

/** The station page's zone forecast (iOS `DetailsViewModel.findForecast`). */
@OptIn(ExperimentalCoroutinesApi::class)
class StationForecastViewModelTest {
    private var now = Instant.parse("2026-11-06T04:00:00Z")
    private var loads = 0

    private val rows = listOf("北部", "馬祖").flatMap { area ->
        listOf("2026-11-05", "2026-11-06", "2026-11-07", "2026-11-08", "2026-11-09").map {
            AqiForecast(area = area, forecastDate = it, aqi = 60, publishTime = "2026-11-05 22:00:00")
        }
    }

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun viewModel(rows: List<AqiForecast> = this.rows) = StationForecastViewModel(
        load = {
            loads += 1
            rows
        },
        now = { now }
    )

    @Test
    fun theStationsZoneTodayOnwardsAtMostThreeDays() {
        val viewModel = viewModel()
        viewModel.find(listOf(ForecastQuery("北部空品區", "臺北市", "北部空品區")))

        val forecast = viewModel.forecast.value!!
        assertEquals("北部空品區", forecast.areaTitle)
        assertEquals(listOf("2026-11-06", "2026-11-07", "2026-11-08"), forecast.days.map { it.forecastDate })
    }

    @Test
    fun todayIsTheTaiwanDay() {
        // 00:30 on 7 November in Taiwan; still the 6th in UTC.
        now = Instant.parse("2026-11-06T16:30:00Z")
        val viewModel = viewModel()
        viewModel.find(listOf(ForecastQuery("北部空品區", "臺北市", "Northern")))

        val forecast = viewModel.forecast.value!!
        assertEquals("Northern", forecast.areaTitle)
        assertEquals(listOf("2026-11-07", "2026-11-08", "2026-11-09"), forecast.days.map { it.forecastDate })
    }

    @Test
    fun anIslandStationIsMatchedByItsCounty() {
        val viewModel = viewModel()
        viewModel.find(listOf(ForecastQuery("其他", "連江縣", "其他")))
        assertEquals(setOf("馬祖"), viewModel.forecast.value!!.days.map { it.area }.toSet())
    }

    @Test
    fun noZoneOrNothingCurrentShowsNoCard() {
        val viewModel = viewModel()
        viewModel.find(listOf(ForecastQuery("中部空品區", "臺中市", null)))
        assertNull(viewModel.forecast.value)

        now = Instant.parse("2026-11-12T04:00:00Z")
        val old = viewModel()
        old.find(listOf(ForecastQuery("北部空品區", "臺北市", null)))
        assertNull(old.forecast.value)

        val offline = viewModel(rows = emptyList())
        offline.find(listOf(ForecastQuery("北部空品區", "臺北市", null)))
        assertNull(offline.forecast.value)
    }

    @Test
    fun theFirstMatchStays() {
        val viewModel = viewModel()
        viewModel.find(listOf(ForecastQuery("北部空品區", "臺北市", "北部空品區")))
        viewModel.find(listOf(ForecastQuery("其他", "連江縣", "其他")))
        assertEquals("北部空品區", viewModel.forecast.value!!.areaTitle)
        assertEquals(1, loads)
    }

    @Test
    fun queriesComeFromTheReadingThenTheRecord() {
        val reading = pollutant(1).copy(area = "Northern", areaLocal = "北部空品區", countyLocal = "臺北市")
        val record = Station(
            id = 1, countryId = 1, countryCode = "twn", code = "s1", lat = 25.0, lon = 121.5, imageUrl = null,
            name = "Station", nameLocal = "測站", area = "Northern", areaLocal = "北部空品區", countyLocal = "臺北市"
        )
        val state = StationDetailsUiState(stationId = 1, station = record, pollutant = reading)
        assertEquals(listOf(ForecastQuery("北部空品區", "臺北市", "北部空品區")), ForecastQuery.from(state, chinese = true))
        assertEquals(listOf(ForecastQuery("北部空品區", "臺北市", "Northern")), ForecastQuery.from(state, chinese = false))
        // Nothing loaded yet, or nowhere to place it: no query.
        assertEquals(
            emptyList<ForecastQuery>(),
            ForecastQuery.from(StationDetailsUiState(stationId = 1), chinese = true)
        )
    }
}
