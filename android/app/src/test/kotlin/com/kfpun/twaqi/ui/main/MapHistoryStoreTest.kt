package com.kfpun.twaqi.ui.main

import com.kfpun.twaqi.data.model.HistoricalPollutant
import com.kfpun.twaqi.data.model.Station
import com.kfpun.twaqi.data.model.StationHistory
import com.kfpun.twaqi.data.repository.DataResult
import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class MapHistoryStoreTest {
    private val anchor = "2026-11-06T02:00:00"

    /** A fake history endpoint: each call waits until the test answers it. */
    private class Endpoint {
        val calls = mutableListOf<Pair<Int, Int>>()
        val answers = mutableMapOf<Int, CompletableDeferred<DataResult<StationHistory>>>()

        suspend fun fetch(stationId: Int, limit: Int): DataResult<StationHistory> {
            calls += stationId to limit
            return answers.getOrPut(stationId) { CompletableDeferred() }.await()
        }

        fun answer(stationId: Int, result: DataResult<StationHistory>) {
            answers.getOrPut(stationId) { CompletableDeferred() }.complete(result)
        }
    }

    private fun TestScope.store(endpoint: Endpoint) = MapHistoryStore(backgroundScope, endpoint::fetch)

    private fun history(stationId: Int, vararg times: String) = DataResult.Fresh(
        StationHistory(
            Station(stationId, 3, "twn", "s$stationId", 25.0, 121.5, null, "S$stationId", "站$stationId"),
            times.mapIndexed { i, time ->
                HistoricalPollutant(40.0 + i, 10.0, 20.0, 1.0, 1.0, 0.2, 30.0, 90.0, 2.0, time)
            }
        ),
        Instant.EPOCH
    )

    @Test
    fun readingsAreKeptByTheirTaiwanHour() = runTest {
        val endpoint = Endpoint()
        val store = store(endpoint)
        store.request(listOf(HistoryRequest(1, anchor)))
        runCurrent()
        // 24 hours back plus the latest: 25 readings.
        assertEquals(listOf(1 to 25), endpoint.calls)

        endpoint.answer(1, history(1, "2026-11-05T23:00:00", "2026-11-06 00:00:00", "2026-11-06T01:00:00"))
        runCurrent()
        assertEquals(40.0, store.reading(1, "2026-11-05T23:00:00")?.aqi)
        assertEquals(41.0, store.reading(1, "2026-11-06T00:00:00")?.aqi)
        assertNull(store.reading(1, "2026-11-05T22:00:00"))
        assertNull(store.reading(2, "2026-11-06T00:00:00"))
    }

    @Test
    fun atMostSixAtOnceInTheRequestedOrder() = runTest {
        val endpoint = Endpoint()
        val store = store(endpoint)
        store.request((1..10).map { HistoryRequest(it, anchor) })
        runCurrent()
        assertEquals((1..6).toList(), endpoint.calls.map { it.first })
        assertEquals(HistoryProgress(0, 10), store.progress)
        assertTrue(store.progress.isLoading)

        endpoint.answer(2, history(2, anchor))
        runCurrent()
        assertEquals((1..7).toList(), endpoint.calls.map { it.first })
        assertEquals(HistoryProgress(1, 10), store.progress)

        (1..10).forEach { endpoint.answer(it, history(it, anchor)) }
        runCurrent()
        assertEquals(HistoryProgress(10, 10), store.progress)
        assertEquals(10, endpoint.calls.size)
    }

    @Test
    fun newRequestsGoAheadOfTheQueue() = runTest {
        val endpoint = Endpoint()
        val store = store(endpoint)
        store.request((1..8).map { HistoryRequest(it, anchor) })
        runCurrent()
        // Panned: station 20 is now nearest the centre.
        store.request(listOf(HistoryRequest(20, anchor), HistoryRequest(8, anchor)))
        endpoint.answer(1, history(1, anchor))
        runCurrent()
        assertEquals(listOf(1, 2, 3, 4, 5, 6, 20), endpoint.calls.map { it.first })
        assertEquals(HistoryProgress(0, 2), store.progress)
    }

    @Test
    fun eachStationOncePerPublishHourEvenWhenItFails() = runTest {
        val endpoint = Endpoint()
        val store = store(endpoint)
        store.request(listOf(HistoryRequest(1, anchor), HistoryRequest(2, anchor)))
        endpoint.answer(1, history(1, anchor))
        endpoint.answer(2, DataResult.Failed(IOException("offline")))
        runCurrent()
        assertEquals(HistoryProgress(2, 2), store.progress)

        store.request(listOf(HistoryRequest(1, anchor), HistoryRequest(2, anchor)))
        runCurrent()
        assertEquals(2, endpoint.calls.size)

        // A new publish hour moves the window: fetched again.
        endpoint.answers.clear()
        store.request(listOf(HistoryRequest(1, "2026-11-06T03:00:00")))
        runCurrent()
        assertEquals(listOf(1, 2, 1), endpoint.calls.map { it.first })
        assertEquals(HistoryProgress(0, 1), store.progress)
    }

    @Test
    fun visibleStationsNearestTheCentreFirstAgainstTheirCountrysAnchor() {
        val taiwan = listOf(
            pollutant(1, lat = 25.0, lon = 121.5).copy(publishTime = "2026-11-06T14:00:00"),
            pollutant(2, lat = 23.0, lon = 120.2).copy(publishTime = "2026-11-06T13:00:00"),
            pollutant(3, lat = 24.1, lon = 120.7).copy(publishTime = "2026-11-06T14:00:00"),
            // Off screen.
            pollutant(4, lat = 26.5, lon = 119.9).copy(publishTime = "2026-11-06T14:00:00")
        )
        val japan = listOf(pollutant(9, lat = 24.4, lon = 122.9).copy(publishTime = "2026-11-06T15:00:00"))
        val area = MapArea(south = 21.5, west = 119.0, north = 26.0, east = 123.5, center = GeoPoint(24.0, 120.8))
        val requests = MapHistoryStore.visibleRequests(mapOf("twn" to taiwan, "jpn" to japan), area)
        assertEquals(
            listOf(
                HistoryRequest(3, "2026-11-06T14:00:00"),
                HistoryRequest(2, "2026-11-06T14:00:00"),
                HistoryRequest(1, "2026-11-06T14:00:00"),
                HistoryRequest(9, "2026-11-06T15:00:00")
            ),
            requests
        )
    }

    @Test
    fun areaAcrossTheAntimeridian() {
        val area = MapArea(south = -10.0, west = 170.0, north = 10.0, east = -170.0, center = GeoPoint(0.0, 180.0))
        assertTrue(area.contains(0.0, 175.0))
        assertTrue(area.contains(0.0, -175.0))
        assertTrue(!area.contains(0.0, 0.0))
    }
}
