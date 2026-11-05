package com.kfpun.twaqi.shortcuts

import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.Pollutant
import java.time.Duration
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * FOX-95: which station answers, what the answer card says in each language, and the tile's
 * station (iOS `AirQualityIntentTests`, FOX-74). The wording comes from the shipped strings.xml.
 */
class AirQualityAnswerTest {
    private val en = ResourceStrings.english
    private val zh = ResourceStrings.chinese

    private fun reading(
        id: Int = 12,
        name: String = "Songshan",
        nameLocal: String = "松山",
        aqi: Double = 42.0,
        pm25: Double = 9.0,
        pm10: Double = 21.0,
        o3: Double = 31.0,
        publishTime: String = "2026-11-04T10:00:00"
    ) = Pollutant(
        stationId = id,
        code = name,
        lat = 25.05,
        lon = 121.57,
        aqi = aqi,
        pm25 = pm25,
        pm10 = pm10,
        no2 = 12.5,
        so2 = 1.4,
        co = 0.3,
        o3 = o3,
        windDirection = 247.0,
        windSpeed = 2.6,
        publishTime = publishTime,
        name = name,
        nameLocal = nameLocal
    )

    /** [hours] after the reading's 10:00 Taiwan-time publish. */
    private fun time(hours: Double, reading: Pollutant): Instant =
        reading.publishedAt!!.plus(Duration.ofSeconds((hours * 3600).toLong()))

    // Which station answers

    @Test
    fun aStationAskedForAnswersItself() {
        assertEquals(
            StationResolution(StationPlan.Station(7), null),
            StationResolution.resolve(7, listOf(3, 4), locationAvailable = false)
        )
    }

    @Test
    fun nearestUsesLocationWhenTheAppHasIt() {
        assertEquals(
            StationResolution(StationPlan.Nearest, null),
            StationResolution.resolve(null, listOf(3, 4), locationAvailable = true)
        )
    }

    @Test
    fun nearestWithoutLocationFallsBackToTheFirstFavouriteAndSaysSo() {
        assertEquals(
            StationResolution(StationPlan.Station(3), StationFallbackNote.FIRST_FAVOURITE),
            StationResolution.resolve(null, listOf(3, 4), locationAvailable = false)
        )
    }

    @Test
    fun nearestWithoutLocationOrFavouritesFallsBackToTheDefault() {
        assertEquals(
            StationResolution(StationPlan.DefaultLocation, StationFallbackNote.DEFAULT_LOCATION),
            StationResolution.resolve(null, emptyList(), locationAvailable = false)
        )
    }

    // The Quick Settings tile's station (iOS Control Center control)

    @Test
    fun tileShowsTheChosenStation() {
        assertEquals(7, StationResolution.controlStationId(7, 2, listOf(3), locationAllowed = true))
    }

    @Test
    fun tileNearestFollowsTheAppsClosestWithLocation() {
        assertEquals(2, StationResolution.controlStationId(null, 2, listOf(3), locationAllowed = true))
    }

    @Test
    fun tileNearestWithoutLocationShowsTheFirstFavourite() {
        assertEquals(3, StationResolution.controlStationId(null, 2, listOf(3, 4), locationAllowed = false))
    }

    @Test
    fun tileNearestWithoutLocationOrFavouritesShowsTheAppsLastStation() {
        assertEquals(2, StationResolution.controlStationId(null, 2, emptyList(), locationAllowed = false))
        assertNull(StationResolution.controlStationId(null, null, emptyList(), locationAllowed = true))
    }

    @Test
    fun tileNearestWithLocationButNoStationYetShowsTheFirstFavourite() {
        assertEquals(3, StationResolution.controlStationId(null, null, listOf(3), locationAllowed = true))
    }

    // Answer text

    @Test
    fun liveAnswerInEnglish() {
        val reading = reading()
        assertEquals(
            "Songshan: AQI 42, Good. Enjoy your usual outdoor activities.",
            AirQualityAnswer.text(reading, AnswerFreshness.LIVE, null, en, time(0.5, reading))
        )
    }

    @Test
    fun liveAnswerInChinese() {
        val reading = reading()
        assertEquals(
            "松山：AQI 42，良好。可正常從事戶外活動。",
            AirQualityAnswer.text(reading, AnswerFreshness.LIVE, null, zh, time(0.5, reading))
        )
    }

    @Test
    fun answerNamesTheMainPollutantPastGood() {
        val reading = reading(aqi = 120.0, pm25 = 40.0)
        assertEquals(
            "Songshan: AQI 120, Unhealthy for sensitive groups. Main pollutant: PM2.5. " +
                "Consider reducing outdoor activities.",
            AirQualityAnswer.text(reading, AnswerFreshness.LIVE, null, en, time(0.5, reading))
        )
    }

    @Test
    fun noReadingInBothLanguages() {
        assertEquals(
            "There's no reading yet. Open Taiwan Air once while online.",
            AirQualityAnswer.text(null, AnswerFreshness.CACHED, null, en)
        )
        assertEquals(
            "目前還沒有數值。請在有網路時開啟 Taiwan Air 一次。",
            AirQualityAnswer.text(null, AnswerFreshness.CACHED, null, zh)
        )
    }

    @Test
    fun cachedReadingSaysHowOldItIs() {
        val reading = reading()
        val now = time(3.2, reading)
        assertEquals(
            "Songshan: AQI 42, Good. Enjoy your usual outdoor activities. " +
                "You're offline, so this is the last saved reading, from 3 hours ago.",
            AirQualityAnswer.text(reading, AnswerFreshness.CACHED, null, en, now)
        )
        assertEquals(
            "松山：AQI 42，良好。可正常從事戶外活動。目前沒有網路，這是最後儲存的數值，為 3小時前的資料。",
            AirQualityAnswer.text(reading, AnswerFreshness.CACHED, null, zh, now)
        )
    }

