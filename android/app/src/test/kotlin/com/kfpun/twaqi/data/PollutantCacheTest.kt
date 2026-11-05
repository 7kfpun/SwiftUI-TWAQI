package com.kfpun.twaqi.data

import com.kfpun.twaqi.data.cache.CacheStore
import com.kfpun.twaqi.data.cache.OfflineCacheRetention
import com.kfpun.twaqi.data.cache.PollutantCache
import java.io.File
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Ported from iOS `PollutantCacheTests`. */
class PollutantCacheTest {
    @get:Rule val temp = TemporaryFolder()

    private var now = Instant.parse("2026-11-06T04:00:00Z")

    private fun makeCache() = PollutantCache(CacheStore(temp.root) { now }) { now }

    /** The shape `current-pollutants` returns, trimmed to what the parser needs. */
    private fun response(vararg stations: Pair<Int, Int>): String = stations.joinToString(
        prefix = """{ "success": true, "data": [""",
        postfix = "] }"
    ) { (id, aqi) ->
        """
        {
          "station_id": $id, "code": "S$id", "lat": 25.1, "lon": 121.7,
          "aqi": $aqi, "pm25": 10, "pm10": 20, "no2": 1, "so2": 1, "co": 0.1, "o3": 30,
          "wind_direction": 90, "wind_speed": 2, "publish_time": "2026-10-31T10:00:00",
          "name": { "en": "Keelung", "zh": "基隆" },
          "address": {}, "area": { "en": "North", "zh": "北部" }, "additional_info": {}
        }
        """.trimIndent()
    }

    @Test
    fun countryResponseReadsBack() {
        val cache = makeCache()
        cache.save("twn", response(91 to 42, 12 to 80))
        assertEquals(listOf(91, 12), cache.pollutants("twn")?.value?.map { it.stationId })
        assertEquals(now, cache.pollutants("twn")?.savedAt)
        assertNull(cache.pollutants("tha"))
    }

    /** A station the map has shown can be opened offline. */
    @Test
    fun countryResponseAlsoFillsStations() {
        val cache = makeCache()
        cache.save("twn", response(91 to 42, 12 to 80))
        assertEquals(80.0, cache.pollutant(12)!!.value.aqi, 0.0)
    }

    @Test
    fun stationsComeBackInTheOrderAsked() {
        val cache = makeCache()
        cache.saveStations(response(1 to 10, 2 to 20, 3 to 30))
        assertEquals(listOf(3, 1), cache.pollutants(listOf(3, 99, 1)).map { it.value.stationId })
    }

    @Test
    fun newerReadingReplacesOlderAndOthersAreKept() {
        val cache = makeCache()
        cache.saveStations(response(1 to 10, 2 to 20))
        cache.saveStations(response(1 to 15))
        assertEquals(listOf(15.0, 20.0), cache.pollutants(listOf(1, 2)).map { it.value.aqi })
    }

    @Test
    fun survivesARelaunch() {
        makeCache().saveStations(response(91 to 42))
        assertEquals(42.0, makeCache().pollutant(91)!!.value.aqi, 0.0)
    }

    @Test
    fun stationsOlderThanAWeekAreNotReturned() {
        val cache = makeCache()
        cache.saveStations(response(91 to 42))
        assertNotNull(cache.pollutant(91))

        now = now.plus(OfflineCacheRetention.maxAge).plusSeconds(60)
        assertNull(cache.pollutant(91))
        assertNull(makeCache().pollutant(91))
    }

    @Test
    fun countryFileOlderThanAWeekIsNotReturned() {
        val cache = makeCache()
        cache.save("twn", response(91 to 42))
        File(temp.root, PollutantCache.countryFileName("twn"))
            .setLastModified(now.minus(OfflineCacheRetention.maxAge).minusSeconds(60).toEpochMilli())
        assertNull(cache.pollutants("twn"))
    }

    @Test
    fun undecodableResponseIsIgnored() {
        val cache = makeCache()
        cache.save("twn", response(91 to 42))
        cache.save("twn", "<html>gateway timeout</html>")
        cache.saveStations("<html>gateway timeout</html>")
        assertEquals(42.0, cache.pollutant(91)!!.value.aqi, 0.0)
        assertEquals(listOf(91), cache.pollutants("twn")?.value?.map { it.stationId })
    }

    @Test
    fun recordedResponseRoundTrips() {
        makeCache().save("twn", Fixtures.currentPollutants)
        val again = makeCache()
        assertEquals(listOf(91, 876, 115), again.pollutants("twn")?.value?.map { it.stationId })
        assertEquals("信義區", again.pollutant(91)!!.value.township)
    }
}
