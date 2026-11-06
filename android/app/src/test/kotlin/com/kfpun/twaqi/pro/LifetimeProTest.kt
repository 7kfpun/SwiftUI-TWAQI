package com.kfpun.twaqi.pro

import android.app.Activity
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Lifetime Pro (FOX-123): Pro is an active subscription or an owned, acknowledged
 * lifetime purchase, as on iOS (`IAPManager.isEntitled`).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class LifetimeProTest {
    private val play = FakeBillingGateway()
    private val store = InMemoryEntitlementStore()

    private fun TestScope.repository(): ProRepository = ProRepository(play, store, backgroundScope).also {
        runCurrent()
    }

    private val subscription = FakeBillingGateway.purchase(ProPlan.SIX_MONTHS, acknowledged = true)
    private val lifetime = FakeBillingGateway.purchase(ProPlan.LIFETIME, acknowledged = true)

    // The truth table

    @Test
    fun subscriptionOnlyIsPro() = runTest {
        play.purchases += subscription
        assertEquals(Entitlement.PRO, repository().refresh())
    }

    @Test
    fun lifetimeOnlyIsPro() = runTest {
        play.purchases += lifetime
        assertEquals(Entitlement.PRO, repository().refresh())
        assertEquals(Entitlement.PRO, store.saved)
    }

    @Test
    fun subscriptionAndLifetimeIsPro() = runTest {
        play.purchases += listOf(subscription, lifetime)
        assertEquals(Entitlement.PRO, repository().refresh())
    }

    @Test
    fun neitherIsFree() = runTest {
        store.saved = Entitlement.PRO
        assertEquals(Entitlement.FREE, repository().refresh())
        assertEquals(Entitlement.FREE, store.saved)
    }

    @Test
    fun pendingLifetimeIsPendingAndNotAcknowledged() = runTest {
        play.purchases += FakeBillingGateway.purchase(ProPlan.LIFETIME, OwnedPurchase.State.PENDING)
        assertEquals(Entitlement.PENDING, repository().refresh())
        assertTrue(play.acknowledgedTokens.isEmpty())
    }

    @Test
    fun pendingSubscriptionBesideOwnedLifetimeIsPro() = runTest {
        play.purchases += FakeBillingGateway.purchase(ProPlan.ONE_MONTH, OwnedPurchase.State.PENDING)
        play.purchases += lifetime
        assertEquals(Entitlement.PRO, repository().refresh())
    }

    @Test
    fun refundedLifetimeTurnsProOffOnTheNextQuery() = runTest {
        play.purchases += lifetime
        val repository = repository()
        assertEquals(Entitlement.PRO, repository.refresh())

        // Play no longer lists a refunded or voided one-time purchase.
        play.purchases.clear()
        assertEquals(Entitlement.FREE, repository.refresh())
        assertEquals(Entitlement.FREE, store.saved)
    }

    @Test
    fun lapsedSubscriptionLeavesLifetimePro() = runTest {
        play.purchases += listOf(subscription, lifetime)
        val repository = repository()
        repository.refresh()

        play.purchases.remove(subscription)
        assertEquals(Entitlement.PRO, repository.refresh())
    }

    @Test
    fun ownedLifetimeIsAcknowledgedAndThenPro() = runTest {
        val unacknowledged = FakeBillingGateway.purchase(ProPlan.LIFETIME)
        play.purchases += unacknowledged
        assertEquals(Entitlement.PRO, repository().refresh())
        assertEquals(listOf(unacknowledged.purchaseToken), play.acknowledgedTokens)
    }

    @Test
    fun lifetimeThatCantBeAcknowledgedWaitsAndIsRetried() = runTest {
        // Play refunds a one-time purchase left unacknowledged, so it isn't owned yet.
        val unacknowledged = FakeBillingGateway.purchase(ProPlan.LIFETIME)
        play.purchases += unacknowledged
        play.acknowledgeStatus = BillingStatus.ERROR
        val repository = repository()
        assertEquals(Entitlement.PENDING, repository.refresh())

        play.acknowledgeStatus = BillingStatus.OK
        assertEquals(Entitlement.PRO, repository.refresh())
        assertEquals(listOf(unacknowledged.purchaseToken), play.acknowledgedTokens)
    }

    @Test
    fun lifetimeProReachesIsProWhichTheWatchRelayReads() = runTest {
        // ProGraph feeds `isPro` to PhoneStateRelay (FOX-62); nothing else to wire.
        play.purchases += lifetime
        val repository = repository()
        repository.refresh()
        assertTrue(repository.isPro.first())
    }

    // Purchase

    @Test
    fun buyingLifetimeTurnsProOnAndAcknowledges() = runTest {
        val repository = repository()
        val outcome = repository.purchase(FakeBillingGateway.offer(ProPlan.LIFETIME), play.launcher)
        assertEquals(PurchaseOutcome.PURCHASED, outcome)
        assertEquals(Entitlement.PRO, repository.entitlement.value)
        assertEquals(listOf("token-lifetime-PURCHASED"), play.acknowledgedTokens)
    }

    @Test
    fun buyingLifetimeWhileSubscribedDoesntReplaceTheSubscription() = runTest {
        play.purchases += subscription
        val repository = repository()
        repository.refresh()

        repository.purchase(FakeBillingGateway.offer(ProPlan.LIFETIME), play.launcher)
        assertNull(play.launches.single().second)
        assertTrue(subscription in play.purchases)
    }

    @Test
    fun subscribingWhileOwningLifetimeHasNoPlanToSwitch() = runTest {
        play.purchases += lifetime
        val repository = repository()
        repository.refresh()

        repository.purchase(FakeBillingGateway.offer(ProPlan.ONE_MONTH), play.launcher)
        assertNull(play.launches.single().second)
    }

    @Test
    fun switchingSubscriptionPlanIgnoresLifetime() = runTest {
        play.purchases += listOf(lifetime, subscription)
        val repository = repository()
        repository.refresh()

        repository.purchase(FakeBillingGateway.offer(ProPlan.TWELVE_MONTHS), play.launcher)
        assertEquals(subscription.purchaseToken, play.launches.single().second)
    }

    @Test
    fun pendingLifetimePurchaseIsPending() = runTest {
        play.onLaunch = { offer, _ ->
            play.buy(offer.plan, OwnedPurchase.State.PENDING)
            BillingStatus.OK
        }
        val repository = repository()
        assertEquals(
            PurchaseOutcome.PENDING,
            repository.purchase(FakeBillingGateway.offer(ProPlan.LIFETIME), play.launcher)
        )
        assertEquals(Entitlement.PENDING, repository.entitlement.value)
    }

    @Test
    fun acknowledgementIsRetriedOnceAtOnce() = runTest {
        var calls = 0
        val flaky = object : BillingGateway by play {
            override suspend fun acknowledge(purchaseToken: String): BillingStatus =
                if (++calls == 1) BillingStatus.UNAVAILABLE else play.acknowledge(purchaseToken)
        }
        val repository = ProRepository(flaky, store, backgroundScope).also { runCurrent() }
        assertEquals(
            PurchaseOutcome.PURCHASED,
            repository.purchase(FakeBillingGateway.offer(ProPlan.LIFETIME), play.launcher)
        )
        assertEquals(Entitlement.PRO, repository.entitlement.value)
        assertEquals(2, calls)
    }

    @Test
    fun lifetimeBoughtButNotAcknowledgedIsPending() = runTest {
        play.acknowledgeStatus = BillingStatus.ERROR
        val repository = repository()
        assertEquals(
            PurchaseOutcome.PENDING,
            repository.purchase(FakeBillingGateway.offer(ProPlan.LIFETIME), play.launcher)
        )
        assertEquals(Entitlement.PENDING, repository.entitlement.value)
    }

    @Test
    fun lifetimeAlreadyOwnedRestoresInstead() = runTest {
        play.purchases += lifetime
        play.onLaunch = { _, _ -> BillingStatus.ITEM_ALREADY_OWNED }
        val repository = repository()
        assertEquals(
            PurchaseOutcome.PURCHASED,
            repository.purchase(FakeBillingGateway.offer(ProPlan.LIFETIME), play.launcher)
        )
        assertEquals(Entitlement.PRO, repository.entitlement.value)
    }

    // Restore

    @Test
    fun restoreFindsLifetime() = runTest {
        val repository = repository()
        play.purchases += FakeBillingGateway.purchase(ProPlan.LIFETIME)
        assertEquals(RestoreOutcome.RESTORED, repository.restore())
        assertEquals(Entitlement.PRO, repository.entitlement.value)
        assertEquals(listOf("token-lifetime-PURCHASED"), play.acknowledgedTokens)
    }

    @Test
    fun restoreFindsBothTypes() = runTest {
        val repository = repository()
        play.purchases += listOf(
            FakeBillingGateway.purchase(ProPlan.TWELVE_MONTHS),
            FakeBillingGateway.purchase(ProPlan.LIFETIME)
        )
        assertEquals(RestoreOutcome.RESTORED, repository.restore())
        assertEquals(listOf("token-12m-PURCHASED", "token-lifetime-PURCHASED"), play.acknowledgedTokens)
    }

    @Test
    fun restoreOfAPendingLifetime() = runTest {
        play.purchases += FakeBillingGateway.purchase(ProPlan.LIFETIME, OwnedPurchase.State.PENDING)
        assertEquals(RestoreOutcome.PENDING, repository().restore())
    }

    // Demo billing (debug builds, FOX-58)

    @Test
    fun demoBillingSellsLifetimeLastAndUnlocksPro() = runTest {
        val demo = DemoBillingGateway()
        val repository = ProRepository(demo, store, backgroundScope).also { runCurrent() }
        val offers = repository.queryOffers().offers
        assertEquals(ProPlan.entries, offers.map { it.plan })

        val outcome = repository.purchase(offers.last(), demo.launcher(Activity()))
        assertEquals(PurchaseOutcome.PURCHASED, outcome)
        assertEquals(Entitlement.PRO, repository.entitlement.value)
        assertEquals(RestoreOutcome.RESTORED, repository.restore())
    }

    @Test
    fun demoLifetimeIsKeptBesideADemoSubscription() = runTest {
        val demo = DemoBillingGateway()
        val repository = ProRepository(demo, store, backgroundScope).also { runCurrent() }
        val offers = repository.queryOffers().offers
        repository.purchase(offers.last(), demo.launcher(Activity()))
        repository.purchase(offers.first(), demo.launcher(Activity()))
        assertEquals(
            setOf(ProProducts.SUBSCRIPTION_ID, ProProducts.LIFETIME_ID),
            demo.queryPurchases().purchases.flatMap { it.productIds }.toSet()
        )
    }

    // Reading Play's lifetime product (PlayBillingGateway)

    private fun oneTime(
        offerId: String? = null,
        token: String? = "token",
        price: String = "NT$990",
        micros: Long = 990_000_000
    ) = OneTimeOffer(offerId, token, price, micros, "TWD")

    @Test
    fun singleOfferProductUsesTheSingleOfferAccessor() {
        // A plain one-time product: Play leaves the offer list null and fills only the single offer.
        val offer = lifetimeOffer(ProProducts.LIFETIME_ID, offers = null, singleOffer = oneTime(token = "single"))
        assertEquals(ProPlan.LIFETIME, offer?.plan)
        assertEquals(ProProducts.LIFETIME_ID, offer?.productId)
        assertEquals("single", offer?.offerToken)
        assertEquals("NT$990", offer?.formattedPrice)
        assertEquals(990_000_000L, offer?.priceMicros)
        assertEquals("TWD", offer?.currencyCode)
    }

    @Test
    fun emptyOfferListFallsBackToTheSingleOffer() {
        val offer =
            lifetimeOffer(ProProducts.LIFETIME_ID, offers = emptyList(), singleOffer = oneTime(token = "single"))
        assertEquals("single", offer?.offerToken)
    }

    @Test
    fun singleOfferWithoutATokenIsSoldWithoutOne() {
        val offer = lifetimeOffer(ProProducts.LIFETIME_ID, offers = null, singleOffer = oneTime(token = null))
        assertEquals("", offer?.offerToken)
    }

    @Test
    fun multiOfferProductPrefersThePurchaseOptionOverADiscount() {
        val offers = listOf(
            oneTime(offerId = "launch-discount", token = "discount", price = "NT$490", micros = 490_000_000),
            oneTime(offerId = null, token = "base")
        )
        val offer = lifetimeOffer(ProProducts.LIFETIME_ID, offers, singleOffer = oneTime(token = "single"))
        assertEquals("base", offer?.offerToken)
        assertEquals("NT$990", offer?.formattedPrice)
    }

    @Test
    fun noOfferAtAllHidesLifetime() {
        assertNull(lifetimeOffer(ProProducts.LIFETIME_ID, offers = null, singleOffer = null))
    }
}
