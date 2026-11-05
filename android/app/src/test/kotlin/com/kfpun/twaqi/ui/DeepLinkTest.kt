package com.kfpun.twaqi.ui

import com.kfpun.twaqi.pro.ProScreenSource
import com.kfpun.twaqi.ui.navigation.DeepLink
import com.kfpun.twaqi.ui.navigation.StationLinkSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** FOX-59: the one deep-link router (iOS `DeepLinkTests`). */
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
}
