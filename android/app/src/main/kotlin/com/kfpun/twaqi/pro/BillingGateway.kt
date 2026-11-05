package com.kfpun.twaqi.pro

import android.app.Activity
import kotlinx.coroutines.flow.Flow

/** A Play Billing response, reduced to what the app acts on. */
enum class BillingStatus {
    OK,
    USER_CANCELED,
    ITEM_ALREADY_OWNED,

    /** Play can't be reached right now (offline, no Play, service down): keep what we know. */
    UNAVAILABLE,
    ERROR
}

/** A plan as Play sells it: the base plan's own offer and its recurring price. */
data class PlanOffer(
    val plan: ProPlan,
    val productId: String,
    val offerToken: String,
    val formattedPrice: String,
    val priceMicros: Long,
    val currencyCode: String
)

/** A purchase Play reports, for a product of ours or not. */
data class OwnedPurchase(
    val productIds: List<String>,
    val state: State,
    val isAcknowledged: Boolean,
    val purchaseToken: String
) {
    enum class State { PURCHASED, PENDING, UNSPECIFIED }

    val isPro: Boolean get() = productIds.any { it in ProProducts.productIds }
}

data class PurchasesResult(val status: BillingStatus, val purchases: List<OwnedPurchase> = emptyList())

data class OffersResult(val status: BillingStatus, val offers: List<PlanOffer> = emptyList())

/**
 * Starts Play's purchase sheet. Its result arrives later on
 * [BillingGateway.purchaseUpdates]; the returned status only says whether the
 * sheet opened. [oldPurchaseToken] switches an existing plan instead of buying
 * a second subscription.
 */
fun interface PurchaseLauncher {
    fun launch(offer: PlanOffer, oldPurchaseToken: String?): BillingStatus
}

/** The Play Billing calls Pro needs, behind an interface so tests use a fake. */
interface BillingGateway {
    /** Every `PurchasesUpdatedListener` call: purchases from the sheet, pending ones completing. */
    val purchaseUpdates: Flow<PurchasesResult>

    suspend fun queryOffers(): OffersResult

    /** Active subscriptions. Play leaves out expired, refunded, revoked and on-hold ones. */
    suspend fun queryPurchases(): PurchasesResult

    suspend fun acknowledge(purchaseToken: String): BillingStatus

    fun launcher(activity: Activity): PurchaseLauncher
}
