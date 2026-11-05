package com.kfpun.twaqi.shortcuts

import org.junit.Assert.assertEquals
import org.junit.Test

/** FOX-95: which stations get a launcher shortcut, in which order, within the launcher's limit. */
class StationShortcutPlanTest {
    @Test
    fun favouritesComeFirstInTheReadersOrderThenRecentsNewestFirst() {
        assertEquals(listOf(5, 3, 9), StationShortcutPlan.stationIds(listOf(5, 3), listOf(9, 3, 5), limit = 4))
        assertEquals(listOf(5, 9, 8), StationShortcutPlan.stationIds(listOf(5), listOf(9, 8, 7), limit = 3))
    }

    @Test
    fun theListIsCapped() {
        assertEquals(
            listOf(1, 2, 3, 4),
            StationShortcutPlan.stationIds(listOf(1, 2, 3, 4, 5, 6), emptyList(), limit = 4)
        )
        assertEquals(emptyList<Int>(), StationShortcutPlan.stationIds(listOf(1), listOf(2), limit = 0))
    }

    @Test
    fun theLastSlotGoesToTheNewestRecentWhenFavouritesWouldFillIt() {
        assertEquals(listOf(1, 2, 3, 9), StationShortcutPlan.stationIds(listOf(1, 2, 3, 4, 5), listOf(9, 8), limit = 4))
        // A recent station that is a favourite takes no extra slot.
        assertEquals(listOf(1, 2, 3, 4), StationShortcutPlan.stationIds(listOf(1, 2, 3, 4, 5), listOf(2), limit = 4))
        // With one slot, it is the first favourite's.
        assertEquals(listOf(1), StationShortcutPlan.stationIds(listOf(1, 2), listOf(9), limit = 1))
    }

    @Test
    fun repeatsAndBadIdsAreDropped() {
        assertEquals(listOf(4, 7), StationShortcutPlan.stationIds(listOf(4, 4, 0, -1), listOf(7, 7, 4), limit = 4))
    }

    @Test
    fun withNoFavouritesRecentsFillTheList() {
        assertEquals(listOf(9, 8, 7, 6), StationShortcutPlan.stationIds(emptyList(), listOf(9, 8, 7, 6, 5), limit = 4))
    }

    @Test
    fun theLimitLeavesRoomForTheAirQualityShortcutAndNeverPassesFour() {
        assertEquals(4, StationShortcutPlan.limit(launcherMax = 15))
        assertEquals(4, StationShortcutPlan.limit(launcherMax = 5))
        assertEquals(3, StationShortcutPlan.limit(launcherMax = 4))
        assertEquals(0, StationShortcutPlan.limit(launcherMax = 1))
        assertEquals(0, StationShortcutPlan.limit(launcherMax = 0))
    }

    @Test
    fun recentStationsMoveToTheFrontAndAreCapped() {
        assertEquals(listOf(3, 1, 2), RecentStations.record(listOf(1, 2, 3), 3))
        assertEquals(listOf(6, 1, 2, 3, 4), RecentStations.record(listOf(1, 2, 3, 4, 5), 6))
        assertEquals(listOf(7), RecentStations.record(emptyList(), 7))
    }

    @Test
    fun shortcutIdsAreStablePerStation() {
        assertEquals("station_126", StationShortcutPlan.shortcutId(126))
    }
}
