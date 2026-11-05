package com.kfpun.twaqi.pro

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The entitlement state machine (FOX-58) against a fake Play. */
@OptIn(ExperimentalCoroutinesApi::class)
class ProRepositoryTest {
    private val play = FakeBillingGateway()
    private val store = InMemoryEntitlementStore()

    private fun TestScope.repository(): ProRepository = ProRepository(play, store, backgroundScope).also {
        runCurrent()
    }

    // Start and the saved value

    @Test
    fun nothingIsKnownUntilTheSavedValueIsRead() = runTest {
        val repository = ProRepository(play, store, backgroundScope)
        assertNull(repository.entitlement.value)
        runCurrent()
        assertEquals(Entitlement.FREE, repository.entitlement.value)
    }

    @Test
    fun savedProHoldsWhilePlayCantBeReached() = runTest {
        store.saved = Entitlement.PRO
        play.queryStatus = BillingStatus.UNAVAILABLE
        val repository = repository()
        assertEquals(Entitlement.PRO, repository.entitlement.value)
        assertEquals(Entitlement.PRO, repository.refresh())
        assertEquals(Entitlement.PRO, store.saved)
    }

    @Test
    fun freshInstallOfflineStartsFree() = runTest {
        play.queryStatus = BillingStatus.UNAVAILABLE
        assertEquals(Entitlement.FREE, repository().refresh())
    }

    // Re-check on start

    @Test
    fun activeSubscriptionIsProAndGetsAcknowledged() = runTest {
        val purchase = FakeBillingGateway.purchase(ProPlan.SIX_MONTHS)
        play.purchases += purchase
        val repository = repository()
        assertEquals(Entitlement.PRO, repository.refresh())
        assertEquals(listOf(purchase.purchaseToken), play.acknowledgedTokens)
        assertEquals(Entitlement.PRO, store.saved)
    }

    @Test
    fun acknowledgedPurchaseIsNotAcknowledgedAgain() = runTest {
        play.purchases += FakeBillingGateway.purchase(ProPlan.ONE_MONTH, acknowledged = true)
        assertEquals(Entitlement.PRO, repository().refresh())
        assertTrue(play.acknowledgedTokens.isEmpty())
    }

    @Test
    fun failedAcknowledgementKeepsProAndIsRetriedOnTheNextStart() = runTest {
        val purchase = FakeBillingGateway.purchase(ProPlan.ONE_MONTH)
        play.purchases += purchase
        play.acknowledgeStatus = BillingStatus.ERROR
        val repository = repository()
        assertEquals(Entitlement.PRO, repository.refresh())
        assertTrue(play.acknowledgedTokens.isEmpty())

        play.acknowledgeStatus = BillingStatus.OK
        repository.refresh()
        assertEquals(listOf(purchase.purchaseToken), play.acknowledgedTokens)
    }

    @Test
    fun cancelledSubscriptionStaysProUntilPlayDropsIt() = runTest {
        // Cancelling only stops renewal: Play lists it until the period ends.
        play.purchases += FakeBillingGateway.purchase(ProPlan.ONE_MONTH, acknowledged = true)
        val repository = repository()
        assertEquals(Entitlement.PRO, repository.refresh())

        play.purchases.clear()
        assertEquals(Entitlement.FREE, repository.refresh())
        assertEquals(Entitlement.FREE, store.saved)
    }

    @Test
    fun refundedOrRevokedSubscriptionTurnsProOffOnTheNextStart() = runTest {
        store.saved = Entitlement.PRO
        val repository = repository()
        assertEquals(Entitlement.PRO, repository.entitlement.value)
        // Play no longer lists a refunded, revoked or expired subscription.
        assertEquals(Entitlement.FREE, repository.refresh())
        assertEquals(Entitlement.FREE, store.saved)
    }

    @Test
    fun pendingPaymentIsNotProAndIsNotAcknowledged() = runTest {
        play.purchases += FakeBillingGateway.purchase(ProPlan.TWELVE_MONTHS, OwnedPurchase.State.PENDING)
        assertEquals(Entitlement.PENDING, repository().refresh())
        assertTrue(play.acknowledgedTokens.isEmpty())
    }

    @Test
    fun pendingPaymentCompletingTurnsProOn() = runTest {
        play.purchases += FakeBillingGateway.purchase(ProPlan.TWELVE_MONTHS, OwnedPurchase.State.PENDING)
        val repository = repository()
        repository.refresh()

        val completed = play.buy(ProPlan.TWELVE_MONTHS)
        runCurrent()
        assertEquals(Entitlement.PRO, repository.entitlement.value)
        assertEquals(listOf(completed.purchaseToken), play.acknowledgedTokens)
    }

    @Test
    fun otherProductsDontCountAsPro() = runTest {
        play.purchases += FakeBillingGateway.purchase(ProPlan.ONE_MONTH, productId = "something.else")
        assertEquals(Entitlement.FREE, repository().refresh())
        assertTrue(play.acknowledgedTokens.isEmpty())
    }

