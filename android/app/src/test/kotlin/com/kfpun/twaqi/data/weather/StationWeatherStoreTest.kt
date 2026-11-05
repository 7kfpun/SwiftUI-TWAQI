package com.kfpun.twaqi.data.weather

import com.kfpun.twaqi.data.cache.CacheStore
import com.kfpun.twaqi.data.cache.OfflineCacheRetention
import java.io.File
import java.time.Duration
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Ported from iOS `StationWeatherStoreTests`: the last good file is kept, and nothing a week old is shown. */
class StationWeatherStoreTest {
    @get:Rule val temp = TemporaryFolder()

    private lateinit var server: MockWebServer
    private var now = Instant.parse("2026-11-05T04:40:00Z")
    private val root get() = File(temp.root, OfflineCacheRetention.ROOT_DIRECTORY)
    private val cacheFile get() = File(root, StationWeatherStore.CACHE_FILE)

    private val body = """
        { "version": 1, "updatedAt": "2026-11-05T04:40:00.000Z", "forecast": null,
          "observations": { "fetchedAt": "2026-11-05T04:40:00.000Z", "stations": [
            { "id": "466920", "name": "臺北", "county": "臺北市", "lat": 25.03766, "lon": 121.51485,
              "time": "2026-11-05T12:00:00+08:00", "temp": 24.3, "humidity": 75, "rain": 0.5, "wind": 3.2 } ] } }
    """.trimIndent()

    @Before
    fun setUp() {
        server = MockWebServer().apply { start() }
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    /** A fresh store over the same cache root: what a relaunch sees. */
    private fun store(): StationWeatherStore = StationWeatherStore(
        baseUrl = server.url("/").toString(),
        store = CacheStore(root) { now },
        http = OkHttpClient.Builder().callTimeout(5, TimeUnit.SECONDS).build(),
        now = { now },
        io = Dispatchers.Unconfined
    )

    private fun ok(text: String = body, code: Int = 200) =
        MockResponse().setResponseCode(code).setHeader("Content-Type", "application/json").setBody(text)

    private fun offline() = MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AT_START)

    @Test
    fun fetchedFileIsSavedAndReadBackOffline() = runBlocking {
        server.enqueue(ok())
        assertEquals(1, store().weather()?.observations?.stations?.size)
        assertEquals("/weather/latest.json", server.takeRequest().path)
        assertTrue(cacheFile.isFile)

        // A new launch, offline, past the TTL: the saved file answers.
        now = now.plus(StationWeatherStore.TTL).plusSeconds(60)
        server.enqueue(offline())
        assertEquals("466920", store().weather()?.observations?.stations?.first()?.id)
    }

    @Test
    fun withinTheTtlNoSecondRequest() = runBlocking {
        server.enqueue(ok())
        val store = store()
        store.weather()
        store.weather()
        // A relaunch inside the TTL reads the saved file without asking either.
        now = now.plus(Duration.ofMinutes(10))
        store().weather()
        assertEquals(1, server.requestCount)
    }

    @Test
    fun badBodyIsNotSavedAndNothingShows() = runBlocking {
        server.enqueue(ok("<html>busy</html>"))
        assertNull(store().weather())
        assertFalse(cacheFile.exists())

        server.enqueue(ok(code = 404))
        assertNull(store().weather())
        assertFalse(cacheFile.exists())
    }

    @Test
    fun failedRefreshKeepsTheLastGoodFileAndAsksAgainNextTime() = runBlocking {
        server.enqueue(ok())
        val store = store()
        store.weather()
        now = now.plus(StationWeatherStore.TTL)
        server.enqueue(ok("<html>busy</html>"))
        assertEquals("466920", store.weather()?.observations?.stations?.first()?.id)
        server.enqueue(ok())
        store.weather()
        assertEquals(3, server.requestCount)
    }

    @Test
    fun savedFileOlderThanAWeekIsNotRead() = runBlocking {
        server.enqueue(ok())
        store().weather()

        now = now.plus(OfflineCacheRetention.maxAge).plusSeconds(60)
        server.enqueue(offline())
        assertNull(store().weather())
    }

    @Test
    fun cacheFileIsUnderTheRootThePurgeScans() = runBlocking {
        server.enqueue(ok())
        store().weather()
        assertEquals(root, cacheFile.parentFile)
        assertEquals(
            listOf(cacheFile),
            OfflineCacheRetention.purge(root, now.plus(OfflineCacheRetention.maxAge).plusSeconds(1))
        )
    }

    @Test
    fun withoutAHostOnlyTheSavedFileIsRead() = runBlocking {
        assertNull(StationWeatherStore.fileUrl(""))
        assertEquals(
            "https://cams.example.com/weather/latest.json",
            StationWeatherStore.fileUrl("https://cams.example.com/").toString()
        )
        val store = StationWeatherStore("", CacheStore(root) { now }, now = { now }, io = Dispatchers.Unconfined)
        assertNull(store.weather())
        assertEquals(0, server.requestCount)
    }
}
