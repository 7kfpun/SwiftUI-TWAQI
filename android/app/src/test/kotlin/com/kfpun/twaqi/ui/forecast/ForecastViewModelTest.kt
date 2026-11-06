package com.kfpun.twaqi.ui.forecast

import com.kfpun.twaqi.data.Fixtures
import com.kfpun.twaqi.data.cache.CacheStore
import com.kfpun.twaqi.data.model.AqiForecast
import com.kfpun.twaqi.data.model.ForecastTabArea.Pin
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.remote.ApiClient
import com.kfpun.twaqi.data.remote.ApiConfig
import com.kfpun.twaqi.data.repository.ForecastRepository
import com.kfpun.twaqi.ui.main.GeoPoint
import com.kfpun.twaqi.ui.main.pollutant
import java.io.File
import java.time.Duration
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** The Forecast tab (iOS `ForecastViewModel`): its states, its order and its offline copy. */
@OptIn(ExperimentalCoroutinesApi::class)
class ForecastViewModelTest {
    @get:Rule val temp = TemporaryFolder()

    /** 12:00 on 6 November in Taiwan. */
    private var now = Instant.parse("2026-11-06T04:00:00Z")

    private val taipei = pollutant(1, lat = 25.04, lon = 121.51).copy(areaLocal = "北部空品區", countyLocal = "臺北市")
    private val chiayi = pollutant(2, lat = 23.48, lon = 120.44).copy(areaLocal = "雲嘉南空品區", countyLocal = "嘉義市")
    private val matsu = pollutant(3, lat = 26.16, lon = 119.95).copy(areaLocal = "其他", countyLocal = "連江縣")

    private class FakeSource(
        var rows: List<AqiForecast> = emptyList(),
        var stations: List<Pollutant> = emptyList(),
        var saved: List<Pollutant> = emptyList(),
        var allowed: Boolean = false,
        var location: GeoPoint? = null,
        val forecasts: (suspend () -> List<AqiForecast>)? = null
    ) : ForecastTabSource {
        var forecastCalls = 0
        override suspend fun forecasts(): List<AqiForecast> {
            forecastCalls += 1
            return forecasts?.invoke() ?: rows
        }
        override suspend fun stations() = stations
        override suspend fun savedPollutants(stationIds: List<Int>) = saved.filter { it.stationId in stationIds }
        override fun isLocationAllowed() = allowed
        override suspend fun location() = location
    }

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun row(area: String, date: String, aqi: Int = 50) =
        AqiForecast(area = area, forecastDate = date, aqi = aqi, publishTime = "2026-11-05 22:00:00")

    private val rows = listOf("北部", "雲嘉南", "馬祖").flatMap { area ->
        listOf("2026-11-05", "2026-11-06", "2026-11-07", "2026-11-08").map { row(area, it) }
    }

    private fun viewModel(source: ForecastTabSource, chinese: Boolean = true) =
        ForecastViewModel(source, chinese = { chinese }, now = { now })

    private fun loaded(viewModel: ForecastViewModel) = viewModel.uiState.value as ForecastUiState.Loaded

    /** The real HTTP client answers on its own thread. */
    private fun awaitLoaded(viewModel: ForecastViewModel): ForecastUiState.Loaded = runBlocking {
        withTimeout(5_000) { viewModel.uiState.first { it !is ForecastUiState.Loading } as ForecastUiState.Loaded }
    }

    @Test
    fun withoutLocationNorthIsFirstThenFavouritesThenTheRest() {
        val viewModel = viewModel(FakeSource(rows = rows, stations = listOf(taipei, chiayi, matsu)))
        viewModel.load(favouriteStationIds = listOf(3))

        val areas = loaded(viewModel).areas
        assertEquals(listOf("北部", "馬祖", "雲嘉南"), areas.map { it.area })
        assertEquals(listOf(Pin.FALLBACK, Pin.FAVOURITE, Pin.NONE), areas.map { it.pin })
        // Yesterday's day dropped; every day from today kept.
        assertEquals(
            listOf("2026-11-06", "2026-11-07", "2026-11-08"),
            areas.first().forecast.days.map {
                it.forecastDate
            }
        )
        assertEquals("北部空品區", areas.first().forecast.areaTitle)
        assertEquals("馬祖", areas[1].forecast.areaTitle)
    }

    @Test
    fun theReadersZoneComesFirst() {
        val source = FakeSource(
            rows = rows,
            stations = listOf(taipei, chiayi, matsu),
            allowed = true,
            location = GeoPoint(23.47, 120.45)
        )
        val viewModel = viewModel(source, chinese = false)
        viewModel.load(favouriteStationIds = listOf(1))

        val areas = loaded(viewModel).areas
        assertEquals(listOf("雲嘉南", "北部", "馬祖"), areas.map { it.area })
        assertEquals(listOf(Pin.READER, Pin.FAVOURITE, Pin.NONE), areas.map { it.pin })
        assertEquals("Yun-Chia-Nan", areas.first().forecast.areaTitle)
    }

