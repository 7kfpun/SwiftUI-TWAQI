package com.kfpun.twaqi

import com.kfpun.twaqi.ui.navigation.DeepLink
import com.kfpun.twaqi.ui.navigation.StationLinkSource
import java.io.File
import java.net.URI
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

/**
 * FOX-115: every twaqi:// link opened from outside the app stacked one more MainActivity. It is
 * `singleTask` now, so the one in the app's task takes each link in `onNewIntent` and routes it
 * through [DeepLink], like the widgets, the tile, alerts, shortcuts and App Actions.
 */
class MainActivityLaunchTest {
    private val manifest = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
        .newDocumentBuilder().parse(File("src/main/AndroidManifest.xml"))

    private fun activity(name: String): Element = manifest.getElementsByTagName("activity").let { nodes ->
        (0 until nodes.length).map { nodes.item(it) as Element }.single { it.getAttributeNS(ANDROID, "name") == name }
    }

    @Test
    fun mainActivityIsOneInstanceInTheAppsTask() {
        val main = activity(".MainActivity")
        assertEquals("singleTask", main.getAttributeNS(ANDROID, "launchMode"))
        // The default affinity (the package), so links from other apps join the app's own task.
        assertEquals("", main.getAttributeNS(ANDROID, "taskAffinity"))
        // The answer card keeps its own empty affinity: it floats over whatever was open.
        assertTrue(activity(".shortcuts.AirQualityAnswerActivity").hasAttributeNS(ANDROID, "taskAffinity"))
    }

    @Test
    fun mainActivityTakesStationLinks() {
        val filters = activity(".MainActivity").getElementsByTagName("data")
        val hosts = (0 until filters.length).map { filters.item(it) as Element }
            .map { it.getAttributeNS(ANDROID, "scheme") to it.getAttributeNS(ANDROID, "host") }
        assertEquals(listOf(DeepLink.SCHEME to DeepLink.STATION_HOST), hosts)
    }

    /** The links from the ticket's adb repro, as `onNewIntent` routes them with stations 105 and 126 known. */
    @Test
    fun externalLinksRouteToTheirStationAndAnUnknownIdChangesNothing() {
        val known = setOf(105, 126)
        fun route(uri: String) = DeepLink.route(parse(uri), isPro = false) { it in known }

        assertEquals(DeepLink.Station(105, StationLinkSource.WIDGET), route("twaqi://station?id=105&source=widget"))
        assertEquals(DeepLink.Station(126, StationLinkSource.DEEP_LINK), route("twaqi://station?id=126"))
        // Ignored: the station page that was open stays, and no screen is added.
        assertNull(route("twaqi://station?id=999999"))
        assertNull(route("twaqi://station?id=abc"))
    }

    /** What the app builds for its widgets, shortcuts and tile parses back to the same station. */
    @Test
    fun theAppsOwnLinksRouteTheSameWay() {
        StationLinkSource.entries.forEach { source ->
            val link = parse(DeepLink.stationUri(126, source))
            assertEquals(DeepLink.Station(126, source), DeepLink.route(link, isPro = false) { it == 126 })
        }
    }

    private fun parse(uri: String): DeepLink? {
        val parsed = URI(uri)
        val query = parsed.rawQuery.orEmpty().split('&').filter { '=' in it }
            .associate { it.substringBefore('=') to it.substringAfter('=') }
        return DeepLink.parse(parsed.scheme, parsed.host, parsed.path, query::get)
    }

    private companion object {
        const val ANDROID = "http://schemas.android.com/apk/res/android"
    }
}
