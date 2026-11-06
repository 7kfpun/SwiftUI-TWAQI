package com.kfpun.twaqi.pro

import android.app.Activity
import kotlinx.coroutines.flow.MutableSharedFlow

/** Play in memory: what it lists, what each call returns, and what the sheet does. */
class FakeBillingGateway : BillingGateway {
    override val purchaseUpdates = MutableSharedFlow<PurchasesResult>(extraBufferCapacity = 16)

    /** What [queryPurchases] lists; Play drops expired, refunded and revoked ones. */
    var purchases = mutableListOf<OwnedPurchase>()
    var queryStatus = BillingStatus.OK
    var acknowledgeStatus = BillingStatus.OK
    var offers = ProPlan.entries.map { offer(it) }
    val acknowledgedTokens = mutableListOf<String>()
    var queryCount = 0

    /** What tapping a plan does: by default the user pays and Play reports it. */
    var onLaunch: (PlanOffer, String?) -> BillingStatus = { offer, _ ->
        buy(offer.plan)
        BillingStatus.OK
    }
    val launches = mutableListOf<Pair<PlanOffer, String?>>()

    val launcher = PurchaseLauncher { offer, oldToken ->
        launches += offer to oldToken
        onLaunch(offer, oldToken)
    }

    override suspend fun queryOffers(): OffersResult {
        val offers = if (queryStatus == BillingStatus.OK) offers else emptyList()
        return OffersResult(queryStatus, offers)
    }

    override suspend fun queryPurchases(): PurchasesResult {
        queryCount++
        return PurchasesResult(queryStatus, if (queryStatus == BillingStatus.OK) purchases.toList() else emptyList())
    }

    override suspend fun acknowledge(purchaseToken: String): BillingStatus {
        if (acknowledgeStatus == BillingStatus.OK) {
            acknowledgedTokens += purchaseToken
            purchases.replaceAll { if (it.purchaseToken == purchaseToken) it.copy(isAcknowledged = true) else it }
        }
        return acknowledgeStatus
    }

    override fun launcher(activity: Activity) = launcher

    /** A completed purchase: Play lists it and tells the listener. */
    fun buy(plan: ProPlan, state: OwnedPurchase.State = OwnedPurchase.State.PURCHASED): OwnedPurchase {
        val purchase = purchase(plan, state)
        purchases.removeAll { it.isPro }
        purchases += purchase
        purchaseUpdates.tryEmit(PurchasesResult(BillingStatus.OK, listOf(purchase)))
        return purchase
    }

    companion object {
        fun offer(plan: ProPlan) = PlanOffer(
            plan = plan,
            productId = ProProducts.SUBSCRIPTION_ID,
            offerToken = "offer-${plan.basePlanId}",
            formattedPrice = "$${plan.months}.00",
            priceMicros = plan.months * 1_000_000L,
            currencyCode = "USD"
        )

        fun purchase(
            plan: ProPlan,
            state: OwnedPurchase.State = OwnedPurchase.State.PURCHASED,
            acknowledged: Boolean = false,
            productId: String = ProProducts.SUBSCRIPTION_ID
        ) = OwnedPurchase(
            productIds = listOf(productId),
            state = state,
            isAcknowledged = acknowledged,
            purchaseToken = "token-${plan.basePlanId}-$state"
        )
    }
}

class InMemoryEntitlementStore(var saved: Entitlement? = null) : EntitlementStore {
    override suspend fun read() = saved

    override suspend fun write(entitlement: Entitlement) {
        saved = entitlement
    }
}
