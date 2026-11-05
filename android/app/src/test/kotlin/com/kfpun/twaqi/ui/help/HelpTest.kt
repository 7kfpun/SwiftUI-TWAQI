package com.kfpun.twaqi.ui.help

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HelpTest {
    /** iOS `HelpSectionOrderTests` (FOX-68), with the sections Android has so far. */
    @Test
    fun freeUserSeesPremiumFirst() {
        assertEquals(
            listOf(
                HelpSection.PURCHASE,
                HelpSection.LANGUAGE,
                HelpSection.APPEARANCE,
                HelpSection.CONTACT,
                HelpSection.WIDGETS_AND_WATCH,
                HelpSection.DEFINITION,
                HelpSection.ABOUT
            ),
            HelpSection.order(isPro = false)
        )
    }

    @Test
    fun proUserHasNoPremiumSection() {
        val order = HelpSection.order(isPro = true)

        assertFalse(HelpSection.PURCHASE in order)
        assertEquals(HelpSection.LANGUAGE, order.first())
    }

    @Test
    fun routesRoundTrip() {
        val destinations = DefinitionPage.entries.map { HelpDestination.IndexGuide(it) } +
            listOf(HelpDestination.WidgetGuide, HelpDestination.WearOsGuide, HelpDestination.Cooperate)
        destinations.forEach { assertEquals(it, HelpDestination.fromRoute(it.route)) }
        assertNull(HelpDestination.fromRoute("guide/pm1"))
        assertNull(HelpDestination.fromRoute("nowhere"))
    }

    @Test
    fun aqiPageHasNoSourcesOrHealthSection() {
        assertEquals(3, DefinitionPage.AQI.sections.size)
        DefinitionPage.entries.filter { it != DefinitionPage.AQI }.forEach { assertEquals(5, it.sections.size) }
    }

    @Test
    fun everyPageHasSixBandsThatMeet() {
        DefinitionPage.entries.forEach { page ->
            val bands = page.bands
            assertEquals(6, bands.size)
            assertEquals(GuideStatus.entries, bands.map { it.status })
            bands.zipWithNext().forEach { (lower, upper) -> assertEquals(lower.until, upper.from, 0.0) }
        }
    }

    @Test
    fun rangesReadAsAPersonWouldSayThem() {
        val aqi = DefinitionPage.AQI.bands
        assertEquals("0–50", DefinitionPage.AQI.rangeText(aqi[0], isLast = false))
        assertEquals("51–100", DefinitionPage.AQI.rangeText(aqi[1], isLast = false))
        assertEquals("301+", DefinitionPage.AQI.rangeText(aqi[5], isLast = true))

        val pm25 = DefinitionPage.PM25.bands
        assertEquals("0.0–15.4 μg/m3", DefinitionPage.PM25.rangeText(pm25[0], isLast = false))
        assertEquals("15.5–35.4 μg/m3", DefinitionPage.PM25.rangeText(pm25[1], isLast = false))
        assertEquals("250.5+ μg/m3", DefinitionPage.PM25.rangeText(pm25[5], isLast = true))

        val co = DefinitionPage.CO.bands
        assertEquals("4.5–9.4 ppm", DefinitionPage.CO.rangeText(co[1], isLast = false))
        assertEquals("55–124 ppb", DefinitionPage.O3.rangeText(DefinitionPage.O3.bands[1], isLast = false))
    }

    @Test
    fun wikipediaInTheReadersLanguage() {
        assertEquals("https://en.wikipedia.org/wiki/Air_quality_index", DefinitionPage.AQI.url(chinese = false))
        val chinese = DefinitionPage.PM25.url(chinese = true)
        assertTrue(chinese.startsWith("https://zh.wikipedia.org/wiki/%E7%B4%B0"))
        assertEquals(java.net.URLDecoder.decode(chinese.substringAfterLast('/'), "UTF-8"), "細懸浮微粒")
    }

    @Test
    fun legalPagesOnThePublicSite() {
        assertEquals("https://taiwanair.wahthefox.com/privacy.html", LegalPage.PRIVACY.url(chinese = false))
        assertEquals("https://taiwanair.wahthefox.com/zh-Hant/terms.html", LegalPage.TERMS.url(chinese = true))
    }
}
