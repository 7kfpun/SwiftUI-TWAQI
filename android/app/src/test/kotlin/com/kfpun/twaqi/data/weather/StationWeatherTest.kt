package com.kfpun.twaqi.data.weather

import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.Fixtures
import com.kfpun.twaqi.ui.station.weather.WeatherFormat
import java.io.File
import java.time.Duration
import java.time.Instant
import java.util.Locale
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

/** Ported from iOS `StationWeatherTests` (FOX-11): the Worker's file, the station join, codes and formatting. */
class StationWeatherTest {
    /** 12:40 Taiwan time on 5 Nov. */
    private val now = Instant.parse("2026-11-05T04:40:00Z")

    // AQI stations (MOENV positions).
    private val zhongshan = 25.062361 to 121.526528 // 中山, Taipei
    private val hualien = 23.971306 to 121.599769 // 花蓮
    private val yangming = 25.182722 to 121.529583 // 陽明, near 竹子湖
    private val lanyu = 22.03 to 121.55 // 蘭嶼: no CWA station in the file within 20 km

    private fun file(): WeatherFile = WeatherFile.parse(Fixtures.read("weather-latest.json"))

    private fun weather(at: Pair<Double, Double>, county: String?, now: Instant = this.now) =
        StationWeatherMatcher.weather(at.first, at.second, county, file(), now)

    // Decoding

    @Test
    fun decodesTheWorkerFile() {
        val file = file()
        assertEquals(2, file.forecast?.counties?.size)
        assertEquals(
            WeatherPeriod("2026-11-05T12:00:00+08:00", "2026-11-05T18:00:00+08:00", 4, "多雲", 10.0, 23.0, 27.0),
            file.forecast?.counties?.get("臺北市")?.first()
        )
        assertNull(file.forecast?.counties?.get("花蓮縣")?.get(2)?.pop)
        val taipei = file.observations!!.stations.first()
        assertEquals("臺北", taipei.name)
        assertEquals(75.0, taipei.humidity)
        assertNull(file.observations!!.stations[1].wind)
        assertEquals(Instant.parse("2026-11-05T04:00:00Z"), taipei.observedAt)
    }

    @Test
    fun decodesSectionsThatNeverLoaded() {
        val file = WeatherFile.parse(
            """{ "version": 1, "updatedAt": "2026-11-05T04:40:00.000Z", "forecast": null, "observations": null }"""
        )
        assertNull(file.forecast)
        assertNull(file.observations)
        // Hidden state: nothing to show.
        assertNull(StationWeatherMatcher.weather(zhongshan.first, zhongshan.second, "臺北市", file, now))
    }

    @Test(expected = WeatherFormatException::class)
    fun aBodyThatIsNotTheFileFails() {
        WeatherFile.parse("<html>busy</html>")
    }

    @Test
    fun periodTimesAreTaiwanTime() {
        val periods = file().forecast!!.counties.getValue("臺北市")
        val period = periods[1]
        assertEquals(Instant.parse("2026-11-05T10:00:00Z"), period.startInstant)
        assertTrue(period.isNight)
        assertFalse(periods[0].isNight)
        assertEquals("11/5 18:00–06:00", WeatherFormat.timeRange(period))
        // No offset: read as Taiwan time.
        assertEquals(period.startInstant, WeatherDates.parse("2026-11-05 18:00:00"))
    }

    // Nearest station

    @Test
    fun taipeiGetsTheNearestFreshStationAndItsCounty() {
        val weather = weather(zhongshan, "臺北市")!!
        assertEquals("466920", weather.now?.observation?.id)
        assertEquals(2.9, weather.now!!.distanceKm, 0.2)
        assertEquals("臺北市", weather.county)
        assertEquals(listOf(4, 8, 11), weather.periods.map { it.wx })
    }

    @Test
    fun hualienGetsHualien() {
        val weather = weather(hualien, "花蓮縣")!!
        assertEquals("花蓮", weather.now?.observation?.name)
        assertEquals("花蓮縣", weather.county)
        assertEquals(3, weather.periods.size)
    }

    @Test
    fun noStationWithinTwentyKilometresMeansNoReading() {
        val stations = file().observations!!.stations
        assertNull(StationWeatherMatcher.nearest(lanyu.first, lanyu.second, stations, now))

        // 20 km is the edge: just inside counts, just outside doesn't.
        val taipei = stations[0]
        val degreesPerKm = 1 / 111.195
        assertNotNull(StationWeatherMatcher.nearest(taipei.lat + 19.9 * degreesPerKm, taipei.lon, listOf(taipei), now))
        assertNull(StationWeatherMatcher.nearest(taipei.lat + 20.1 * degreesPerKm, taipei.lon, listOf(taipei), now))
    }

    @Test
    fun stationWithoutPositionHasNoReading() {
        val stations = file().observations!!.stations
        assertNull(StationWeatherMatcher.nearest(0.0, 0.0, stations, now))
        // …but still gets its county's forecast.
        val weather = weather(0.0 to 0.0, "臺北市")!!
        assertNull(weather.now)
        assertEquals(3, weather.periods.size)
    }

