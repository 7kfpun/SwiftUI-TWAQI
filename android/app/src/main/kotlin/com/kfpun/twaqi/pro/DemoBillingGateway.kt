package com.kfpun.twaqi.pro

import android.app.Activity
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Sells the plans at made-up prices without Play, in memory: debug builds only
 * ([ProGraph.useDemoBilling], launched with `--ez demo_billing true`). Every
 * purchase succeeds at once and is gone on the next launch.
 */
class DemoBillingGateway : BillingGateway {
    private val updates = MutableSharedFlow<PurchasesResult>(extraBufferCapacity = 16)
    override val purchaseUpdates: Flow<PurchasesResult> = updates.asSharedFlow()

    private val purchases = mutableListOf<OwnedPurchase>()

    override suspend fun queryOffers() = OffersResult(
        BillingStatus.OK,
        listOf(
            offer(ProPlan.ONE_MONTH, 90),
            offer(ProPlan.SIX_MONTHS, 450),
            offer(ProPlan.TWELVE_MONTHS, 790)
        )
    )

    override suspend fun queryPurchases() = PurchasesResult(
        BillingStatus.OK,
        synchronized(purchases) {
            purchases.toList()
        }
    )

    override suspend fun acknowledge(purchaseToken: String): BillingStatus {
        synchronized(purchases) {
            purchases.replaceAll { if (it.purchaseToken == purchaseToken) it.copy(isAcknowledged = true) else it }
        }
        return BillingStatus.OK
    }

    override fun launcher(activity: Activity) = PurchaseLauncher { offer, _ ->
        val purchase = OwnedPurchase(
            productIds = listOf(offer.productId),
            state = OwnedPurchase.State.PURCHASED,
            isAcknowledged = false,
            purchaseToken = "demo-${offer.plan.basePlanId}"
        )
        synchronized(purchases) {
            purchases.clear()
            purchases += purchase
        }
        updates.tryEmit(PurchasesResult(BillingStatus.OK, listOf(purchase)))
        BillingStatus.OK
    }

    private fun offer(plan: ProPlan, dollars: Long) = PlanOffer(
        plan = plan,
        productId = ProProducts.SUBSCRIPTION_ID,
        offerToken = "demo-${plan.basePlanId}",
        formattedPrice = "NT$$dollars.00",
        priceMicros = dollars * 1_000_000,
        currencyCode = "TWD"
    )
}
