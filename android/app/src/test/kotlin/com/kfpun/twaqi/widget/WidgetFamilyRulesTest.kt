package com.kfpun.twaqi.widget

import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.ui.main.pollutant
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** FOX-59: what each widget size does, and what a free user sees against a Pro one (iOS `WidgetFamilyRules`). */
class WidgetFamilyRulesTest {
    private val now = Instant.ofEpochSecond(1_793_000_000)

    @Test
    fun sizeDecidesTheFamily() {
        assertEquals(WidgetFamily.SMALL, WidgetFamily.forSize(110f, 110f))
        assertEquals(WidgetFamily.SMALL, WidgetFamily.forSize(180f, 400f))
        assertEquals(WidgetFamily.MEDIUM, WidgetFamily.forSize(250f, 110f))
        assertEquals(WidgetFamily.MEDIUM, WidgetFamily.forSize(320f, 249f))
        assertEquals(WidgetFamily.LARGE, WidgetFamily.forSize(250f, 250f))
        assertEquals(WidgetFamily.LARGE, WidgetFamily.forSize(400f, 500f))
    }

    @Test
    fun onlySmallIsFree() {
        WidgetFamily.entries.forEach { family ->
            val pro = family != WidgetFamily.SMALL
            assertEquals("$family", pro, WidgetFamilyRules.isProFamily(family))
            assertEquals("$family", pro, WidgetFamilyRules.isLocked(family, isPro = false))
            assertFalse("$family", WidgetFamilyRules.isLocked(family, isPro = true))
            // The widget picker previews every size unlocked.
            assertFalse("$family", WidgetFamilyRules.isLocked(family, isPro = false, isPreview = true))
        }
    }

    @Test
    fun onlyMediumAndLargePageAndOnlyStationDetailShowsHistory() {
        assertEquals(
            setOf(WidgetFamily.MEDIUM, WidgetFamily.LARGE),
            WidgetFamily.entries.filter(WidgetFamilyRules::pagesFavourites).toSet()
        )
        assertEquals(
            listOf(WidgetFamily.STATION_DETAIL),
            WidgetFamily.entries.filter(WidgetFamilyRules::showsStationDetail)
        )
        assertEquals(
            setOf(WidgetFamily.LARGE, WidgetFamily.STATION_DETAIL),
            WidgetFamily.entries.filter(WidgetFamilyRules::showsForecast).toSet()
        )
        assertFalse(WidgetFamilyRules.listsFavourites(WidgetFamily.STATION_DETAIL))
    }

    // Entries: free against Pro

    private val readings = listOf(10, 1, 2, 3).associateWith { pollutant(it) }

    private fun entry(
        family: WidgetFamily,
        isPro: Boolean,
        state: WidgetPageState = WidgetPageState(),
        favourites: List<Int> = listOf(1, 2, 3)
    ) = WidgetEntry.make(
        family = family,
        leading = readings.getValue(10),
        config = WidgetConfig(index = AirIndexType.PM25),
        favouriteIds = favourites,
        readings = readings,
        isPro = isPro,
        state = state,
        now = now
    )

    @Test
    fun freeSmallShowsItsStationAndFavourites() {
        val small = entry(WidgetFamily.SMALL, isPro = false)
        assertFalse(small.isLocked)
        assertEquals(10, small.reading?.stationId)
        assertEquals(listOf(1, 2), small.listedFavourites.map { it.stationId })
        assertTrue(small.cyclesIndex)
        assertFalse(small.showsPager)
    }

    @Test
    fun freeMediumLargeAndStationDetailAreLocked() {
        listOf(WidgetFamily.MEDIUM, WidgetFamily.LARGE, WidgetFamily.STATION_DETAIL).forEach { family ->
            val locked = entry(family, isPro = false)
            assertTrue("$family", locked.isLocked)
            assertFalse("$family", locked.showsPager)
            assertFalse("$family", locked.cyclesIndex)
        }
    }

    @Test
    fun proMediumAndLargePageThroughFavourites() {
        val medium = entry(WidgetFamily.MEDIUM, isPro = true)
        assertTrue(medium.showsPager)
        assertEquals(listOf(10, 1, 2, 3), medium.pageIds)
        assertEquals(2, medium.listedFavourites.size)
        assertEquals(3, entry(WidgetFamily.LARGE, isPro = true).listedFavourites.size)
        // One favourite: no pager.
        assertFalse(entry(WidgetFamily.MEDIUM, isPro = true, favourites = listOf(1)).showsPager)
    }

    @Test
    fun pagedEntryShowsTheFavouriteAndListsTheRestWithoutIt() {
        val paged =
            entry(
                WidgetFamily.LARGE,
                isPro = true,
                state = WidgetPageState(stationId = 2, tappedAt = now.minusSeconds(60))
            )
        assertEquals(2, paged.page)
        assertEquals(2, paged.reading?.stationId)
        assertEquals(listOf(1, 3), paged.favourites.map { it.stationId })
    }

    @Test
    fun cycledIndexIsShownExceptOnStationDetail() {
        val cycled = WidgetPageState(index = AirIndexType.O3.key, tappedAt = now)
        assertEquals(AirIndexType.O3, entry(WidgetFamily.SMALL, isPro = false, state = cycled).type)
        assertEquals(AirIndexType.PM25, entry(WidgetFamily.STATION_DETAIL, isPro = true, state = cycled).type)
    }

    @Test
    fun favouriteWithoutAReadingIsLeftOut() {
        val withMissing = entry(WidgetFamily.LARGE, isPro = true, favourites = listOf(1, 99, 2))
        assertEquals(listOf(1, 2), withMissing.favourites.map { it.stationId })
    }

    @Test
    fun noReadingLeavesNothingToShow() {
        val empty = WidgetEntry.make(
            WidgetFamily.MEDIUM,
            leading = null,
            config = WidgetConfig(),
            favouriteIds = emptyList(),
            readings = emptyMap(),
            isPro = true,
            state = WidgetPageState(),
            now = now
        )
        assertNull(empty.reading)
        assertFalse(empty.showsPager)
    }

    @Test
    fun largeKeepsRoomForTheForecast() {
        // A 4×3 phone large widget: the forecast stays, a favourite and the indices give way.
        val withForecast = WidgetFamilyRules.largeFit(340f, hasForecast = true, favourites = 4)
        assertFalse(withForecast.showsOtherIndices)
        assertEquals(3, withForecast.favouriteRows)
        // Without a forecast the same size shows the indices and all four favourites.
        val noForecast = WidgetFamilyRules.largeFit(340f, hasForecast = false, favourites = 4)
        assertTrue(noForecast.showsOtherIndices)
        assertEquals(4, noForecast.favouriteRows)
        // Tall enough, everything fits.
        assertEquals(LargeFit(true, 4), WidgetFamilyRules.largeFit(460f, hasForecast = true, favourites = 4))
    }

    @Test
    fun largeAlwaysListsAFavouriteItHasAndNeverMoreThanItHas() {
        assertEquals(1, WidgetFamilyRules.largeFit(250f, hasForecast = true, favourites = 4).favouriteRows)
        assertEquals(0, WidgetFamilyRules.largeFit(250f, hasForecast = true, favourites = 0).favouriteRows)
        assertEquals(2, WidgetFamilyRules.largeFit(600f, hasForecast = true, favourites = 2).favouriteRows)
    }
}