    // Staleness

    @Test
    fun staleReadingGivesWayToAFreshOneFurtherOff() {
        // 竹子湖 is closest to 陽明 but its reading is 5 h 40 min old; 臺北 is ~16 km off with a fresh one.
        val stations = file().observations!!.stations
        assertEquals(
            "466930",
            StationWeatherMatcher.nearest(yangming.first, yangming.second, stations, null)?.observation?.id
        )
        assertEquals(
            "466920",
            StationWeatherMatcher.nearest(yangming.first, yangming.second, stations, now)?.observation?.id
        )
    }

    @Test
    fun readingAgeLimits() {
        val limit = StationWeatherMatcher.maxObservationAge
        assertTrue(StationWeatherMatcher.isFresh(now.minus(limit), now))
        assertFalse(StationWeatherMatcher.isFresh(now.minus(limit).minusSeconds(1), now))
        assertTrue(StationWeatherMatcher.isFresh(now.plus(Duration.ofMinutes(5)), now))
        assertFalse(StationWeatherMatcher.isFresh(now.plus(Duration.ofHours(1)), now))
    }

    @Test
    fun endedPeriodsAreDropped() {
        val periods = file().forecast!!.counties.getValue("臺北市")
        // 19:00 on the 5th: the 12–18 period is over, the next three remain.
        val evening = now.plus(Duration.ofMinutes(6 * 60 + 20))
        assertEquals(listOf(8, 11, 7), StationWeatherMatcher.upcoming(periods, evening).map { it.wx })
        // A period ending exactly now is over.
        val sixPm = Instant.parse("2026-11-05T10:00:00Z")
        assertEquals(8, StationWeatherMatcher.upcoming(periods, sixPm).first().wx)
    }

    @Test
    fun aWeekOldFileShowsNothing() {
        // Offline for days: every reading is stale and every period has ended.
        assertNull(weather(zhongshan, "臺北市", now.plus(Duration.ofDays(3))))
    }

    // County

    @Test
    fun countyFallsBackToTheNearestStationsAndAcceptsTaiVariant() {
        val counties = setOf("臺北市", "花蓮縣")
        val hualienStation = WeatherObservation("466990", "花蓮", "花蓮縣", 0.0, 0.0, "", null, null, null, null)
        assertEquals("臺北市", StationWeatherMatcher.county("台北市", null, counties))
        assertEquals("花蓮縣", StationWeatherMatcher.county(null, hualienStation, counties))
        assertEquals("花蓮縣", StationWeatherMatcher.county("連江縣", hualienStation, counties))
        assertNull(StationWeatherMatcher.county("連江縣", null, counties))
    }

    @Test
    fun hiddenWhenNothingIsInRangeOrInTheForecast() {
        assertNull(weather(lanyu, "臺東縣"))
        assertNull(weather(0.0 to 0.0, null))
    }

    @Test
    fun forecastWithoutAReadingStillShows() {
        // 21:40 on the 6th: the 12:00 reading on the 5th is long stale, the 18:00–06:00 period is still on.
        val weather = weather(zhongshan, "臺北市", now.plus(Duration.ofHours(33)))!!
        assertNull(weather.now)
        assertEquals(listOf(7), weather.periods.map { it.wx })
    }

    // Weather codes

    @Test
    fun everyCodeHasEnglishAndChineseText() {
        assertEquals(41, WeatherCode.all.size)
        assertFalse(40 in WeatherCode.all)
        for (code in WeatherCode.all) {
            // Each code points at its own string, `weather_wx_<code>`.
            assertEquals("weather_wx_$code", stringNames[WeatherCode.stringRes(code)])
            val english = WeatherCode.text(code, null, chinese = false, getString = english::getValue)!!
            assertTrue("$code", english.isNotEmpty())
            assertFalse("$code: $english", han.containsMatchIn(english))
            val chinese = WeatherCode.text(code, null, chinese = true, getString = chinese::getValue)!!
            assertTrue("$code: $chinese", han.containsMatchIn(chinese))
        }
        assertNull(WeatherCode.stringRes(40))
    }

    @Test
    fun chineseShowsCwasTextAndEnglishNeverDoes() {
        val get = english::getValue
        assertEquals("午後短暫陣雨", WeatherCode.text(8, "午後短暫陣雨", chinese = true, getString = get))
        assertEquals(
            "Partly cloudy, occasional showers",
            WeatherCode.text(8, "午後短暫陣雨", chinese = false, getString = get)
        )
        // A code this build doesn't know: no English rather than Chinese.
        assertNull(WeatherCode.text(40, "新天氣", chinese = false, getString = get))
        assertNull(WeatherCode.text(null, "新天氣", chinese = false, getString = get))
        assertEquals("新天氣", WeatherCode.text(99, "新天氣", chinese = true, getString = get))
        // Chinese without CWA's text falls back to the app's own.
        assertEquals("多雲短暫陣雨", WeatherCode.text(8, "", chinese = true, getString = chinese::getValue))
    }

