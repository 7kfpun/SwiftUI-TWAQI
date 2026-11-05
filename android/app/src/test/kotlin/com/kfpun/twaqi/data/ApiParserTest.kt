package com.kfpun.twaqi.data

import com.kfpun.twaqi.data.model.Country
import com.kfpun.twaqi.data.model.StationType
import com.kfpun.twaqi.data.remote.ApiFormatException
import com.kfpun.twaqi.data.remote.ApiParser
import java.time.Instant
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Parsing against recorded responses (and iOS `StationParsingTests`' cases). */
class ApiParserTest {

    @Test
    fun countries() {
        val countries = ApiParser.countries(Fixtures.countries)
        assertEquals(7, countries.size)
        val taiwan = countries.single { it.code == "twn" }
        assertEquals(Country.SUPPORTED_ID, taiwan.id)
        assertTrue(taiwan.isSupported)
        assertEquals("Taiwan", taiwan.name)
        assertEquals("台灣", taiwan.nameLocal)
        assertEquals(7.9f, taiwan.zoom, 0.001f)
        assertEquals(listOf("twn"), countries.filter { it.isSupported }.map { it.code })

        // A placeholder row: no names, null island. Falls back to the code and is no place to search from.
        val korea = countries.single { it.code == "kor" }
        assertEquals("KOR", korea.name)
        assertEquals("KOR", korea.displayName(chinese = true))
        assertFalse(korea.hasValidLocation)
        assertTrue(taiwan.hasValidLocation)
    }

    @Test
    fun countryDisplayNameFallsBackThroughTheOtherLanguage() {
        val onlyEnglish = Country(9, "xyz", 1.0, 1.0, 5f, name = "Somewhere", nameLocal = "")
        assertEquals("Somewhere", onlyEnglish.displayName(chinese = true))
        assertEquals("台灣", ApiParser.countries(Fixtures.countries).single { it.id == 3 }.displayName(chinese = true))
    }

    @Test
    fun completeStation() {
        val keelung = ApiParser.stations(Fixtures.stations).single { it.id == 91 }
        assertEquals(3, keelung.countryId)
        assertEquals("基隆", keelung.code)
        assertEquals("Keelung", keelung.name)
        assertEquals("基隆", keelung.nameLocal)
        assertEquals(25.129167, keelung.lat, 1e-6)
        assertEquals(121.760056, keelung.lon, 1e-6)
        assertEquals("基隆市東信路324號", keelung.address)
        assertEquals("North", keelung.area)
        assertEquals("北部空品區", keelung.areaLocal)
        assertEquals("Keelung City", keelung.county)
        assertEquals("基隆市", keelung.countyLocal)
        assertEquals("信義區", keelung.township)
        assertEquals(StationType.GENERAL, keelung.stationType)
        assertEquals("https://example.com/webcam?site=1&type=l", keelung.imageUrl)
        assertEquals("Keelung", keelung.displayName(chinese = false))
        assertEquals("基隆", keelung.displayName(chinese = true))
        assertEquals("信義區, Keelung City", keelung.displayLocality(chinese = false))
        assertEquals("信義區, 基隆市", keelung.displayLocality(chinese = true))
        assertEquals("Xinyi, Keelung City", keelung.displayLocality(chinese = false) { "Xinyi" })
        assertEquals("北部空品區", keelung.displayArea(chinese = true))
    }

    /** Micro-sensor stations send `{}` for every nested object and `""` for the type and image. */
    @Test
    fun sparseStationDegradesToNull() {
        val sparse = ApiParser.stations(Fixtures.stations).single { it.id == 898 }
        assertNull(sparse.address)
        assertNull(sparse.area)
        assertNull(sparse.areaLocal)
        assertNull(sparse.county)
        assertNull(sparse.countyLocal)
        assertNull(sparse.township)
        assertNull(sparse.imageUrl)
        assertNull(sparse.displayLocality(chinese = false))
        assertNull(sparse.displayArea(chinese = false))
        assertEquals(StationType.UNKNOWN, sparse.stationType)
        assertFalse(sparse.stationType.isDisplayable)
    }

    @Test
    fun missingEnglishNameFallsBackToLocal() {
        val station = ApiParser.station(obj("""{"id": 17281, "code": "臺灣大道", "name": {"zh": "臺灣大道"}}"""))
        assertEquals("臺灣大道", station.name)
        assertEquals("臺灣大道", station.nameLocal)
    }

    @Test
    fun acceptsCamelCaseCountryKeysAndDefaultsMissingOnes() {
        val camel = ApiParser.station(
            obj("""{"id": 63, "countryId": 3, "countryCode": "twn", "name": {"en": "Taixi"}}""")
        )
        assertEquals(3, camel.countryId)
        assertEquals("twn", camel.countryCode)

        val bare = ApiParser.station(obj("""{"id": 1}"""))
        assertEquals(0, bare.countryId)
        assertEquals("", bare.countryCode)
        assertEquals(0.0, bare.lat, 0.0)
        assertEquals("#1", bare.displayName(chinese = false))
    }

    @Test
    fun currentPollutants() {
        val readings = ApiParser.pollutants(Fixtures.currentPollutants)
        assertEquals(listOf(91, 876, 115), readings.map { it.stationId })

        val keelung = readings.first()
        assertEquals(54.0, keelung.aqi, 0.0)
        assertEquals(7.0, keelung.pm25, 0.0)
        assertEquals(0.33, keelung.co, 0.0)
        assertEquals(85.0, keelung.windDirection, 0.0)
        assertEquals("2026-11-06T00:00:00", keelung.publishTime)
        // Taiwan midnight is 16:00 UTC the day before, whatever the device zone.
        assertEquals(Instant.parse("2026-11-05T16:00:00Z"), keelung.publishedAt)
        assertEquals("北部空品區", keelung.areaLocal)
        assertEquals("25.129167, 121.760056", keelung.coordinateText)

        val sparse = readings.single { it.stationId == 876 }
        assertNull(sparse.area)
        assertNull(sparse.imageUrl)
        assertEquals(StationType.UNKNOWN, sparse.stationType)
        assertEquals("Dacheng", sparse.displayName(chinese = false))
    }

    /** iOS's decoder fails a reading without its numbers; the rest of the response still shows. */
    @Test
    fun readingMissingANumberIsDropped() {
        val body = """
            {"success": true, "data": [
              {"station_id": 1, "lat": 1, "lon": 1, "aqi": 10, "pm25": 1, "pm10": 1, "no2": 1, "so2": 1, "co": 0.1,
               "o3": 1, "wind_direction": 1, "wind_speed": 1, "publish_time": "2026-11-06T00:00:00", "name": {}},
              {"station_id": 2, "lat": 1, "lon": 1, "aqi": null, "publish_time": "2026-11-06T00:00:00"}
            ]}
        """.trimIndent()
        assertEquals(listOf(1), ApiParser.pollutants(body).map { it.stationId })
        assertEquals("#1", ApiParser.pollutants(body).single().displayName(chinese = true))
    }

    @Test
    fun history() {
        val history = ApiParser.history(Fixtures.historicalPollutants)
        assertEquals(91, history.station.id)
        assertEquals("北部空品區", history.station.areaLocal)
        assertEquals(12, history.readings.size)
        assertEquals("2026-11-05T01:00:00", history.readings.first().publishTime)
        assertEquals("2026-11-05T12:00:00", history.readings.last().publishTime)
        assertEquals(62.0, history.readings.first().aqi, 0.0)
        // Oldest first: the trend reads straight off it.
        val publishTimes = history.readings.map { it.publishedAt!! }
        assertEquals(publishTimes.sorted(), publishTimes)
    }

    @Test
    fun forecasts() {
        val rows = ApiParser.forecasts(Fixtures.forecast)
        assertEquals(9, rows.size)
        val north = rows.first()
        assertEquals("北部", north.area)
        assertEquals("2026-11-06", north.forecastDate)
        assertEquals(60, north.aqi)
        assertEquals("細懸浮微粒", north.majorPollutant)
        assertNull(north.minorPollutantAqi)
        assertEquals(Instant.parse("2026-11-05T14:00:00Z"), north.publishedAt)
        assertTrue(north.translatedContent("en")!!.startsWith("Today"))
        assertEquals("PM2.5", north.displayMajorPollutant(chinese = false))
    }

    @Test
    fun failureResponsesThrow() {
        listOf(
            "<html>gateway timeout</html>",
            """{"success": false, "data": []}""",
            """{"success": true}""",
            "[]"
        ).forEach { body ->
            try {
                ApiParser.pollutants(body)
                throw AssertionError("parsed $body")
            } catch (e: ApiFormatException) {
                // expected
            }
        }
    }

    private fun obj(json: String): JsonObject = ApiParser.element(json).jsonObject
}