    @Test
    fun cachedReadingJustPublishedStillSaysItIsSaved() {
        val reading = reading()
        val text = AirQualityAnswer.text(reading, AnswerFreshness.CACHED, null, en, time(0.25, reading))
        assertTrue(text, text.endsWith("You're offline, so this is the last saved reading, from 15 minutes ago."))
    }

    @Test
    fun aCachedReadingWhoseTimeDoesNotParseSaysItIsSaved() {
        val text = AirQualityAnswer.text(reading(publishTime = ""), AnswerFreshness.CACHED, null, en)
        assertTrue(
            text,
            text.endsWith("Enjoy your usual outdoor activities. You're offline, so this is the last saved reading.")
        )
    }

    @Test
    fun staleLiveReadingSaysHowOldItIs() {
        val reading = reading()
        val fresh = AirQualityAnswer.text(reading, AnswerFreshness.LIVE, null, en, time(1.9, reading))
        assertFalse(fresh, fresh.contains("ago"))

        val stale = AirQualityAnswer.text(reading, AnswerFreshness.LIVE, null, en, time(50.0, reading))
        assertTrue(stale, stale.endsWith("This reading is from 2 days ago."))
        val staleZh = AirQualityAnswer.text(reading, AnswerFreshness.LIVE, null, zh, time(50.0, reading))
        assertTrue(staleZh, staleZh.endsWith("這筆數值是 2天前發布的。"))
    }

    @Test
    fun oneUnitIsSingularInEnglish() {
        assertEquals("1 hour", AirQualityAnswer.ageString(Duration.ofMinutes(61), en))
        assertEquals("1 minute", AirQualityAnswer.ageString(Duration.ofSeconds(5), en))
        assertEquals("47 hours", AirQualityAnswer.ageString(Duration.ofHours(47), en))
    }

    @Test
    fun fallbackIsSaidFirst() {
        val reading = reading()
        val now = time(0.5, reading)
        assertEquals(
            "Taiwan Air doesn't have your location, so here is your first favourite. " +
                "Songshan: AQI 42, Good. Enjoy your usual outdoor activities.",
            AirQualityAnswer.text(reading, AnswerFreshness.LIVE, StationFallbackNote.FIRST_FAVOURITE, en, now)
        )
        assertEquals(
            "Taiwan Air 無法取得你的位置，以下是你的第一個最愛測站。松山：AQI 42，良好。可正常從事戶外活動。",
            AirQualityAnswer.text(reading, AnswerFreshness.LIVE, StationFallbackNote.FIRST_FAVOURITE, zh, now)
        )
    }

    @Test
    fun defaultFallbackIsSaidFirst() {
        val text = AirQualityAnswer.text(null, AnswerFreshness.CACHED, StationFallbackNote.DEFAULT_LOCATION, en)
        assertTrue(text, text.startsWith("Taiwan Air doesn't have your location and you have no favourites"))
    }

    @Test
    fun aReadingWithoutAQISaysSo() {
        assertEquals(
            "Songshan has no AQI reading right now.",
            AirQualityAnswer.text(reading(aqi = 0.0), AnswerFreshness.LIVE, null, en)
        )
        assertEquals(
            "松山目前沒有 AQI 數值。",
            AirQualityAnswer.text(reading(aqi = 0.0), AnswerFreshness.LIVE, null, zh)
        )
    }

    // Main pollutant

    @Test
    fun noMainPollutantWhileGood() {
        assertNull(AirQualityAnswer.mainPollutant(reading(aqi = 42.0, pm25 = 40.0)))
    }

    @Test
    fun mainPollutantIsTheWorstBand() {
        assertEquals(AirIndexType.O3, AirQualityAnswer.mainPollutant(reading(aqi = 130.0, pm25 = 9.0, o3 = 140.0)))
    }

    @Test
    fun mainPollutantTiesGoToPM25First() {
        // PM2.5 and PM10 both moderate.
        assertEquals(AirIndexType.PM25, AirQualityAnswer.mainPollutant(reading(aqi = 60.0, pm25 = 20.0, pm10 = 60.0)))
    }

    @Test
    fun noMainPollutantWhenEveryPollutantIsGood() {
        assertNull(AirQualityAnswer.mainPollutant(reading(aqi = 60.0, pm25 = 9.0, pm10 = 21.0)))
    }

    // The tile's text

    @Test
    fun tileShowsTheAqiTheStationAndTheLevel() {
        val content = AirQualityTileContent.of(12, reading(), chinese = true, statusLabel = zh.status, noStation = "-")
        assertEquals(AirQualityTileContent(12, "AQI 42", "松山 · 良好", com.kfpun.twaqi.data.model.AirStatus.GOOD), content)
        assertEquals(com.kfpun.twaqi.R.drawable.ic_tile_aqi_low, content.icon)
    }

    @Test
    fun tileWithoutAReadingAsksToOpenTheApp() {
        val content = AirQualityTileContent.of(null, null, chinese = false, statusLabel = en.status, noStation = "Open")
        assertEquals("AQI –", content.title)
        assertEquals("Open", content.subtitle)
        assertNull(content.stationId)

        val noAqi = AirQualityTileContent.of(
            12,
            reading(aqi = 0.0),
            chinese = false,
            statusLabel = en.status,
            noStation = "Open"
        )
        assertEquals("Songshan", noAqi.subtitle)
        assertEquals(12, noAqi.stationId)
    }
}
