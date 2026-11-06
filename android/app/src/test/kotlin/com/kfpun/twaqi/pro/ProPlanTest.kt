package com.kfpun.twaqi.pro

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ProPlanTest {
    @Test
    fun plansKeepTheIosAnalyticsNamesAndOrder() {
        assertEquals(listOf("1m", "6m", "12m", "lifetime"), ProPlan.entries.map { it.analyticsName })
        assertEquals(listOf(ProPlan.TWELVE_MONTHS), ProPlan.entries.filter { it.isBestValue })
    }

    @Test
    fun lifetimeIsTheIosOneTimeProduct() {
        assertEquals("com.kfpun.twaqi.adfree", ProProducts.LIFETIME_ID)
        assertEquals(ProProducts.LIFETIME_ID, ProPlan.LIFETIME.productId)
        assertNull(ProPlan.LIFETIME.basePlanId)
        assertNull(ProPlan.LIFETIME.months)
        assertEquals(
            setOf("com.kfpun.twaqi.subscription.adfree", "com.kfpun.twaqi.adfree"),
            ProProducts.productIds
        )
        assertEquals(listOf(ProPlan.LIFETIME), ProPlan.entries.filter { it.isLifetime })
    }

    @Test
    fun basePlansMapToPlans() {
        assertEquals(ProPlan.SIX_MONTHS, ProPlan.forBasePlan("adfree-6m"))
        assertNull(ProPlan.forBasePlan("adfree-2y"))
        // Lifetime has no base plan, so none maps to it.
        assertNull(ProPlan.forBasePlan(null))
    }

    // Product ordering: subscriptions shortest first, then lifetime (iOS `IAPManager.products()`).

    @Test
    fun offersAreShownInIosOrder() {
        val shuffled = listOf(ProPlan.LIFETIME, ProPlan.TWELVE_MONTHS, ProPlan.ONE_MONTH, ProPlan.SIX_MONTHS)
            .map { FakeBillingGateway.offer(it) }
        assertEquals(ProPlan.entries, shuffled.inDisplayOrder().map { it.plan })
    }

    @Test
    fun lifetimeIsListedAfterTheSubscriptions() {
        val merged = mergeOffers(
            subscriptions = OffersResult(BillingStatus.OK, subscriptionOffers.reversed()),
            lifetime = OffersResult(BillingStatus.OK, listOf(FakeBillingGateway.offer(ProPlan.LIFETIME)))
        )
        assertEquals(BillingStatus.OK, merged.status)
        assertEquals(ProPlan.entries, merged.offers.map { it.plan })
    }

    @Test
    fun lifetimeNotYetInPlayHidesItsRowWithoutAnError() {
        // Play lists no INAPP product until it's created in Play Console.
        val missing = mergeOffers(OffersResult(BillingStatus.OK, subscriptionOffers), OffersResult(BillingStatus.OK))
        assertEquals(OffersResult(BillingStatus.OK, subscriptionOffers), missing)

        val failed = mergeOffers(OffersResult(BillingStatus.OK, subscriptionOffers), OffersResult(BillingStatus.ERROR))
        assertEquals(OffersResult(BillingStatus.OK, subscriptionOffers), failed)
    }

    @Test
    fun failedSubscriptionsFailTheReadEvenWhenLifetimeLoads() {
        // Otherwise the screen would show lifetime alone, with no plans and no retry.
        val lifetimeOnly = mergeOffers(
            OffersResult(BillingStatus.UNAVAILABLE),
            OffersResult(BillingStatus.OK, listOf(FakeBillingGateway.offer(ProPlan.LIFETIME)))
        )
        assertEquals(OffersResult(BillingStatus.UNAVAILABLE), lifetimeOnly)

        val neither = mergeOffers(OffersResult(BillingStatus.UNAVAILABLE), OffersResult(BillingStatus.ERROR))
        assertEquals(OffersResult(BillingStatus.UNAVAILABLE), neither)
    }

    // Restore reads both product types.

    @Test
    fun purchasesOfBothTypesAreRead() {
        val subscription = FakeBillingGateway.purchase(ProPlan.ONE_MONTH)
        val lifetime = FakeBillingGateway.purchase(ProPlan.LIFETIME)
        assertEquals(
            PurchasesResult(BillingStatus.OK, listOf(subscription, lifetime)),
            mergePurchases(
                PurchasesResult(BillingStatus.OK, listOf(subscription)),
                PurchasesResult(BillingStatus.OK, listOf(lifetime))
            )
        )
    }

    @Test
    fun eitherTypeFailingFailsTheRead() {
        // Otherwise a lifetime buyer would turn free when only the subscriptions came back.
        val subscription = FakeBillingGateway.purchase(ProPlan.ONE_MONTH)
        assertEquals(
            PurchasesResult(BillingStatus.UNAVAILABLE),
            mergePurchases(
                PurchasesResult(BillingStatus.OK, listOf(subscription)),
                PurchasesResult(BillingStatus.UNAVAILABLE)
            )
        )
        assertEquals(
            PurchasesResult(BillingStatus.ERROR),
            mergePurchases(PurchasesResult(BillingStatus.ERROR), PurchasesResult(BillingStatus.OK))
        )
    }

    @Test
    fun purchasesKnowTheirType() {
        val lifetime = FakeBillingGateway.purchase(ProPlan.LIFETIME)
        val subscription = FakeBillingGateway.purchase(ProPlan.SIX_MONTHS)
        assertTrue(lifetime.isPro && lifetime.isLifetime && !lifetime.isSubscription)
        assertTrue(subscription.isPro && subscription.isSubscription && !subscription.isLifetime)
    }

    private val subscriptionOffers = ProPlan.entries.filterNot { it.isLifetime }.map { FakeBillingGateway.offer(it) }

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