    @Test
    fun everyCodeHasAnIcon() {
        for (code in WeatherCode.all + listOf(40, 99)) {
            for (night in listOf(false, true)) assertNotNull(WeatherCode.icon(code, night))
        }
        assertEquals(WeatherIcon.SUN_MAX, WeatherCode.icon(1, night = false))
        assertEquals(WeatherIcon.MOON_STARS, WeatherCode.icon(1, night = true))
        assertEquals(WeatherIcon.CLOUD_BOLT_RAIN, WeatherCode.icon(18, night = false))
        assertEquals(WeatherIcon.SNOWFLAKE, WeatherCode.icon(42, night = true))
        assertEquals(WeatherIcon.CLOUD, WeatherCode.icon(null, night = false))
    }

    // Formatting

    @Test
    fun formatting() {
        assertEquals("24°", WeatherFormat.temperature(24.3))
        assertEquals("0°", WeatherFormat.temperature(-0.4))
        assertEquals("-3°", WeatherFormat.temperature(-2.5))
        assertEquals("—", WeatherFormat.temperature(null))
        assertEquals("21–28°", WeatherFormat.temperatureRange(21.0, 27.6))
        assertEquals("27°", WeatherFormat.temperatureRange(null, 27.0))
        assertEquals("—", WeatherFormat.temperatureRange(null, null))
        assertEquals("30%", WeatherFormat.percent(30.0))
        assertEquals("0.5 mm", WeatherFormat.millimetres(0.5))
        assertEquals("—", WeatherFormat.windSpeed(null))
        assertEquals("3.2 m/s", WeatherFormat.windSpeed(3.2))
    }

    /**
     * 02:00 Thursday (Taiwan): the 18:00–06:00 period that started Wednesday is running, so it is
     * today, not Wednesday; the next one starts today too. Holds in any device time zone.
     */
    @Test
    fun periodRunningPastMidnightIsToday() {
        val zone = java.util.TimeZone.getDefault()
        java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone("America/Los_Angeles"))
        try {
            val night = period("2026-11-04T18:00:00+08:00", "2026-11-05T06:00:00+08:00")
            val day = period("2026-11-05T06:00:00+08:00", "2026-11-05T18:00:00+08:00")
            val tonight = period("2026-11-05T18:00:00+08:00", "2026-11-06T06:00:00+08:00")
            val today = english.getValue(R.string.forecast_today)
            val tomorrow = english.getValue(R.string.forecast_tomorrow)

            val twoAm = WeatherDates.parse("2026-11-05T02:00:00+08:00")!!
            assertEquals(today, dayTitle(night, twoAm))
            assertEquals(today, dayTitle(day, twoAm))

            // At 20:00 the period that starts tonight is today; at 06:00 the night one has ended.
            assertEquals(today, dayTitle(tonight, WeatherDates.parse("2026-11-05T20:00:00+08:00")!!))
            assertNotEquals(today, dayTitle(night, WeatherDates.parse("2026-11-05T06:00:00+08:00")!!))

            // The running night and tonight both read 18:00–06:00; the start date tells them apart.
            assertEquals("11/4 18:00–06:00", WeatherFormat.timeRange(night))
            assertEquals("11/5 18:00–06:00", WeatherFormat.timeRange(tonight))
            assertEquals("06:00–18:00", WeatherFormat.timeRange(day))

            // A later period keeps its own day; further out it is the weekday, in the app's language.
            val next = period("2026-11-06T06:00:00+08:00", "2026-11-06T18:00:00+08:00")
            assertEquals(tomorrow, dayTitle(next, twoAm))
            val later = period("2026-11-08T06:00:00+08:00", "2026-11-08T18:00:00+08:00")
            assertEquals("Sunday", dayTitle(later, twoAm))
            assertEquals(
                "星期日",
                WeatherFormat.dayTitle(later, twoAm, Locale.forLanguageTag("zh-TW"), chinese::getValue)
            )
        } finally {
            java.util.TimeZone.setDefault(zone)
        }
    }

    private fun period(start: String, end: String) = WeatherPeriod(start, end, 1, null, 0.0, 20.0, 24.0)

    private fun dayTitle(period: WeatherPeriod, now: Instant) =
        WeatherFormat.dayTitle(period, now, Locale.ENGLISH, english::getValue)

    private companion object {
        val han = Regex("\\p{IsHan}")

        /** `R.string` ids → their names, for reading the strings files without a device. */
        val stringNames: Map<Int, String> =
            R.string::class.java.fields.associate { it.getInt(null) to it.name }

        val english: Map<Int, String> = strings("values")
        val chinese: Map<Int, String> = strings("values-zh-rTW")

        /** Unit tests run from the module directory (android/app). */
        fun strings(folder: String): Map<Int, String> {
            val document = DocumentBuilderFactory.newInstance().newDocumentBuilder()
                .parse(File("src/main/res/$folder/strings.xml"))
            val nodes = document.getElementsByTagName("string")
            val byName = (0 until nodes.length).associate {
                val element = nodes.item(it) as Element
                element.getAttribute("name") to element.textContent.replace("\\'", "'")
            }
            return stringNames.mapNotNull { (id, name) -> byName[name]?.let { id to it } }.toMap()
        }
    }
}
