package com.kfpun.twaqi.data

import com.kfpun.twaqi.data.cache.CacheStore
import com.kfpun.twaqi.data.cache.OfflineCacheRetention
import com.kfpun.twaqi.data.cache.PollutantCache
import java.io.File
import java.time.Duration
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Ported from iOS `OfflineCacheRetentionTests`: one root, everything under it older than a week goes. */
class OfflineCacheRetentionTest {
    @get:Rule val temp = TemporaryFolder()

    private val now = Instant.parse("2026-11-06T04:00:00Z")
    private val week = OfflineCacheRetention.maxAge
    private val day = Duration.ofDays(1)

    private val root: File by lazy { File(temp.root, OfflineCacheRetention.ROOT_DIRECTORY) }

    private fun file(path: String, age: Duration): File = File(root, path).apply {
        parentFile!!.mkdirs()
        writeText("{}")
        setLastModified(now.minus(age).toEpochMilli())
    }

    private fun exists(path: String) = File(root, path).exists()

    @Test
    fun purgesEveryCacheOlderThanAWeekAtAnyDepth() {
        val old = listOf(
            CacheStore.stations("twn"),
            PollutantCache.countryFileName("twn"),
            PollutantCache.STATIONS_FILE_NAME,
            CacheStore.FORECAST,
            CacheStore.COUNTRIES,
            "station-cams/001.jpg",
            "station-cams/history/001-2026-10-20-22.jpg"
        )
        old.forEach { file(it, week + day) }

        val removed = OfflineCacheRetention.purge(root, now)

        assertEquals(old.size, removed.size)
        old.forEach { assertFalse(it, exists(it)) }
    }

    @Test
    fun keepsCachesYoungerThanAWeek() {
        file(CacheStore.stations("twn"), week - day)
        file(CacheStore.FORECAST, Duration.ofMinutes(1))
        file("station-cams/history/057-2026-10-30-22.jpg", day)

        assertTrue(OfflineCacheRetention.purge(root, now).isEmpty())
        assertTrue(exists(CacheStore.stations("twn")))
        assertTrue(exists(CacheStore.FORECAST))
        assertTrue(exists("station-cams/history/057-2026-10-30-22.jpg"))
    }

    /** Only the cache root is scanned: settings and SDK files beside it stay. */
    @Test
    fun leavesFilesOutsideTheRootAlone() {
        val settings = File(temp.root, "settings.json").apply {
            writeText("{}")
            setLastModified(now.minus(week.multipliedBy(10)).toEpochMilli())
        }
        file(CacheStore.FORECAST, week + day)

        OfflineCacheRetention.purge(root, now)

        assertTrue(settings.exists())
        assertFalse(exists(CacheStore.FORECAST))
    }

    @Test
    fun missingRootIsFine() {
        assertTrue(OfflineCacheRetention.purge(File(temp.root, "nope"), now).isEmpty())
    }

    @Test
    fun missingDateIsExpired() {
        assertTrue(OfflineCacheRetention.isExpired(null, now))
        assertFalse(OfflineCacheRetention.isExpired(now, now))
        assertFalse(OfflineCacheRetention.isExpired(now.minus(week), now))
        assertTrue(OfflineCacheRetention.isExpired(now.minus(week).minusSeconds(1), now))
    }

    /** Reads skip a week-old file even before the purge has run. */
    @Test
    fun storeIgnoresAnExpiredFile() {
        val store = CacheStore(root) { now }
        store.write(CacheStore.FORECAST, """{"data": []}""")
        assertEquals("""{"data": []}""", store.read(CacheStore.FORECAST)?.value)

        File(root, CacheStore.FORECAST).setLastModified(now.minus(week + day).toEpochMilli())
        assertNull(store.read(CacheStore.FORECAST))
    }

    /** Every file the stores write is under the root, so the purge reaches all of them. */
    @Test
    fun storesWriteOnlyUnderTheRoot() {
        val store = CacheStore(root) { now }
        PollutantCache(store) { now }.save("twn", Fixtures.currentPollutants)
        store.write(CacheStore.stations("twn"), Fixtures.stations)
        store.write(CacheStore.FORECAST, Fixtures.forecast)
        store.write(CacheStore.COUNTRIES, Fixtures.countries)

        assertEquals(listOf(OfflineCacheRetention.ROOT_DIRECTORY), temp.root.list()!!.toList())
        val names = root.list()!!.toSet()
        assertEquals(
            setOf(
                "pollutants-twn.json",
                "pollutants-stations.json",
                "stations-twn.json",
                "aqi-forecast.json",
                "countries.json"
            ),
            names
        )
        assertEquals(names.size, OfflineCacheRetention.purge(root, now.plus(week + day)).size)
    }
}
