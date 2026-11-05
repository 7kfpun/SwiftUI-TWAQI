package com.kfpun.twaqi.data

import com.kfpun.twaqi.data.cache.CacheStore
import com.kfpun.twaqi.data.cache.PollutantCache
import com.kfpun.twaqi.data.remote.ApiClient
import com.kfpun.twaqi.data.remote.ApiConfig
import com.kfpun.twaqi.data.repository.AirQualityRepository
import com.kfpun.twaqi.data.repository.DataResult
import com.kfpun.twaqi.data.repository.ForecastRepository
import java.io.File
import java.time.Duration
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
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

/**
 * The repositories against a local server serving the recorded fixtures: online they save what
 * they fetch, and offline they fall back to it (the FOX-53 "done when").
 */
class RepositoryTest {
    @get:Rule val temp = TemporaryFolder()

    private lateinit var server: MockWebServer
    private var now = Instant.parse("2026-11-06T04:00:00Z")
    private val root get() = File(temp.root, "offline-cache")

    @Before
    fun setUp() {
        server = MockWebServer().apply { start() }
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    private fun client(): ApiClient {
        val base = server.url("/").toString()
        val http = OkHttpClient.Builder().callTimeout(5, TimeUnit.SECONDS).build()
        return ApiClient(ApiConfig(apiDomain = base, directusUrl = base, directusToken = "test-token"), http)
    }

    /** A fresh repository over the same cache root: what a relaunch sees. */
    private fun airQuality(): AirQualityRepository {
        val store = CacheStore(root) { now }
        return AirQualityRepository(client(), store, PollutantCache(store) { now }, now = { now })
    }

    private fun forecasts() = ForecastRepository(client(), CacheStore(root) { now }, now = { now })

    private fun json(body: String) =
        MockResponse().setHeader("Content-Type", "application/json; charset=utf-8").setBody(body)

    private fun offline() = MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AT_START)

    @Test
    fun stationsAndReadingsLoadOnlineAndFallBackToTheCacheOffline() = runBlocking {
        server.enqueue(json(Fixtures.stations))
        server.enqueue(json(Fixtures.currentPollutants))
        val online = airQuality()
        val stations = online.stations("twn")
        val readings = online.currentPollutants("twn")
        assertTrue(stations is DataResult.Fresh)
        assertTrue(readings is DataResult.Fresh)
        assertEquals(3, stations.valueOrNull?.size)
        assertEquals(listOf(91, 876, 115), readings.valueOrNull?.map { it.stationId })

        assertEquals("/v1/stations?country=twn", server.takeRequest().path)
        assertEquals("/v1/current-pollutants?country=twn", server.takeRequest().path)

        // Relaunch offline, an hour later.
        now = now.plus(Duration.ofHours(1))
        server.enqueue(offline())
        server.enqueue(offline())
        server.enqueue(offline())
        val offline = airQuality()
        val savedStations = offline.stations("twn")
        val savedReadings = offline.currentPollutants("twn")
        val savedStation = offline.currentPollutant(876)

        assertTrue(savedStations is DataResult.Stale)
        assertEquals(3, savedStations.valueOrNull?.size)
        assertTrue(savedReadings is DataResult.Stale)
        assertEquals(listOf(91, 876, 115), savedReadings.valueOrNull?.map { it.stationId })
        assertEquals(Instant.parse("2026-11-06T04:00:00Z"), (savedReadings as DataResult.Stale).savedAt)
        // A station the country list showed opens offline too.
        assertEquals(87.0, (savedStation as DataResult.Stale).value.aqi, 0.0)
    }

    @Test
    fun nothingSavedAndOfflineFails() = runBlocking {
        server.enqueue(offline())
        server.enqueue(MockResponse().setResponseCode(503).setBody("busy"))
        assertTrue(airQuality().stations("twn") is DataResult.Failed)
        assertTrue(airQuality().currentPollutants("twn") is DataResult.Failed)
    }

