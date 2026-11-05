package com.kfpun.twaqi.data.cams

import com.kfpun.twaqi.data.Fixtures
import com.kfpun.twaqi.data.cache.CacheStore
import com.kfpun.twaqi.data.cache.OfflineCacheRetention
import java.io.File
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The manifest store and the two frame caches against a local server: a missing hour is a plain
 * 404 (missing, not an error), saved frames stand in offline, and everything sits under the
 * offline cache root, where the week-old purge reaches it.
 */
class StationCamCachesTest {
    @get:Rule val temp = TemporaryFolder()

    private lateinit var server: MockWebServer
    private var now = Instant.parse("2026-10-30T14:40:00Z") // 22:40 in Taiwan
    private val http = OkHttpClient()
    private val root: File by lazy { File(temp.root, OfflineCacheRetention.ROOT_DIRECTORY) }
    private val camDirectory: File by lazy { File(root, StationCamFrameCache.DIRECTORY_NAME) }
    private val historyDirectory: File by lazy { File(camDirectory, StationCamHistoryCache.DIRECTORY_NAME) }

    private val cam = StationCam("001", "基隆", 25.129167, 121.760056, "2026-10-30T22:30:00+08:00")
    private val hour = StationCamHour("001", Instant.parse("2026-10-30T13:00:00Z")) // 21:00 in Taiwan

    /** "JPEG…" bodies are images; anything else isn't. Thumbnails are marked so tests can tell them apart. */
    private object TextDecoder : CamImageDecoder<String> {
        override fun full(bytes: ByteArray): String? = bytes.decodeToString().takeIf { it.startsWith("JPEG") }

        override fun thumbnail(bytes: ByteArray, maxPixelSize: Int): String? = full(bytes)?.let {
            "thumb($maxPixelSize):$it"
        }
    }

    @Before
    fun setUp() {
        server = MockWebServer().apply { start() }
        base = server.url("/").toString()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    /** Read once, so a test can shut the server down and still aim at it. */
    private lateinit var base: String
    private val endpoints get() = StationCamEndpoints(base)

    private fun history() =
        StationCamHistoryCache(historyDirectory, endpoints, http, TextDecoder, { now }, Dispatchers.Unconfined)

    private fun frames() = StationCamFrameCache(camDirectory, endpoints, http, TextDecoder, {
        now
    }, Dispatchers.Unconfined)

    private fun image(text: String) = MockResponse().setBody(Buffer().write(text.encodeToByteArray()))

    // History: 404 is missing, never an error

    @Test
    fun aMissingHourIsMissingNotFailed() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(404))

