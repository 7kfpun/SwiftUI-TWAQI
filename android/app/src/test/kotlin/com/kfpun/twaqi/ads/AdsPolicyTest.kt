package com.kfpun.twaqi.ads

import com.kfpun.twaqi.pro.Entitlement
import com.kfpun.twaqi.pro.FakeBillingGateway
import com.kfpun.twaqi.pro.InMemoryEntitlementStore
import com.kfpun.twaqi.pro.ProPlan
import com.kfpun.twaqi.pro.ProRepository
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ads are for free users only (FOX-58). */
@OptIn(ExperimentalCoroutinesApi::class)
class AdsPolicyTest {
    @Test
    fun proHidesTheBanner() {
        assertFalse(AdsPolicy.showBanner(Entitlement.PRO, canRequestAds = true))
    }

    @Test
    fun freeUsersGetTheBannerOnceConsentAllows() {
        assertTrue(AdsPolicy.showBanner(Entitlement.FREE, canRequestAds = true))
        assertFalse(AdsPolicy.showBanner(Entitlement.FREE, canRequestAds = false))
    }

    @Test
    fun pendingPaymentIsNotProYet() {
        assertTrue(AdsPolicy.showBanner(Entitlement.PENDING, canRequestAds = true))
    }

    @Test
    fun nothingShowsBeforeProIsKnown() {
        assertFalse(AdsPolicy.showBanner(null, canRequestAds = true))
    }

    @Test
    fun bannerGoesAwayWhenAPurchaseCompletesAndBackWhenItLapses() = runTest {
        val play = FakeBillingGateway()
        val repository = ProRepository(play, InMemoryEntitlementStore(), backgroundScope)
        runCurrent()
        assertTrue(AdsPolicy.showBanner(repository.entitlement.value, canRequestAds = true))

        repository.purchase(FakeBillingGateway.offer(ProPlan.ONE_MONTH), play.launcher)
        assertFalse(AdsPolicy.showBanner(repository.entitlement.value, canRequestAds = true))

        play.purchases.clear()
        repository.refresh()
        assertTrue(AdsPolicy.showBanner(repository.entitlement.value, canRequestAds = true))
    }
}
