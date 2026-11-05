package com.kfpun.twaqi.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `TrackingManager` and `AnalyticsTests` (DebugView). */
class TrackingManagerTest {
    private val preferences = object : TrackingPreferences {
        override var isExcluded = false
    }
    private val switches = mutableListOf<Boolean>()

    private fun manager(debug: Boolean) = TrackingManager(preferences, { switches += it }, isDebugBuild = debug)

    @Test
    fun releaseBuildReportsUntilOptedOut() {
        val manager = manager(debug = false)

        manager.applyAtLaunch()

        assertTrue(manager.isReporting)
        assertEquals(listOf(true), switches)
    }

    @Test
    fun toggleSavesTheOptOutAndStopsCollectionAtOnce() {
        val manager = manager(debug = false)
        manager.applyAtLaunch()

        assertTrue(manager.toggleExcluded())

        assertTrue(preferences.isExcluded)
        assertFalse(manager.isReporting)
        assertEquals(listOf(true, false), switches)

        assertFalse(manager.toggleExcluded())

        assertFalse(preferences.isExcluded)
        assertTrue(manager.isReporting)
        assertEquals(listOf(true, false, true), switches)
    }

    @Test
    fun optOutHoldsOnTheNextLaunch() {
        manager(debug = false).setExcluded(true)
        switches.clear()

        val next = manager(debug = false)
        next.applyAtLaunch()

        assertTrue(next.isExcluded)
        assertFalse(next.isReporting)
        assertEquals(listOf(false), switches)
    }

    @Test
    fun debugBuildNeverReports() {
        val manager = manager(debug = true)

        manager.applyAtLaunch()
        assertFalse(manager.isReporting)

        manager.toggleExcluded()
        manager.toggleExcluded()

        assertFalse(manager.isReporting)
        assertTrue(switches.none { it })
    }

    @Test
    fun debugViewNeedsADebugBuildAndNoOptOut() {
        assertFalse(manager(debug = false).enableDebugView())

        val debug = manager(debug = true)
        assertTrue(debug.enableDebugView())
        assertTrue(debug.isReporting)

        // Opting out turns DebugView off too, and it can't come back on.
        debug.setExcluded(true)
        assertFalse(debug.isReporting)
        assertFalse(debug.enableDebugView())
    }

    @Test
    fun everySeventhTapOnTheVersionRowToggles() {
        val counter = VersionTapCounter()

        val toggles = (1..14).map { counter.tap() }

        assertEquals(listOf(7, 14), toggles.withIndex().filter { it.value }.map { it.index + 1 })
    }
}
