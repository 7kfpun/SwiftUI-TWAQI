package com.kfpun.twaqi.widget

import com.kfpun.twaqi.data.model.AirIndexType
import java.time.Duration
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** FOX-59 (iOS FOX-76, `WidgetPagingTests`): paging a widget through favourites and cycling its index. */
class WidgetPagingTest {
    private val now = Instant.ofEpochSecond(1_793_000_000)

    /** Closest station 10, favourites 1, 2, 3. */
    private val pages = WidgetPaging.pageIds(defaultId = 10, favouriteIds = listOf(1, 2, 3))

    private fun state(on: Int?, tappedSecondsAgo: Long) =
        WidgetPageState(stationId = on, tappedAt = now.minusSeconds(tappedSecondsAgo))

    // Pages

    @Test
    fun pagesStartWithTheWidgetsStationThenFavouritesInOrder() {
        assertEquals(listOf(10, 1, 2, 3), pages)
    }

    @Test
    fun widgetsStationThatIsAFavouriteIsNotRepeated() {
        assertEquals(listOf(1, 2, 3), WidgetPaging.pageIds(1, listOf(1, 2, 3)))
        assertEquals(listOf(2, 1, 3), WidgetPaging.pageIds(2, listOf(1, 2, 3, 2)))
    }

    @Test
    fun pagesWithoutAStationAreTheFavourites() {
        assertEquals(listOf(4, 5), WidgetPaging.pageIds(null, listOf(4, 5)))
    }

    @Test
    fun noButtonsWithNoneOrOneFavourite() {
        assertFalse(WidgetPaging.showsPager(favouriteCount = 0, pageCount = 1))
        assertFalse(WidgetPaging.showsPager(favouriteCount = 1, pageCount = 2))
        assertTrue(WidgetPaging.showsPager(favouriteCount = 2, pageCount = 3))
        assertTrue(WidgetPaging.showsPager(favouriteCount = 2, pageCount = 2))
        // Two favourites saved, but only one with a reading to show.
        assertFalse(WidgetPaging.showsPager(favouriteCount = 2, pageCount = 1))
    }

    // Next / previous

    @Test
    fun nextAndPreviousWrap() {
        assertEquals(1, WidgetPaging.page(from = 0, step = 1, count = 4))
        assertEquals(0, WidgetPaging.page(from = 3, step = 1, count = 4))
        assertEquals(3, WidgetPaging.page(from = 0, step = -1, count = 4))
        assertEquals(1, WidgetPaging.page(from = 2, step = -1, count = 4))
        assertEquals(0, WidgetPaging.page(from = 0, step = 1, count = 0))
    }

    @Test
    fun buttonTargetsStoreNullForTheDefaultPage() {
        assertNull(WidgetPaging.target(0, pages))
        assertEquals(1, WidgetPaging.target(1, pages))
        assertEquals(3, WidgetPaging.target(3, pages))
        assertNull(WidgetPaging.target(9, pages))
    }

    @Test
    fun steppingThroughEveryPageComesBackToTheDefault() {
        var state = WidgetPageState()
        val shown = mutableListOf<Int>()
        repeat(pages.size) {
            val current = WidgetPaging.currentPage(state, pages, now)
            shown += pages[current]
            val next = WidgetPaging.page(current, 1, pages.size)
            state = WidgetPaging.paged(state, WidgetPaging.target(next, pages), now)
        }
        assertEquals(listOf(10, 1, 2, 3), shown)
        assertEquals(0, WidgetPaging.currentPage(state, pages, now))
        assertNull(state.stationId)
    }

    // Default page

    @Test
    fun defaultPageWithNothingStored() {
        assertEquals(0, WidgetPaging.currentPage(WidgetPageState(), pages, now))
    }

    @Test
    fun storedPageIsShown() {
        assertEquals(2, WidgetPaging.currentPage(state(on = 2, tappedSecondsAgo = 60), pages, now))
    }

    @Test
    fun backToDefaultAfterThirtyMinutesWithoutATap() {
        assertEquals(2, WidgetPaging.currentPage(state(2, 29 * 60), pages, now))
        assertEquals(0, WidgetPaging.currentPage(state(2, 30 * 60), pages, now))
        assertEquals(0, WidgetPaging.currentPage(state(2, 3 * 3600), pages, now))
    }

    @Test
    fun resetIsThirtyMinutesAfterTheTap() {
        assertEquals(now.plus(Duration.ofMinutes(25)), WidgetPaging.resetAt(state(2, 5 * 60), pages, now))
        assertNull(WidgetPaging.resetAt(WidgetPageState(), pages, now))
    }