    @Test
    fun purchaseUpdateTurnsProOnEvenWhenTheListCantBeRead() = runTest {
        val repository = repository()
        play.queryStatus = BillingStatus.UNAVAILABLE
        play.buy(ProPlan.ONE_MONTH)
        runCurrent()
        assertEquals(Entitlement.PRO, repository.entitlement.value)
    }

    // Purchase

    @Test
    fun purchaseTurnsProOnAndAcknowledges() = runTest {
        val repository = repository()
        val outcome = repository.purchase(FakeBillingGateway.offer(ProPlan.SIX_MONTHS), play.launcher)
        assertEquals(PurchaseOutcome.PURCHASED, outcome)
        assertEquals(Entitlement.PRO, repository.entitlement.value)
        assertEquals(1, play.acknowledgedTokens.size)
        assertEquals(Entitlement.PRO, store.saved)
    }

    @Test
    fun closingTheSheetIsNotCompletedAndStaysFree() = runTest {
        play.onLaunch = { _, _ ->
            play.purchaseUpdates.tryEmit(PurchasesResult(BillingStatus.USER_CANCELED))
            BillingStatus.OK
        }
        val repository = repository()
        assertEquals(
            PurchaseOutcome.NOT_COMPLETED,
            repository.purchase(FakeBillingGateway.offer(ProPlan.ONE_MONTH), play.launcher)
        )
        assertEquals(Entitlement.FREE, repository.entitlement.value)
    }

    @Test
    fun pendingPurchaseIsPendingNotPro() = runTest {
        play.onLaunch = { offer, _ ->
            play.buy(offer.plan, OwnedPurchase.State.PENDING)
            BillingStatus.OK
        }
        val repository = repository()
        assertEquals(
            PurchaseOutcome.PENDING,
            repository.purchase(FakeBillingGateway.offer(ProPlan.ONE_MONTH), play.launcher)
        )
        assertEquals(Entitlement.PENDING, repository.entitlement.value)
    }

    @Test
    fun sheetThatCantOpenFails() = runTest {
        play.onLaunch = { _, _ -> BillingStatus.UNAVAILABLE }
        val repository = repository()
        assertEquals(
            PurchaseOutcome.FAILED,
            repository.purchase(FakeBillingGateway.offer(ProPlan.ONE_MONTH), play.launcher)
        )
        assertEquals(Entitlement.FREE, repository.entitlement.value)
    }

    @Test
    fun purchaseErrorFromPlayFails() = runTest {
        play.onLaunch = { _, _ ->
            play.purchaseUpdates.tryEmit(PurchasesResult(BillingStatus.ERROR))
            BillingStatus.OK
        }
        assertEquals(
            PurchaseOutcome.FAILED,
            repository().purchase(FakeBillingGateway.offer(ProPlan.ONE_MONTH), play.launcher)
        )
    }

    @Test
    fun alreadyOwnedRestoresInstead() = runTest {
        play.purchases += FakeBillingGateway.purchase(ProPlan.TWELVE_MONTHS)
        play.onLaunch = { _, _ -> BillingStatus.ITEM_ALREADY_OWNED }
        val repository = repository()
        assertEquals(
            PurchaseOutcome.PURCHASED,
            repository.purchase(FakeBillingGateway.offer(ProPlan.TWELVE_MONTHS), play.launcher)
        )
        assertEquals(Entitlement.PRO, repository.entitlement.value)
    }

    @Test
    fun buyingAnotherPlanSwitchesTheCurrentOne() = runTest {
        val current = FakeBillingGateway.purchase(ProPlan.ONE_MONTH, acknowledged = true)
        play.purchases += current
        val repository = repository()
        repository.refresh()

        repository.purchase(FakeBillingGateway.offer(ProPlan.TWELVE_MONTHS), play.launcher)
        assertEquals(current.purchaseToken, play.launches.single().second)
    }

    @Test
    fun firstPurchaseHasNoPlanToSwitch() = runTest {
        repository().purchase(FakeBillingGateway.offer(ProPlan.ONE_MONTH), play.launcher)
        assertNull(play.launches.single().second)
    }

    // Restore

    @Test
    fun restoreFindsAPurchase() = runTest {
        val repository = repository()
        play.purchases += FakeBillingGateway.purchase(ProPlan.SIX_MONTHS)
        assertEquals(RestoreOutcome.RESTORED, repository.restore())
        assertEquals(Entitlement.PRO, repository.entitlement.value)
    }

    @Test
    fun restoreWithNothingToRestore() = runTest {
        assertEquals(RestoreOutcome.NOT_FOUND, repository().restore())
    }

    @Test
    fun restoreOfAPendingPayment() = runTest {
        play.purchases += FakeBillingGateway.purchase(ProPlan.SIX_MONTHS, OwnedPurchase.State.PENDING)
        assertEquals(RestoreOutcome.PENDING, repository().restore())
    }

    @Test
    fun restoreOfflineFailsAndKeepsPro() = runTest {
        store.saved = Entitlement.PRO
        play.queryStatus = BillingStatus.UNAVAILABLE
        val repository = repository()
        assertEquals(RestoreOutcome.FAILED, repository.restore())
        assertEquals(Entitlement.PRO, repository.entitlement.value)
    }
}
