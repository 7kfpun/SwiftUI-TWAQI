package com.kfpun.twaqi.data

import com.kfpun.twaqi.data.model.AqiForecast
import com.kfpun.twaqi.data.model.ForecastTabArea
import com.kfpun.twaqi.data.model.ForecastTabArea.Pin
import com.kfpun.twaqi.data.model.ForecastTabOrdering
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ported from iOS `ForecastTabOrderingTests` (FOX-32). */
class ForecastTabOrderingTest {
    private val today = "2026-11-03"

    private fun row(
        area: String,
        date: String,
        aqi: Int? = 50,
        content: String? = null,
        published: String = "2026-11-03 10:30:00"
    ) = AqiForecast(area = area, forecastDate = date, aqi = aqi, content = content, publishTime = published)

    private val allAreas = listOf("馬祖", "高屏", "北部", "金門", "竹苗", "花東", "中部", "澎湖", "宜蘭", "雲嘉南").map { row(it, today) }

    private fun order(
        forecasts: List<AqiForecast>,
        reader: String? = null,
        favourites: List<String?> = emptyList(),
        chinese: Boolean = true
    ): List<ForecastTabArea> = ForecastTabOrdering.areas(forecasts, reader, favourites, today, chinese)

    @Test
    fun readerAreaFirstThenFavouritesThenRestInRegionOrder() {
        val result = order(allAreas, reader = "高屏", favourites = listOf("宜蘭", "中部"))
        assertEquals(listOf("高屏", "宜蘭", "中部", "北部", "竹苗", "雲嘉南", "花東", "澎湖", "金門", "馬祖"), result.map { it.area })
        assertEquals(listOf(Pin.READER, Pin.FAVOURITE, Pin.FAVOURITE) + List(7) { Pin.NONE }, result.map { it.pin })
    }

    @Test
    fun noLocationPinsNorthAsTheFallback() {
        val result = order(allAreas, favourites = listOf("花東"))
        assertEquals(listOf("北部", "花東"), result.take(2).map { it.area })
        assertEquals(listOf(Pin.FALLBACK, Pin.FAVOURITE), result.take(2).map { it.pin })
        assertEquals(10, result.size)
    }

    @Test
    fun readerAreaWithoutAForecastFallsBackToNorth() {
        val result = order(allAreas.filter { it.area != "澎湖" }, reader = "澎湖")
        assertEquals("北部", result.first().area)
        assertEquals(Pin.FALLBACK, result.first().pin)
        assertFalse("澎湖" in result.map { it.area })
    }

    @Test
    fun favouriteInReaderAreaAppearsOnce() {
        val result = order(allAreas, reader = "北部", favourites = listOf("北部", null, "竹苗", "竹苗"))
        assertEquals(listOf("北部", "竹苗"), result.take(2).map { it.area })
        assertEquals(listOf(Pin.READER, Pin.FAVOURITE), result.take(2).map { it.pin })
        assertEquals(result.size, result.map { it.area }.toSet().size)
    }

    @Test
    fun favouritesKeepFavouritesOrderAndSkipAreasWithoutForecast() {
        assertEquals(
            listOf("北部", "馬祖", "雲嘉南", "竹苗"),
            order(allAreas, reader = "北部", favourites = listOf("馬祖", "雲嘉南", "竹苗")).take(4).map { it.area }
        )
        assertEquals(
            listOf("北部", "中部"),
            order(
                allAreas.filter {
                    it.area != "金門"
                },
                reader = "北部",
                favourites = listOf("金門", "中部")
            ).take(2).map { it.area }
        )
    }

    @Test
    fun areaOutsideTheKnownListGoesLast() {
        assertEquals("東沙", order(allAreas + row("東沙", today), reader = "北部").last().area)
    }

    @Test
    fun everyDayTheFeedReturnsIsKept() {
        val dates = listOf("2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07")
        assertEquals(dates, order(dates.map { row("北部", it) }).first().forecast.days.map { it.forecastDate })
    }

    @Test
    fun pastDaysDroppedAndNewestPublishWins() {
        val result =
            order(listOf(row("北部", "2026-11-02"), row("北部", "2026-11-04"), row("北部", today), row("中部", "2026-11-01")))
        assertEquals(listOf("北部"), result.map { it.area })
        assertEquals(listOf(today, "2026-11-04"), result.first().forecast.days.map { it.forecastDate })

        val twice = listOf(row("北部", today, aqi = 40, published = "2026-11-02 16:30:00"), row("北部", today, aqi = 70))
        assertEquals(listOf(70), order(twice).first().forecast.days.map { it.aqi })
        assertTrue(order(emptyList(), reader = "北部", favourites = listOf("中部")).isEmpty())
    }

    @Test
    fun titlesInChineseAndEnglish() {
        assertEquals("北部空品區", ForecastTabOrdering.title("北部", chinese = true))
        assertEquals("金門", ForecastTabOrdering.title("金門", chinese = true))
        assertEquals("North", ForecastTabOrdering.title("北部", chinese = false))
        assertEquals("Matsu", ForecastTabOrdering.title("馬祖", chinese = false))
        assertEquals("東沙", ForecastTabOrdering.title("東沙", chinese = false))
        assertEquals("North", order(allAreas, chinese = false).first().forecast.areaTitle)
    }

    @Test
    fun sharedContentAndTranslation() {
        val text = "1. 今日各地擴散條件良好。"
        assertEquals(
            text,
            ForecastTabOrdering.sharedContent(
                order(listOf(row("北部", today, content = text), row("中部", today, content = text), row("花東", today)))
            )
        )
        assertNull(
            ForecastTabOrdering.sharedContent(
                order(listOf(row("北部", today, content = "北部普通。"), row("中部", today, content = "中部良好。")))
            )
        )
        assertNull(ForecastTabOrdering.sharedContent(order(listOf(row("北部", today, content = "北部普通。")))))

        val translated = row("中部", today, content = text).copy(
            contentI18n = mapOf(
                "zh-Hant" to text,
                "en" to "1. Dispersion is good everywhere today."
            )
        )
        val result = order(listOf(row("北部", today, content = text), translated, row("花東", today)))
        assertEquals("1. Dispersion is good everywhere today.", ForecastTabOrdering.sharedTranslation(result, "en"))
        assertNull(ForecastTabOrdering.sharedTranslation(result, "ja"))

        val stale = row(
            "中部",
            today,
            content = text
        ).copy(contentI18n = mapOf("zh-Hant" to "舊的文字。", "en" to "Old text."))
        assertNull(ForecastTabOrdering.sharedTranslation(order(listOf(row("北部", today, content = text), stale)), "en"))
        assertNull(ForecastTabOrdering.sharedTranslation(order(listOf(translated)), "en"))
    }
}
