package com.kfpun.twaqi.pro

import com.kfpun.twaqi.analytics.Analytics
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** The Pro screen's funnel events and outcomes, named as on iOS. */
@OptIn(ExperimentalCoroutinesApi::class)
class ProViewModelTest {
    private val play = FakeBillingGateway()
    private val events = mutableListOf<Pair<String, Map<String, String>>>()
    private lateinit var scope: CoroutineScope

    @Before
    fun setUp() {
        val dispatcher = UnconfinedTestDispatcher()
        Dispatchers.setMain(dispatcher)
        scope = CoroutineScope(SupervisorJob() + dispatcher)
    }

    @After
    fun tearDown() {
        scope.cancel()
        Dispatchers.resetMain()
    }

    private fun model(source: ProScreenSource = ProScreenSource.AD_BANNER) =
        ProViewModel(ProRepository(play, InMemoryEntitlementStore(), scope), source) { name, parameters ->
            events += name to parameters
        }

    private val names get() = events.map { it.first }

    @Test
    fun openingLogsTheSourceAndLoadsThePlansInOrder() {
        val model = model(ProScreenSource.WIDGET_LOCKED)
        assertEquals(Analytics.PRO_SCREEN_OPENED to mapOf("source" to "widget_locked"), events.first())
        assertEquals(ProPlan.entries, model.uiState.value.offers.map { it.plan })
        assertFalse(model.uiState.value.loadFailed)
    }

    @Test
    fun plansThatDontLoadOfferRetry() {
        play.queryStatus = BillingStatus.UNAVAILABLE
        val model = model()
        assertTrue(model.uiState.value.loadFailed)

        play.queryStatus = BillingStatus.OK
        model.load()
        assertEquals(4, model.uiState.value.offers.size)
    }

    @Test
    fun lifetimeIsListedLast() {
        assertEquals(ProPlan.LIFETIME, model().uiState.value.offers.last().plan)
    }

    @Test
    fun lifetimeMissingFromPlayLeavesTheSubscriptionsWithoutAnError() {
        play.offers = play.offers.filterNot { it.plan.isLifetime }
        val model = model()
        assertEquals(
            listOf(ProPlan.ONE_MONTH, ProPlan.SIX_MONTHS, ProPlan.TWELVE_MONTHS),
            model.uiState.value.offers.map { it.plan }
        )
        assertFalse(model.uiState.value.loadFailed)
    }

    @Test
    fun lifetimePurchaseLogsTheLifetimePlanAndCloses() {
        val model = model()
        model.buy(FakeBillingGateway.offer(ProPlan.LIFETIME), play.launcher)
        assertEquals(Analytics.BUY_PRODUCT_DONE, names.last())
        assertEquals(mapOf("plan" to "lifetime", "source" to "ad_banner"), events.last().second)
        assertTrue(model.uiState.value.done)
    }

    @Test
    fun restoreThatFindsLifetimeCloses() {
        play.purchases += FakeBillingGateway.purchase(ProPlan.LIFETIME)
        val model = model()
        model.restore()
        assertEquals(Analytics.RESTORE_PURCHASE_DONE, names.last())
        assertTrue(model.uiState.value.done)
    }

    @Test
    fun purchaseLogsTheFunnelAndCloses() {
        val model = model()
        model.buy(FakeBillingGateway.offer(ProPlan.SIX_MONTHS), play.launcher)
        val parameters = mapOf("plan" to "6m", "source" to "ad_banner")
        assertEquals(
            listOf(
                Analytics.PRO_SCREEN_OPENED,
                Analytics.PRO_PLAN_SELECTED,
                Analytics.BUY_PRODUCT_STARTED,
                Analytics.BUY_PRODUCT_DONE
            ),
            names
        )
        assertEquals(parameters, events.last().second)
        assertTrue(model.uiState.value.done)
        assertFalse(model.uiState.value.busy)
    }

    @Test
    fun failedPurchaseShowsTheAlert() {
        play.onLaunch = { _, _ -> BillingStatus.ERROR }
        val model = model()
        model.buy(FakeBillingGateway.offer(ProPlan.ONE_MONTH), play.launcher)
        assertEquals(Analytics.BUY_PRODUCT_FAILED, names.last())
        assertEquals(ProDialog.PURCHASE_FAILED, model.uiState.value.dialog)
        assertFalse(model.uiState.value.done)
    }

    @Test
    fun pendingPurchaseIsNotCompletedAndExplained() {
        play.onLaunch = { offer, _ ->
            play.buy(offer.plan, OwnedPurchase.State.PENDING)
            BillingStatus.OK
        }
        val model = model()
        model.buy(FakeBillingGateway.offer(ProPlan.ONE_MONTH), play.launcher)
        assertEquals(Analytics.BUY_PRODUCT_NOT_COMPLETED, names.last())
        assertEquals(ProDialog.PURCHASE_PENDING, model.uiState.value.dialog)
    }

    @Test
    fun restoreWithNothingFoundFails() {
        val model = model()
        model.restore()
        assertEquals(listOf(Analytics.RESTORE_PURCHASE_STARTED, Analytics.RESTORE_PURCHASE_FAILED), names.drop(1))
        assertEquals(ProDialog.PURCHASE_FAILED, model.uiState.value.dialog)
    }

    @Test
    fun restoreThatFindsProCloses() {
        play.purchases += FakeBillingGateway.purchase(ProPlan.TWELVE_MONTHS)
        val model = model()
        model.restore()
        assertEquals(Analytics.RESTORE_PURCHASE_DONE, names.last())
        assertTrue(model.uiState.value.done)
    }
}
