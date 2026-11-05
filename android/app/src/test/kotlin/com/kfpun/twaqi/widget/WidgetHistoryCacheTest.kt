package com.kfpun.twaqi.widget

import com.kfpun.twaqi.data.Fixtures
import com.kfpun.twaqi.data.cache.CacheStore
import com.kfpun.twaqi.data.remote.ApiParser
import java.nio.file.Files
import java.time.Duration
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** FOX-59 (iOS `WidgetExtraLargeTests`): the station detail widget keeps its last good 24 hours for a week. */
class WidgetHistoryCacheTest {
    private val root = Files.createTempDirectory("widget-history").toFile()
    private var now = Instant.ofEpochSecond(1_793_000_000)
    private val cache = WidgetHistoryCache(CacheStore(root) { now })
    private val history = ApiParser.history(Fixtures.historicalPollutants).readings

    @Test
    fun roundTrips() {
        cache.save(12, history)
        assertEquals(history, cache.read(12))
        assertNull(cache.read(13))
    }

    @Test
    fun anEmptyFetchKeepsTheSavedCopy() {
        cache.save(12, history)
        cache.save(12, emptyList())
        assertEquals(history, cache.read(12))
    }

    @Test
    fun aWeekOldCopyIsIgnoredAndLivesUnderTheCacheRoot() {
        cache.save(12, history)
        assertEquals(root, CacheStore(root).file(WidgetHistoryCache.fileName(12)).parentFile)
        now = now.plus(Duration.ofDays(8))
        assertNull(cache.read(12))
    }
}
