package com.kfpun.twaqi.data

import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.AqiForecastMatcher
import com.kfpun.twaqi.data.model.AqiForecastPollutant
import com.kfpun.twaqi.data.model.AreaForecast
import com.kfpun.twaqi.data.model.TaiwanTime
import com.kfpun.twaqi.data.remote.ApiClient
import com.kfpun.twaqi.data.remote.ApiConfig
import com.kfpun.twaqi.data.remote.ApiParser
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Ported from iOS `AqiForecastTests`. */
class AqiForecastTest {
    private val response = """
    {
      "data": [
        { "area": "北部", "forecast_date": "2026-10-31", "aqi": 62, "major_pollutant": "臭氧8小時", "minor_pollutant": "細懸浮微粒", "minor_pollutant_aqi": 55, "content": "今日北部普通。", "publish_time": "2026-10-31 10:30:00" },
        { "area": "北部", "forecast_date": "2026-11-01", "aqi": 88, "major_pollutant": "細懸浮微粒", "minor_pollutant": null, "minor_pollutant_aqi": null, "content": "明日北部普通。", "publish_time": "2026-10-31 16:30:00" },
        { "area": "北部", "forecast_date": "2026-11-02", "aqi": 45, "major_pollutant": null, "minor_pollutant": null, "minor_pollutant_aqi": null, "content": "明日北部普通。", "publish_time": "2026-10-31 16:30:00" },
        { "area": "北部", "forecast_date": "2026-11-03", "aqi": 40, "major_pollutant": null, "minor_pollutant": null, "minor_pollutant_aqi": null, "content": null, "publish_time": "2026-10-31 16:30:00" },
        { "area": "北部", "forecast_date": "2026-10-30", "aqi": 99, "major_pollutant": null, "minor_pollutant": null, "minor_pollutant_aqi": null, "content": null, "publish_time": "2026-10-29 16:30:00" },
        { "area": "雲嘉南", "forecast_date": "2026-11-01", "aqi": 120, "major_pollutant": "細懸浮微粒", "minor_pollutant": null, "minor_pollutant_aqi": null, "content": null, "publish_time": "2026-10-31 16:30:00" },
        { "area": "馬祖", "forecast_date": "2026-11-01", "aqi": 30, "major_pollutant": null, "minor_pollutant": null, "minor_pollutant_aqi": null, "content": null, "publish_time": "2026-10-31 16:30:00" }
      ]
    }
    """.trimIndent()

    private fun rows() = ApiParser.forecasts(response)

    @Test
    fun decodesDirectusRows() {
        val rows = rows()
        assertEquals(7, rows.size)
        assertEquals("北部", rows[0].area)
        assertEquals(62, rows[0].aqi)
        assertEquals(55, rows[0].minorPollutantAqi)
        assertNull(rows[2].majorPollutant)
        assertEquals(AirStatus.MODERATE, rows[0].status)
        assertEquals(AirStatus.UNHEALTHY_FOR_SENSITIVE_GROUP, rows[5].status)
    }

    @Test
    fun decodesPretranslatedContent() {
        val json = """
        { "data": [
          { "area": "北部", "forecast_date": "2026-11-03", "aqi": 62, "content": "今日北部普通。", "publish_time": "2026-11-03 16:30:00",
            "content_i18n": { "zh-Hant": "今日北部普通。", "en": "Northern: Moderate today." } },
          { "area": "竹苗", "forecast_date": "2026-11-03", "aqi": 70, "content": "明日竹苗普通。", "publish_time": "2026-11-03 16:30:00",
            "content_i18n": { "zh-Hant": "今日北部普通。", "en": "Northern: Moderate today." } },
          { "area": "中部", "forecast_date": "2026-11-03", "aqi": 80, "content": "今日中部普通。", "publish_time": "2026-11-03 16:30:00",
            "content_i18n": null },
          { "area": "高屏", "forecast_date": "2026-11-03", "aqi": 90, "content": "今日高屏普通。", "publish_time": "2026-11-03 16:30:00",
            "content_i18n": { "en": 3 } },
          { "area": "宜蘭", "forecast_date": "2026-11-03", "aqi": 30, "content": "今日宜蘭良好。", "publish_time": "2026-11-03 16:30:00" }
        ] }
        """.trimIndent()
        val rows = ApiParser.forecasts(json)
        assertEquals(5, rows.size)

        assertEquals("Northern: Moderate today.", rows[0].contentI18n?.get("en"))
        assertEquals("Northern: Moderate today.", rows[0].translatedContent("en"))
        assertNull(rows[0].translatedContent("ja"))
        assertNull(rows[0].translatedContent(null))
        // Made from older text: stale, so the original is used.
        assertNull(rows[1].translatedContent("en"))
        // Null, malformed or missing: the row still parses.
        assertNull(rows[2].contentI18n)
        assertNull(rows[3].contentI18n)
        assertEquals(90, rows[3].aqi)
        assertNull(rows[4].contentI18n)
        assertNull(rows[4].translatedContent("en"))

        val area = AreaForecast("North", listOf(rows[0]))
        assertEquals("今日北部普通。", area.content)
        assertEquals("Northern: Moderate today.", area.translatedContent("en"))
        assertNull(AreaForecast("Central", listOf(rows[2])).translatedContent("en"))
    }

