package com.kfpun.twaqi.widget

import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.TaiwanTime
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** FOX-120: the widget picker's previews draw the bundled sample stations, the Pro sizes unlocked (iOS `isPreview`). */
class WidgetPreviewTest {
    // 2026-11-06 08:30 in Taipei.
    private val now = Instant.parse("2026-11-06T00:30:00Z")
    private val snapshot = WidgetPreviewData.snapshot(now)

    @Test
    fun previewUnlocksEveryProSizeForAFreeUser() {
        assertFalse(snapshot.isPro)
        WidgetFamily.entries.forEach { family ->
            val preview = WidgetPreviewData.entry(family, snapshot, now)
            assertFalse("$family preview is unlocked", preview.isLocked)
            assertEquals("$family", WidgetPreviewData.leading, preview.reading)
        }
    }

    @Test
    fun theSameSampleOutsideThePreviewLocksTheProSizes() {
        WidgetFamily.entries.forEach { family ->
            val placed = WidgetEntry.make(
                family = family,
                leading = snapshot.leading,
                config = snapshot.config,
                favouriteIds = snapshot.favouriteIds,
                readings = snapshot.readings,
                isPro = false,
                state = WidgetPageState(),
                now = now
            )
            assertEquals("$family", WidgetFamilyRules.isProFamily(family), placed.isLocked)
        }
    }

    @Test
    fun previewShowsWhatEachSizeDoes() {
        val small = WidgetPreviewData.entry(WidgetFamily.SMALL, snapshot, now)
        assertEquals(listOf(-1, -2), small.listedFavourites.map { it.stationId })
        assertTrue(small.cyclesIndex)

        val medium = WidgetPreviewData.entry(WidgetFamily.MEDIUM, snapshot, now)
        assertTrue(medium.showsPager)
        assertEquals(listOf(0, -1, -2, -3), medium.pageIds)
        assertEquals(0, medium.page)

        val large = WidgetPreviewData.entry(WidgetFamily.LARGE, snapshot, now)
        assertEquals(3, large.listedFavourites.size)

        val detail = WidgetPreviewData.entry(WidgetFamily.STATION_DETAIL, snapshot, now)
        assertTrue(detail.favourites.isEmpty())
        assertEquals(AirIndexType.AQI, detail.type)
    }

    @Test
    fun sampleStationsHaveEnglishAndChineseNamesAndNoRealIds() {
        val stations = listOf(WidgetPreviewData.leading) + WidgetPreviewData.favourites
        assertEquals(listOf("Songshan", "Banqiao", "Hsinchu", "Tainan"), stations.map { it.displayName(false) })
        assertEquals(listOf("松山", "板橋", "新竹", "臺南"), stations.map { it.displayName(true) })
        stations.forEach {
            assertTrue("${it.name} keeps clear of real station ids", it.stationId <= 0)
            assertNotNull(it.displayArea(false))
            assertNotNull(it.displayArea(true))
        }
        // Levels the preview shows: Good, Moderate, Good, Unhealthy for sensitive groups.
        assertEquals(listOf(42, 58, 35, 104), stations.map { it.aqi.toInt() })
    }

    @Test
    fun forecastAndHistoryAreTheSampleDayInTaiwanTime() {
        val forecast = snapshot.forecast(WidgetPreviewData.leading, chinese = true, now = now)
        assertNotNull(forecast)
        assertEquals(listOf("2026-11-06", "2026-11-07"), forecast!!.days.map { it.forecastDate })
        assertEquals("北部空品區", forecast.areaTitle)
        assertEquals("North", snapshot.forecast(WidgetPreviewData.leading, chinese = false, now = now)?.areaTitle)

        val history = snapshot.history
        assertEquals(24, history.size)
        assertEquals("2026-11-06T08:00:00", history.last().publishTime)
        assertEquals("2026-11-05T09:00:00", history.first().publishTime)
        assertEquals(TaiwanTime.parsePublishTime("2026-11-06 08:00:00"), history.last().publishedAt)
        assertEquals(42.0, history.last().aqi, 0.0)
    }

    @Test
    fun previewIsPublishedAgainAfterAnUpdateOrInAnotherLanguage() {
        val drawn = WidgetPreviews.drawnWith(lastUpdateTime = 1L, languageTag = "en")
        assertEquals(drawn, WidgetPreviews.drawnWith(1L, "en"))
        assertNotEquals(drawn, WidgetPreviews.drawnWith(2L, "en"))
        assertNotEquals(drawn, WidgetPreviews.drawnWith(1L, "zh-TW"))
    }

    @Test
    fun previewSizesCoverEveryAirQualityFamily() {
        val families = WidgetPreviews.airQualitySizes.map {
            WidgetFamily.forSize(it.width.value, it.height.value)
        }.toSet()
        assertEquals(setOf(WidgetFamily.SMALL, WidgetFamily.MEDIUM, WidgetFamily.LARGE), families)
    }
}
