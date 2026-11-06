package com.kfpun.twaqi.pro

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ProPlanTest {
    @Test
    fun plansKeepTheIosAnalyticsNamesAndOrder() {
        assertEquals(listOf("1m", "6m", "12m"), ProPlan.entries.map { it.analyticsName })
        assertEquals(listOf(ProPlan.TWELVE_MONTHS), ProPlan.entries.filter { it.isBestValue })
    }

    @Test
    fun basePlansMapToPlans() {
        assertEquals(ProPlan.SIX_MONTHS, ProPlan.forBasePlan("adfree-6m"))
        assertNull(ProPlan.forBasePlan("adfree-2y"))
        assertNull(ProPlan.forBasePlan(null))
    }

    @Test
    fun sourcesUseTheIosNames() {
        assertEquals(ProScreenSource.HELP_ROW, ProScreenSource.fromAnalyticsName("help_row"))
        assertEquals(ProScreenSource.WIDGET_LOCKED, ProScreenSource.fromAnalyticsName("widget_locked"))
        assertEquals(ProScreenSource.DEEP_LINK, ProScreenSource.fromAnalyticsName("nope"))
        assertEquals(ProScreenSource.DEEP_LINK, ProScreenSource.fromAnalyticsName(null))
    }

    @Test
    fun proLinksAreRecognised() {
        assertEquals(ProScreenSource.WIDGET_LOCKED, ProDeepLink.source("twaqi", "pro", "", "widget_locked"))
        assertEquals(ProScreenSource.DEEP_LINK, ProDeepLink.source("TWAQI", "pro", "/", null))
        assertNull(ProDeepLink.source("twaqi", "station", "", null))
        assertNull(ProDeepLink.source("https", "pro", "", null))
        assertNull(ProDeepLink.source("twaqi", "pro", "/extra", null))
    }

    @Test
    fun longerPlansShowTheirMonthlyPrice() {
        assertEquals("$2.00", ProPricing.perMonth(23_990_000, 12, "USD", Locale.US))
        assertEquals("$1.50", ProPricing.perMonth(8_990_000, 6, "USD", Locale.US))
        // Currencies without minor units show none.
        val yen = ProPricing.perMonth(1_200_000_000, 12, "JPY", Locale.JAPAN)
        assertEquals("100", yen.filter { it.isDigit() || it == '.' })
    }

    @Test
    fun legalPagesFollowTheLanguage() {
        assertEquals("https://taiwanair.wahthefox.com/terms.html", legalUrl("terms.html", Locale.ENGLISH))
        assertEquals(
            "https://taiwanair.wahthefox.com/zh-Hant/privacy.html",
            legalUrl("privacy.html", Locale.TRADITIONAL_CHINESE)
        )
    }
}
