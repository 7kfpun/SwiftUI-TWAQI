package com.kfpun.twaqi.pro

import android.app.Activity
import java.util.Locale
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Sells the plans at made-up prices without Play, in memory: debug builds only
 * ([ProGraph.useDemoBilling], launched with `--ez demo_billing true`). Every
 * purchase succeeds at once and is gone on the next launch. A subscription plan
 * replaces the current one; lifetime is bought beside it, as on Play.
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
            offer(ProPlan.TWELVE_MONTHS, 790),
            offer(ProPlan.LIFETIME, 1490)
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
            purchaseToken = "demo-${offer.plan.analyticsName}"
        )
        synchronized(purchases) {
            purchases.removeAll { it.productIds == purchase.productIds }
            purchases += purchase
        }
        updates.tryEmit(PurchasesResult(BillingStatus.OK, listOf(purchase)))
        BillingStatus.OK
    }

    private fun offer(plan: ProPlan, dollars: Long) = PlanOffer(
        plan = plan,
        productId = plan.productId,
        offerToken = "demo-${plan.analyticsName}",
        formattedPrice = "NT$" + String.format(Locale.US, "%,d.00", dollars),
        priceMicros = dollars * 1_000_000,
        currencyCode = "TWD"
    )
}
