package com.kfpun.twaqi.ui

import com.kfpun.twaqi.pro.ProScreenSource
import com.kfpun.twaqi.ui.navigation.DeepLink
import com.kfpun.twaqi.ui.navigation.StationLinkSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** FOX-59, FOX-95: the one deep-link router (iOS `DeepLinkTests`). */
class DeepLinkTest {
    private fun parse(uri: String): DeepLink? {
        val scheme = uri.substringBefore("://")
        val rest = uri.substringAfter("://")
        val hostAndPath = rest.substringBefore('?')
        val host = hostAndPath.substringBefore('/')
        val path = hostAndPath.removePrefix(host)
        val query = rest.substringAfter('?', "").split('&').filter { it.contains('=') }
            .associate { it.substringBefore('=') to it.substringAfter('=') }
        return DeepLink.parse(scheme, host, path, query::get)
    }

    @Test
    fun stationLinksRoundTrip() {
        val uri = DeepLink.stationUri(126, StationLinkSource.WIDGET)
        assertEquals("twaqi://station?id=126&source=widget", uri)
        assertEquals(DeepLink.Station(126, StationLinkSource.WIDGET), parse(uri))
    }

    @Test
    fun unknownSourcesAreDeepLinks() {
        assertEquals(DeepLink.Station(5, StationLinkSource.DEEP_LINK), parse("twaqi://station?id=5"))
        assertEquals(DeepLink.Station(5, StationLinkSource.DEEP_LINK), parse("twaqi://station?id=5&source=nope"))
    }

    @Test
    fun proLinksGoThroughTheProRouter() {
        assertEquals(DeepLink.Pro(ProScreenSource.WIDGET_LOCKED), parse("twaqi://pro?source=widget_locked"))
    }

    @Test
    fun theLockedWidgetsProLinkRoundTrips() {
        val uri = DeepLink.proUri(ProScreenSource.WIDGET_LOCKED)
        assertEquals("twaqi://pro?source=widget_locked", uri)
        assertEquals(DeepLink.Pro(ProScreenSource.WIDGET_LOCKED), parse(uri))
    }

    @Test
    fun anythingElseIsIgnored() {
        listOf(
            "https://station?id=5",
            "twaqi://station",
            "twaqi://station?id=abc",
            "twaqi://station?id=0",
            "twaqi://station/extra?id=5",
            "twaqi://elsewhere?id=5"
        ).forEach { assertNull(it, parse(it)) }
    }

    @Test
    fun routeIgnoresProForProUsersAndUnknownStations() {
        val pro = DeepLink.Pro(ProScreenSource.WIDGET_LOCKED)
        assertEquals(pro, DeepLink.route(pro, isPro = false) { true })
        assertNull(DeepLink.route(pro, isPro = true) { true })

        val station = DeepLink.Station(999_999, StationLinkSource.DEEP_LINK)
        assertNull(DeepLink.route(station, isPro = false) { false })
        assertEquals(station, DeepLink.route(station, isPro = false) { it == 999_999 })
        assertNull(DeepLink.route(null, isPro = false) { true })
    }

    // FOX-95: launcher shortcuts, Assistant and the Quick Settings tile.

    @Test
    fun shortcutAndTileStationLinksRoundTrip() {
        assertEquals("twaqi://station?id=12&source=shortcut", DeepLink.stationUri(12, StationLinkSource.SHORTCUT))
        assertEquals(DeepLink.Station(12, StationLinkSource.SHORTCUT), parse("twaqi://station?id=12&source=shortcut"))
        assertEquals(
            DeepLink.Station(12, StationLinkSource.TILE),
            parse(DeepLink.stationUri(12, StationLinkSource.TILE))
        )
    }

    @Test
    fun airQualityLinksRoundTrip() {
        assertEquals("twaqi://air-quality", DeepLink.airQualityUri())
        assertEquals(DeepLink.AirQuality(null), parse(DeepLink.airQualityUri()))
        assertEquals("twaqi://air-quality?id=12", DeepLink.airQualityUri(12))
        assertEquals(DeepLink.AirQuality(12), parse(DeepLink.airQualityUri(12)))
        assertEquals(DeepLink.AirQuality(null), parse("TWAQI://Air-Quality/"))
        assertEquals(DeepLink.AirQuality(null), parse("twaqi://air-quality?source=shortcut"))
    }

    @Test
    fun badAirQualityLinksAreIgnored() {
        listOf(
            "twaqi://air-quality?id=abc",
            "twaqi://air-quality?id=0",
            "twaqi://air-quality?id=-3",
            "twaqi://air-quality/extra",
            "https://air-quality"
        ).forEach { assertNull(it, parse(it)) }
    }

    @Test
    fun routeAnswersAirQualityForNearestOrAKnownStation() {
        val nearest = DeepLink.AirQuality(null)
        assertEquals(nearest, DeepLink.route(nearest, isPro = true) { false })
        val station = DeepLink.AirQuality(12)
        assertEquals(station, DeepLink.route(station, isPro = false) { it == 12 })
        assertNull(DeepLink.route(station, isPro = false) { false })
    }
}
