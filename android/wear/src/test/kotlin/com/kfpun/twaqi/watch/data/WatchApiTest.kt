package com.kfpun.twaqi.watch.data

import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The watch's API client (iOS `WatchAPI`) against a local server with a recorded response shape. */
class WatchApiTest {
    private val server = MockWebServer().apply { start() }
    private val api = WatchApi(server.url("/").toString())

    @After
    fun tearDown() = server.shutdown()

    private val current = """
        {"success": true, "data": [
          {"station_id": 126, "code": "Songshan", "lat": 25.05, "lon": 121.578,
           "aqi": 42, "pm25": 9, "pm10": 21, "o3": 31.2, "co": 0.32, "so2": 1.4, "no2": 12.5,
           "wind_direction": 247, "wind_speed": 2.6, "publish_time": "2026-11-06 10:00:00",
           "name": {"en": "Songshan", "zh": "松山"},
           "additional_info": {"county": {"en": "Taipei City", "zh": "臺北市"}, "township": {"zh": "松山區"}}},
          {"station_id": 3, "code": "Banqiao", "lat": 25.013, "lon": 121.458,
           "aqi": 104, "pm25": 37, "pm10": 61, "o3": 52.3, "co": 0.48, "so2": 2.6, "no2": 18.8,
           "wind_direction": 210, "wind_speed": 1.8, "publish_time": "2026-11-06 10:00:00",
           "name": {"en": "Banqiao", "zh": "板橋"}},
          {"station_id": 9, "code": "Broken", "lat": 22.0, "lon": 120.0, "aqi": null,
           "pm25": 1, "pm10": 1, "o3": 1, "co": 1, "so2": 1, "no2": 1,
           "wind_direction": 0, "wind_speed": 0, "publish_time": "2026-11-06 10:00:00"}
        ]}
    """.trimIndent()

    @Test
    fun readsCurrentReadingsAndDropsIncompleteOnes() = runTest {
        server.enqueue(MockResponse().setBody(current))
        val readings = api.currentPollutants()

        assertEquals(listOf(126, 3), readings.map { it.stationId })
        val songshan = readings.first()
        assertEquals("松山", songshan.displayName(chinese = true))
        assertEquals("Songshan", songshan.displayName(chinese = false))
        assertEquals("臺北市", songshan.locality(chinese = true))
        assertEquals("松山區", songshan.township)
        assertEquals("/v1/current-pollutants?country=twn", server.takeRequest().path)
    }

    @Test
    fun asksForSeveralStationsInOneRequest() = runTest {
        server.enqueue(MockResponse().setBody(current))
        api.currentPollutants(listOf(126, 3))
        assertEquals("/v1/current-pollutants?station_id=126%2C3", server.takeRequest().path)
        assertEquals(emptyList<WatchReading>(), api.currentPollutants(emptyList()))
    }

    @Test
    fun readsHistoryLeniently() = runTest {
        server.enqueue(
            MockResponse().setBody(
                """{"success": true, "data": [{"aqi": 40, "pm25": null, "publish_time": "2026-11-06 09:00:00"}, {"aqi": 42}]}"""
            )
        )
        val history = api.history(126, limit = 12)
        assertEquals(listOf(40.0, 42.0), history.map { it.aqi })
        assertEquals(0.0, history.first().pm25, 0.0)
        assertEquals("/v1/historical-pollutants?station_id=126&limit=12", server.takeRequest().path)
    }

    @Test
    fun aFailedOrUnsuccessfulResponseThrows() = runTest {
        server.enqueue(MockResponse().setResponseCode(500))
        assertTrue(runCatching { api.currentPollutant(126) }.exceptionOrNull() is WatchApiException)
        server.enqueue(MockResponse().setBody("""{"success": false}"""))
        assertTrue(runCatching { api.currentPollutant(126) }.exceptionOrNull() is WatchApiException)
    }

    /** Home without a location is the station nearest 中正 (iOS `defaultLocation`). */
    @Test
    fun closestPicksTheNearestStation() = runTest {
        server.enqueue(MockResponse().setBody(current))
        val stations = api.currentPollutants()
        assertEquals(3, WatchApi.closest(25.0, 121.45, stations)?.stationId)
        assertEquals(126, WatchApi.closest(25.05, 121.58, stations)?.stationId)
        assertNull(WatchApi.closest(25.0, 121.5, emptyList()))
    }

    @Test
    fun readingsRoundTripThroughJson() {
        val reading = WatchApiParser.readings(current).first()
        assertEquals(reading, WatchReading.fromJson(reading.toJson()))
        assertEquals(listOf(reading), WatchReading.listFromJson(WatchReading.listToJson(listOf(reading))))
    }

    @Test
    fun publishTimesShowInTaiwanTime() {
        assertEquals("10:00", WatchReading.hourMinute("2026-11-06T10:00:00"))
        assertEquals("", WatchReading.hourMinute(""))
    }

    @Test
    fun windNamesItsCompassPoint() {
        assertEquals("WNW", Wind(297.0, 2.0).compassPoint)
        assertEquals("N", Wind(-10.0, 2.0).compassPoint)
        assertEquals("—", Wind(90.0, 0.0).compassPoint)
    }
}