    @Test
    fun matchesStationAreaToForecastArea() {
        val areas = listOf("北部", "竹苗", "中部", "雲嘉南", "高屏", "宜蘭", "花東", "馬祖", "金門", "澎湖")
        assertEquals("北部", AqiForecastMatcher.area("北部空品區", "臺北市", areas))
        assertEquals("雲嘉南", AqiForecastMatcher.area("雲嘉南空品區", null, areas))
        assertEquals("高屏", AqiForecastMatcher.area(" 高屏空品區 ", null, areas))
        // Islands may carry a catch-all area; their county decides.
        assertEquals("馬祖", AqiForecastMatcher.area("其他", "連江縣", areas))
        assertEquals("澎湖", AqiForecastMatcher.area(null, "澎湖縣", areas))
        assertNull(AqiForecastMatcher.area("其他", "臺北市", areas))
        assertNull(AqiForecastMatcher.area(null, null, areas))
    }

    @Test
    fun forecastForStationIsTodayOnwardsSoonestFirst() {
        val forecast = AqiForecastMatcher.forecast("北部空品區", "臺北市", rows(), today = "2026-10-31")!!
        assertEquals("北部空品區", forecast.areaTitle)
        assertEquals(listOf("2026-10-31", "2026-11-01", "2026-11-02"), forecast.days.map { it.forecastDate })
        assertEquals("明日北部普通。", forecast.content)

        val english = AqiForecastMatcher.forecast("北部空品區", null, rows(), title = "North", today = "2026-10-31")!!
        assertEquals("North", english.areaTitle)
    }

    @Test
    fun noForecastWhenNothingCurrent() {
        assertNull(AqiForecastMatcher.forecast("北部空品區", null, rows(), today = "2026-11-10"))
        assertNull(AqiForecastMatcher.forecast("北部空品區", null, emptyList(), today = "2026-10-31"))
        assertNull(AqiForecastMatcher.forecast("中部空品區", null, rows(), today = "2026-10-31"))
    }

    /** The recorded feed matches the recorded Keelung and Matsu stations. */
    @Test
    fun recordedFeedMatchesRecordedStations() {
        val forecasts = ApiParser.forecasts(Fixtures.forecast)
        val stations = ApiParser.stations(Fixtures.stations)
        val keelung = stations.single { it.id == 91 }
        val matsu = stations.single { it.id == 92 }

        val north = AqiForecastMatcher.forecast(
            keelung.areaLocal,
            keelung.countyLocal,
            forecasts,
            today = "2026-11-06"
        )!!
        assertEquals(listOf("2026-11-06", "2026-11-07", "2026-11-08"), north.days.map { it.forecastDate })
        assertEquals(setOf("北部"), north.days.map { it.area }.toSet())
        // Matsu's area is 其他; 連江縣 sends it to 馬祖.
        val islands = AqiForecastMatcher.forecast(matsu.areaLocal, matsu.countyLocal, forecasts, today = "2026-11-06")!!
        assertEquals(setOf("馬祖"), islands.days.map { it.area }.toSet())
    }

    @Test
    fun datesAreTaiwanDays() {
        // 2026-10-31 17:00 UTC is already 1 November in Taiwan.
        val late = Instant.parse("2026-10-31T17:00:00Z")
        assertEquals("2026-11-01", TaiwanTime.today(late))
        assertEquals(1, TaiwanTime.daysFromToday("2026-11-02", late))

        val published = TaiwanTime.parsePublishTime("2026-10-31 16:30:00")
        assertEquals(Instant.parse("2026-10-31T08:30:00Z"), published)
        assertEquals(published, TaiwanTime.parsePublishTime("2026-10-31T16:30"))
        assertNull(TaiwanTime.parsePublishTime(""))
        assertNull(TaiwanTime.parsePublishTime("not a time"))
    }

    @Test
    fun pollutantDisplay() {
        assertEquals("PM2.5", AqiForecastPollutant.display("細懸浮微粒", chinese = false))
        assertEquals("PM10", AqiForecastPollutant.display("懸浮微粒", chinese = false))
        assertEquals("O₃ (8h)", AqiForecastPollutant.display("臭氧8小時", chinese = false))
        assertEquals("臭氧8小時", AqiForecastPollutant.display("臭氧8小時", chinese = true))
        assertNull(AqiForecastPollutant.display(" ", chinese = true))
        assertNull(AqiForecastPollutant.display("-", chinese = false))
    }

    @Test
    fun requestReadsTodayOnwardsWithBearerToken() {
        val config =
            ApiConfig(
                apiDomain = "https://api.example.com",
                directusUrl = "https://directus.example.com",
                directusToken = "abc"
            )
        val request = ApiClient.forecastRequest(config, "2026-10-31")!!
        assertEquals("Bearer abc", request.header("Authorization"))
        assertEquals("/items/twaqi_aqi_forecast", request.url.encodedPath)
        assertEquals("2026-10-31", request.url.queryParameter("filter[forecast_date][_gte]"))
        assertEquals("true", request.url.queryParameter("filter[archived][_neq]"))
        // `*`, not a field list: naming content_i18n before the token may read it fails the read.
        assertEquals("*", request.url.queryParameter("fields"))
        assertEquals("forecast_date,area", request.url.queryParameter("sort"))

        assertNull(ApiClient.forecastRequest(config.copy(directusToken = ""), "2026-10-31"))
        assertNull(ApiClient.forecastRequest(config.copy(directusUrl = ""), "2026-10-31"))
    }
}