    /** A proxy's HTML page or a `success: false` must not replace the saved copy. */
    @Test
    fun badBodiesAreNotSavedAndFallBack() = runBlocking {
        server.enqueue(json(Fixtures.currentPollutants))
        airQuality().currentPollutants("twn")

        server.enqueue(MockResponse().setHeader("Content-Type", "text/html").setBody("<html>gateway timeout</html>"))
        server.enqueue(json("""{"success": false, "data": []}"""))
        assertTrue(airQuality().currentPollutants("twn") is DataResult.Stale)
        assertTrue(airQuality().currentPollutants("twn") is DataResult.Stale)

        server.enqueue(offline())
        assertEquals(3, airQuality().currentPollutants("twn").valueOrNull?.size)
    }

    /** An empty list never wipes the saved one. */
    @Test
    fun emptyStationListKeepsTheSavedOne() = runBlocking {
        server.enqueue(json(Fixtures.stations))
        airQuality().stations("twn")
        server.enqueue(json("""{"success": true, "data": []}"""))
        val result = airQuality().stations("twn")
        assertTrue(result is DataResult.Stale)
        assertEquals(3, result.valueOrNull?.size)
    }

    @Test
    fun savedCopyOlderThanAWeekIsNotUsed() = runBlocking {
        server.enqueue(json(Fixtures.stations))
        airQuality().stations("twn")
        now = now.plus(Duration.ofDays(8))
        server.enqueue(offline())
        assertTrue(airQuality().stations("twn") is DataResult.Failed)
    }

    @Test
    fun countriesAndHistory() = runBlocking {
        server.enqueue(json(Fixtures.countries))
        server.enqueue(json(Fixtures.historicalPollutants))
        val repository = airQuality()
        assertEquals(7, repository.countries().valueOrNull?.size)
        val history = repository.history(91)
        assertEquals(12, history.valueOrNull?.readings?.size)
        server.takeRequest()
        assertEquals("/v1/historical-pollutants?station_id=91&limit=24", server.takeRequest().path)

        // History isn't cached, as on iOS.
        server.enqueue(offline())
        assertTrue(repository.history(91) is DataResult.Failed)
        server.enqueue(offline())
        assertEquals(7, repository.countries().valueOrNull?.size)
    }

    @Test
    fun forecastUsesTheTtlThenFallsBack() = runBlocking {
        server.enqueue(json(Fixtures.forecast))
        val repository = forecasts()
        assertTrue(repository.forecasts() is DataResult.Fresh)
        val request = server.takeRequest()
        assertEquals("Bearer test-token", request.getHeader("Authorization"))
        assertEquals("2026-11-06", request.requestUrl?.queryParameter("filter[forecast_date][_gte]"))

        // Within 30 minutes: no request.
        now = now.plus(Duration.ofMinutes(10))
        assertEquals(9, repository.forecasts().valueOrNull?.size)
        assertEquals(1, server.requestCount)

        // Past the TTL and offline: the last good rows.
        now = now.plus(Duration.ofMinutes(30))
        server.enqueue(offline())
        assertTrue(repository.forecasts() is DataResult.Stale)

        // A relaunch reads them from disk.
        server.enqueue(offline())
        assertEquals(9, forecasts().forecasts().valueOrNull?.size)
    }

    /** No rows counts as a failed refresh: never saved, and the next call asks again. */
    @Test
    fun emptyForecastIsAFailedRefresh() = runBlocking {
        server.enqueue(json("""{"data": []}"""))
        assertTrue(forecasts().forecasts() is DataResult.Failed)
        server.enqueue(json(Fixtures.forecast))
        server.enqueue(json("""{"data": []}"""))
        val repository = forecasts()
        assertTrue(repository.forecasts() is DataResult.Fresh)
        now = now.plus(Duration.ofHours(1))
        val stale = repository.forecasts()
        assertTrue(stale is DataResult.Stale)
        assertEquals(9, stale.valueOrNull?.size)
    }
}
