package com.kfpun.twaqi.ui.main

import androidx.window.core.layout.WindowSizeClass
import com.kfpun.twaqi.data.model.Country
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MapLayoutTest {
    @Test
    fun firstLaunchOpensOnTheMapHome() {
        assertEquals(MapTarget(23.49, 120.96, 7.9f), MapHome.initialCamera(0.0, 0.0, 0f))
        assertEquals(MapTarget(25.0, 121.5, 11f), MapHome.initialCamera(25.0, 121.5, 11f))
        assertEquals(MapTarget(25.0, 121.5, 7.9f), MapHome.initialCamera(25.0, 121.5, 0f))
    }

    @Test
    fun defaultLocationPrefersTheApisSupportedCountry() {
        assertEquals(MapHome.target, MapHome.defaultLocation(emptyList()))
        val taiwan = Country(Country.SUPPORTED_ID, "twn", 23.7, 121.0, 7.5f, "Taiwan", "臺灣")
        val japan = Country(4, "jpn", 36.2, 138.2, 5f, "Japan", "日本")
        assertEquals(MapTarget(23.7, 121.0, 7.5f), MapHome.defaultLocation(listOf(japan, taiwan)))
        assertEquals(MapTarget(23.7, 121.0, 7.9f), MapHome.defaultLocation(listOf(taiwan.copy(zoom = 0f))))
        // A placeholder row for the supported country falls back to the constants.
        assertEquals(MapHome.target, MapHome.defaultLocation(listOf(taiwan.copy(lat = 0.0, lon = 0.0))))
    }

    @Test
    fun foldSplitsOnlyWithRoomOnBothSides() {
        assertNull(FoldLine.leadingWidth(null, 0f, 900f))
        assertEquals(450f, FoldLine.leadingWidth(450f, 0f, 900f))
        assertEquals(370f, FoldLine.leadingWidth(450f, 80f, 820f))
        assertNull(FoldLine.leadingWidth(300f, 0f, 900f))
        assertNull(FoldLine.leadingWidth(600f, 0f, 900f))
    }

    @Test
    fun wideWindowsShowTheStationBesideTheMap() {
        assertFalse(WideLayout.isWide(411f, 891f))
        assertFalse(WideLayout.isWide(891f, 411f))
        assertTrue(WideLayout.isWide(800f, 1280f))
        assertTrue(WideLayout.isWide(1280f, 800f))
    }

    /** FOX-119: the same answer from the window size class, the way the app asks. */
    @Test
    fun wideFollowsTheWindowSizeClass() {
        fun wide(width: Float, height: Float) = WideLayout.isWide(WindowSizeClass.compute(width, height))
        // Phones, portrait and landscape.
        assertFalse(wide(411f, 891f))
        assertFalse(wide(891f, 411f))
        // A flip phone's cover screen (720 x 748 px at 306 dpi).
        assertFalse(wide(376f, 391f))
        // A folded Fold's outer screen.
        assertFalse(wide(412f, 914f))
        // Tablets, portrait and landscape, and an unfolded Fold.
        assertTrue(wide(800f, 1280f))
        assertTrue(wide(1280f, 800f))
        assertTrue(wide(841f, 701f))
        // A small tablet in portrait is medium width too.
        assertTrue(wide(600f, 960f))
        assertFalse(wide(599f, 960f))
    }

    @Test
    fun panelTakesTwoFifthsOrStartsOnTheFold() {
        assertEquals(320f, WideLayout.panelWidth(700f))
        assertEquals(400f, WideLayout.panelWidth(1000f))
        assertEquals(440f, WideLayout.panelWidth(1280f))
        // An unfolded foldable: the map and the station each get a half.
        assertEquals(442f, WideLayout.panelWidth(884f, foldX = 442f))
        // The fold too close to an edge: the usual width.
        assertEquals(400f, WideLayout.panelWidth(1000f, foldX = 900f))
    }

    /** FOX-112: the wind button leaves the legend's corner when it would cover it. */
    @Test
    fun windButtonMovesRightOnlyWhenItWouldCoverTheLegend() {
        // Portrait: legend ends at 480 px, the button row at 2000 px: plenty of room.
        assertFalse(MapButtonsLayout.windBesideLocationButtons(480f, 2000f, 158f, 32f))
        // Landscape: legend ends at 440 px, the row at 560 px: a 158 px button would reach 370.
        assertTrue(MapButtonsLayout.windBesideLocationButtons(440f, 560f, 158f, 32f))
        // Exactly touching the gap still fits.
        assertFalse(MapButtonsLayout.windBesideLocationButtons(400f, 590f, 158f, 32f))
        // Before the first layout nothing is measured: it stays where iOS has it.
        assertFalse(MapButtonsLayout.windBesideLocationButtons(0f, 560f, 158f, 32f))
        assertFalse(MapButtonsLayout.windBesideLocationButtons(440f, 0f, 158f, 32f))
    }
}