    @Test
    fun removedFavouriteGoesBackToDefault() {
        val paged = state(2, 60)
        val afterRemoval = WidgetPaging.pageIds(10, listOf(1, 3))
        assertEquals(0, WidgetPaging.currentPage(paged, afterRemoval, now))
        assertNull(WidgetPaging.resetAt(paged, afterRemoval, now))
    }

    @Test
    fun reorderedFavouritesKeepTheStationShown() {
        val reordered = WidgetPaging.pageIds(10, listOf(3, 2, 1))
        assertEquals(2, reordered[WidgetPaging.currentPage(state(2, 60), reordered, now)])
    }

    // Refreshes

    @Test
    fun refreshGoesBackToDefaultAndKeepsTheIndex() {
        val paged = state(2, 60).copy(index = AirIndexType.PM25.key)
        val refreshed = WidgetPaging.refreshed(paged, hasNewData = true, now = now)
        assertNull(refreshed.stationId)
        assertEquals(now, refreshed.refreshedAt)
        assertEquals("pm25", refreshed.index)
        assertEquals(0, WidgetPaging.currentPage(refreshed, pages, now))
    }

    @Test
    fun refreshWithoutNewDataKeepsThePage() {
        // Offline or a failed request: the same saved readings, so the page stays.
        val refreshed = WidgetPaging.refreshed(state(2, 60), hasNewData = false, now = now)
        assertEquals(2, refreshed.stationId)
        assertEquals(now, refreshed.refreshedAt)
        assertEquals(2, WidgetPaging.currentPage(refreshed, pages, now))
    }

    @Test
    fun refreshClearsAnExpiredPageEvenOffline() {
        val refreshed = WidgetPaging.refreshed(state(2, 50 * 60), hasNewData = false, now = now)
        assertNull(refreshed.stationId)
        assertNull(WidgetPaging.resetAt(refreshed, pages, now))
    }

    @Test
    fun offlineRefreshStillPlansTheReturn() {
        val refreshed = WidgetPaging.refreshed(state(2, 20 * 60), hasNewData = false, now = now)
        assertEquals(now.plus(Duration.ofMinutes(10)), WidgetPaging.resetAt(refreshed, pages, now))
    }

    @Test
    fun tapDuringTheFetchIsKept() {
        val before = state(null, 40 * 60)
        val tapped = WidgetPaging.paged(before, 3, now.plusSeconds(2))
        for (hasNewData in listOf(true, false)) {
            val saved = WidgetPaging.afterFetch(tapped, before, hasNewData, now)
            assertEquals(3, saved.stationId)
            assertEquals(tapped.tappedAt, saved.tappedAt)
            assertEquals(now, saved.refreshedAt)
            assertEquals(3, WidgetPaging.currentPage(saved, pages, now))
        }
    }

    @Test
    fun noTapDuringTheFetchIsARefresh() {
        val before = state(2, 60)
        val saved = WidgetPaging.afterFetch(before, before, hasNewData = true, now = now)
        assertEquals(WidgetPaging.refreshed(before, hasNewData = true, now = now), saved)
        assertNull(saved.stationId)
    }

    // Index cycle

    @Test
    fun indexCycleOrder() {
        var index = AirIndexType.AQI
        val seen = mutableListOf<AirIndexType>()
        repeat(7) {
            index = WidgetPaging.nextIndex(index)
            seen += index
        }
        assertEquals(
            listOf(
                AirIndexType.PM25,
                AirIndexType.PM10,
                AirIndexType.O3,
                AirIndexType.CO,
                AirIndexType.SO2,
                AirIndexType.NO2,
                AirIndexType.AQI
            ),
            seen
        )
    }

    @Test
    fun configuredIndexIsTheStartingValue() {
        assertEquals(AirIndexType.O3, WidgetPaging.index(WidgetPageState(), AirIndexType.O3))
        val cycled = WidgetPaging.cycled(WidgetPageState(), AirIndexType.NO2, now)
        assertEquals(AirIndexType.NO2, WidgetPaging.index(cycled, AirIndexType.O3))
        assertEquals(now, cycled.tappedAt)
        assertEquals(AirIndexType.CO, WidgetPaging.index(WidgetPageState(index = "bogus"), AirIndexType.CO))
    }

    @Test
    fun indexTapKeepsThePage() {
        val cycled = WidgetPaging.cycled(state(3, 20 * 60), AirIndexType.PM10, now)
        assertEquals(3, WidgetPaging.currentPage(cycled, pages, now))
    }

    @Test
    fun indexTapDoesNotReviveAnExpiredPage() {
        val cycled = WidgetPaging.cycled(state(2, 50 * 60), AirIndexType.PM25, now)
        assertNull(cycled.stationId)
        assertEquals(0, WidgetPaging.currentPage(cycled, pages, now))
        assertEquals("pm25", cycled.index)
    }
}
