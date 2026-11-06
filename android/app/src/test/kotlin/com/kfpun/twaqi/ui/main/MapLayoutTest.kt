package com.kfpun.twaqi.ui.main

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
    fun wideWindowsShowTheListBesideTheMap() {
        assertFalse(WideLayout.isWide(411f, 891f))
        assertFalse(WideLayout.isWide(891f, 411f))
        assertTrue(WideLayout.isWide(800f, 1280f))
        assertTrue(WideLayout.isWide(1280f, 800f))
    }

    @Test
    fun listTakesTwoFifthsOrEndsOnTheFold() {
        assertEquals(320f, WideLayout.listWidth(700f))
        assertEquals(400f, WideLayout.listWidth(1000f))
        assertEquals(440f, WideLayout.listWidth(1280f))
        assertEquals(442f, WideLayout.listWidth(884f, foldX = 442f))
    }
}