    @Test
    fun aFavouriteNotReportingIsNamedFromItsSavedReading() {
        val viewModel = viewModel(FakeSource(rows = rows, stations = listOf(taipei), saved = listOf(chiayi)))
        viewModel.load(favouriteStationIds = listOf(2))

        assertEquals(listOf(Pin.FALLBACK, Pin.FAVOURITE), loaded(viewModel).areas.take(2).map { it.pin })
        assertEquals("雲嘉南", loaded(viewModel).areas[1].area)
    }

    @Test
    fun favouritesChangedSinceTheLastVisitRepinAtOnce() {
        val viewModel = viewModel(FakeSource(rows = rows, stations = listOf(taipei, chiayi, matsu)))
        viewModel.load(favouriteStationIds = listOf(3))
        assertEquals("馬祖", loaded(viewModel).areas[1].area)

        viewModel.load(favouriteStationIds = listOf(2))
        assertEquals("雲嘉南", loaded(viewModel).areas[1].area)
        assertEquals(Pin.FAVOURITE, loaded(viewModel).areas[1].pin)
    }

    @Test
    fun theDayTurnsOverAtTaiwanMidnight() {
        val viewModel = viewModel(FakeSource(rows = rows))
        // 23:59 on 6 November in Taiwan.
        now = Instant.parse("2026-11-06T15:59:00Z")
        viewModel.load(emptyList())
        assertEquals("2026-11-06", loaded(viewModel).areas.first().forecast.days.first().forecastDate)

        // 00:00 on the 7th in Taiwan, still the 6th in UTC and most of the world.
        now = Instant.parse("2026-11-06T16:00:00Z")
        viewModel.load(emptyList())
        assertEquals(
            listOf("2026-11-07", "2026-11-08"),
            loaded(viewModel).areas.first().forecast.days.map {
                it.forecastDate
            }
        )
    }

    @Test
    fun nothingFetchedAndNothingSavedIsTheOfflineEmptyState() {
        val viewModel = viewModel(FakeSource())
        assertEquals(ForecastUiState.Loading, viewModel.uiState.value)
        viewModel.load(emptyList())
        assertEquals(ForecastUiState.Empty, viewModel.uiState.value)
    }

    @Test
    fun aSavedCopyWithNothingFromTodayOnIsNoCurrentForecast() {
        now = Instant.parse("2026-11-10T04:00:00Z")
        val viewModel = viewModel(FakeSource(rows = rows))
        viewModel.load(emptyList())
        assertEquals(ForecastUiState.NoCurrentForecast, viewModel.uiState.value)
    }

    @Test
    fun aReloadThatFindsNothingKeepsTheLastRows() {
        val source = FakeSource(rows = rows)
        val viewModel = viewModel(source)
        viewModel.load(emptyList())
        source.rows = emptyList()
        viewModel.load(emptyList())

        assertEquals(2, source.forecastCalls)
        assertEquals(3, loaded(viewModel).areas.size)
    }

    @Test
    fun sharedParagraphIsShownOnceAboveTheCards() {
        val text = "今（5）日環境風場為偏東風轉東北風。"
        val viewModel = viewModel(FakeSource(rows = rows.map { it.copy(content = text) }))
        viewModel.load(emptyList())
        assertEquals(text, loaded(viewModel).sharedContent)
    }

    /** The tab over the real repository and cache: a relaunch offline shows the saved forecast. */
    @Test
    fun offlineRelaunchShowsTheSavedForecast() {
        val server = MockWebServer().apply { start() }
        try {
            val base = server.url("/").toString()
            val http = OkHttpClient.Builder().callTimeout(5, TimeUnit.SECONDS).build()
            val api = ApiClient(ApiConfig(apiDomain = base, directusUrl = base, directusToken = "test-token"), http)
            val root = File(temp.root, "offline-cache")
            fun repository() = ForecastRepository(
                api,
                CacheStore(root) {
                    now
                },
                now = { now },
                io = Dispatchers.Unconfined
            )
            fun tab(repository: ForecastRepository) =
                viewModel(FakeSource(forecasts = { repository.forecasts().valueOrNull.orEmpty() }))

            server.enqueue(
                MockResponse().setHeader("Content-Type", "application/json; charset=utf-8").setBody(Fixtures.forecast)
            )
            val online = tab(repository())
            online.load(emptyList())
            assertEquals(listOf("北部", "雲嘉南", "馬祖"), awaitLoaded(online).areas.map { it.area })

            // An hour later, past the TTL, in a new process and offline.
            now = now.plus(Duration.ofHours(1))
            server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AT_START))
            val offline = tab(repository())
            offline.load(emptyList())
            val areas = awaitLoaded(offline).areas
            assertEquals(listOf("北部", "雲嘉南", "馬祖"), areas.map { it.area })
            assertTrue(areas.all { it.forecast.publishedAt == Instant.parse("2026-11-05T14:00:00Z") })
        } finally {
            server.shutdown()
        }
    }
}
