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

/**
 * A plan as Play sells it: a subscription base plan's own offer and its recurring
 * price, or the lifetime product's one-time price.
 */
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

    val isSubscription: Boolean get() = ProProducts.SUBSCRIPTION_ID in productIds

    val isLifetime: Boolean get() = ProProducts.LIFETIME_ID in productIds
}

data class PurchasesResult(val status: BillingStatus, val purchases: List<OwnedPurchase> = emptyList())

data class OffersResult(val status: BillingStatus, val offers: List<PlanOffer> = emptyList())

/**
 * The subscription and lifetime purchase lists, read with one Play query per
 * product type, as one result. Either failing fails the whole read, so a lifetime
 * buyer isn't turned free because only the subscription list came back.
 */
fun mergePurchases(subscriptions: PurchasesResult, lifetime: PurchasesResult): PurchasesResult {
    val failed = listOf(subscriptions, lifetime).firstOrNull { it.status != BillingStatus.OK }
    return failed?.let { PurchasesResult(it.status) }
        ?: PurchasesResult(BillingStatus.OK, subscriptions.purchases + lifetime.purchases)
}

/**
 * The subscription plans and the lifetime offer as one list in display order. The
 * lifetime product is optional: Play lists none until it's created in Play Console,
 * so a missing or failed lifetime query only leaves its row out. A failed
 * subscription query fails the read even when lifetime loaded, so the screen offers
 * a retry rather than lifetime alone.
 */
fun mergeOffers(subscriptions: OffersResult, lifetime: OffersResult): OffersResult {
    if (subscriptions.status != BillingStatus.OK) return OffersResult(subscriptions.status)
    val lifetimeOffers = if (lifetime.status == BillingStatus.OK) lifetime.offers else emptyList()
    return OffersResult(BillingStatus.OK, (subscriptions.offers + lifetimeOffers).inDisplayOrder())
}

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

    /**
     * Active subscriptions and the owned lifetime purchase. Play leaves out expired,
     * refunded, revoked and on-hold subscriptions, and refunded or voided one-time purchases.
     */
    suspend fun queryPurchases(): PurchasesResult

    suspend fun acknowledge(purchaseToken: String): BillingStatus

    fun launcher(activity: Activity): PurchaseLauncher
}