        assertEquals(CamHourResult.Missing, history().load(hour))
        assertEquals("/stations/001/2026-10-30/21.jpg", server.takeRequest().path)
        assertFalse(history().file(hour).exists())
    }

    @Test
    fun serverTroubleIsFailed() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(503))
        assertEquals(CamHourResult.Failed, history().load(hour))

        server.enqueue(MockResponse().setResponseCode(403))
        assertEquals(CamHourResult.Failed, history().load(hour))

        // A 200 that isn't an image (an HTML error page) isn't saved.
        server.enqueue(image("<html>"))
        assertEquals(CamHourResult.Failed, history().load(hour))
        assertFalse(history().file(hour).exists())
    }

    @Test
    fun offlineIsFailed() = runBlocking {
        server.shutdown()
        assertEquals(CamHourResult.Failed, history().load(hour))
    }

    @Test
    fun aFetchedHourIsSavedAndNeverFetchedAgain() = runBlocking {
        server.enqueue(image("JPEG 21:00"))

        assertEquals(CamHourResult.Thumbnail("thumb(640):JPEG 21:00"), history().load(hour))
        assertEquals(File(historyDirectory, "001-2026-10-30-21.jpg"), history().file(hour))
        assertTrue(history().file(hour).isFile)

        // From disk: no second request.
        assertEquals(CamHourResult.Thumbnail("thumb(640):JPEG 21:00"), history().load(hour))
        assertEquals("JPEG 21:00", history().savedFullImage(hour))
        assertEquals(1, server.requestCount)
    }

    @Test
    fun aSavedHourOverAWeekOldIsNotUsed() = runBlocking {
        server.enqueue(image("JPEG 21:00"))
        history().load(hour)

        now = now.plus(OfflineCacheRetention.maxAge).plus(Duration.ofMinutes(1))
        assertNull(history().savedThumbnail(hour))
        assertNull(history().savedFullImage(hour))
    }

    // The latest frame

    @Test
    fun theLatestFrameIsVersionedSavedAndReadBackWithItsTime() = runBlocking {
        server.enqueue(image("JPEG live"))

        assertEquals(CamFrame("JPEG live", cam.time), frames().fetch(cam))
        val request = server.takeRequest()
        assertEquals("/stations/001.jpg", request.requestUrl?.encodedPath)
        assertEquals(cam.time, request.requestUrl?.queryParameter("t"))

        assertEquals(CamFrame("JPEG live", cam.time), frames().savedFrame("001"))
        assertNull(frames().savedFrame("057"))
    }

    @Test
    fun aFailedRefreshLeavesTheSavedFrame() = runBlocking {
        server.enqueue(image("JPEG old"))
        frames().fetch(cam)

        server.enqueue(MockResponse().setResponseCode(500))
        assertNull(frames().fetch(cam.copy(time = "2026-10-30T23:30:00+08:00")))
        server.enqueue(image("not an image"))
        assertNull(frames().fetch(cam.copy(time = "2026-10-30T23:30:00+08:00")))

        assertEquals(CamFrame("JPEG old", cam.time), frames().savedFrame("001"))
    }

    @Test
    fun aSavedFrameOverAWeekOldIsNotUsed() = runBlocking {
        server.enqueue(image("JPEG live"))
        frames().fetch(cam)

        now = now.plus(Duration.ofDays(8))
        assertNull(frames().savedFrame("001"))
    }

    // The manifest

    private fun store(cacheStore: CacheStore = CacheStore(root) { now }) =
        StationCamStore(endpoints, cacheStore, http, { now }, Dispatchers.Unconfined)

    @Test
    fun theManifestIsFetchedOnceAnHourAndKeptWhenARefreshFails() = runBlocking {
        server.enqueue(MockResponse().setBody(Fixtures.stationCamsManifest))
        val store = store()

        assertEquals(listOf("001", "057", "088", "204"), store.cams().map { it.siteId })
        assertEquals("/manifest.json", server.takeRequest().path)
        store.cams()
        assertEquals(1, server.requestCount)

        now = now.plus(StationCamStore.TTL)
        server.enqueue(MockResponse().setResponseCode(500))
        assertEquals(4, store.cams().size)
        assertEquals(2, server.requestCount)
    }

    @Test
    fun aNewStoreReadsTheSavedManifestOffline() = runBlocking {
        server.enqueue(MockResponse().setBody(Fixtures.stationCamsManifest))
        store().cams()
        server.shutdown()

        now = now.plus(Duration.ofHours(3))
        assertEquals(4, store().cams().size)

        now = now.plus(Duration.ofDays(8))
        assertEquals(emptyList<StationCam>(), store().cams())
    }

    // The week-old purge

    @Test
    fun framesAndHistoryAreUnderTheOfflineCacheRootAndPurgedAfterAWeek() = runBlocking {
        server.enqueue(image("JPEG live"))
        server.enqueue(image("JPEG 21:00"))
        server.enqueue(MockResponse().setBody(Fixtures.stationCamsManifest))
        frames().fetch(cam)
        history().load(hour)
        store().cams()

        val saved = listOf(
            File(camDirectory, "001.jpg"),
            File(camDirectory, "001.json"),
            File(historyDirectory, "001-2026-10-30-21.jpg"),
            File(root, StationCamStore.FILE_NAME)
        )
        saved.forEach { assertTrue("$it saved", it.isFile) }
        assertTrue(saved.all { it.canonicalPath.startsWith(root.canonicalPath + File.separator) })

        // Six days on, nothing goes.
        assertEquals(emptyList<File>(), OfflineCacheRetention.purge(root, now.plus(Duration.ofDays(6))))

        val removed = OfflineCacheRetention.purge(root, now.plus(Duration.ofDays(8)))
        assertEquals(saved.map { it.canonicalPath }.toSet(), removed.map { it.canonicalPath }.toSet())
        saved.forEach { assertFalse("$it purged", it.exists()) }
    }
}
