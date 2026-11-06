package com.kfpun.twaqi.pro

import android.app.Activity
import android.content.Context
import android.util.Log
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClient.BillingResponseCode
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * [BillingGateway] over the Play Billing Library. Verification is on the device
 * for now (Play's signed purchase list); a server-side check is a follow-up.
 */
class PlayBillingGateway(context: Context) : BillingGateway {
    private val updates = MutableSharedFlow<PurchasesResult>(extraBufferCapacity = 16)
    override val purchaseUpdates: Flow<PurchasesResult> = updates.asSharedFlow()

    private val client: BillingClient = BillingClient.newBuilder(context.applicationContext)
        .setListener { result, purchases ->
            updates.tryEmit(PurchasesResult(result.status(), purchases.orEmpty().map { it.toOwned() }))
        }
        // The library requires it. A purchase paid with a slow method (cash, some
        // bank transfers) arrives PENDING, handled by ProRepository: the lifetime
        // product (FOX-123) is a one-time product, subscriptions arrive PENDING either way.
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection()
        .build()

    private val connectLock = Mutex()

    /** From the last [queryOffers]; the purchase sheet needs Play's own object. */
    private val productDetails = ConcurrentHashMap<String, ProductDetails>()

    private suspend fun connect(): BillingStatus = connectLock.withLock {
        if (client.isReady) return BillingStatus.OK
        suspendCancellableCoroutine { continuation ->
            val resumed = AtomicBoolean(false)
            client.startConnection(object : BillingClientStateListener {
                override fun onBillingSetupFinished(result: BillingResult) {
                    if (resumed.compareAndSet(false, true)) continuation.resume(result.status())
                }

                override fun onBillingServiceDisconnected() {
                    if (resumed.compareAndSet(false, true)) continuation.resume(BillingStatus.UNAVAILABLE)
                }
            })
        }
    }

    override suspend fun queryOffers(): OffersResult {
        val connected = connect()
        if (connected != BillingStatus.OK) return OffersResult(connected)
        // One query per product type: Play rejects a product list that mixes them.
        return mergeOffers(
            subscriptions = queryOffers(ProProducts.SUBSCRIPTION_ID, BillingClient.ProductType.SUBS) { product ->
                product.subscriptionOfferDetails.orEmpty()
                    // The base plan's own offer: no trial or intro price, as on iOS.
                    .filter { it.offerId == null }
                    .mapNotNull { offer ->
                        val plan = ProPlan.forBasePlan(offer.basePlanId) ?: return@mapNotNull null
                        val price = offer.pricingPhases.pricingPhaseList.lastOrNull() ?: return@mapNotNull null
                        PlanOffer(
                            plan = plan,
                            productId = product.productId,
                            offerToken = offer.offerToken,
                            formattedPrice = price.formattedPrice,
                            priceMicros = price.priceAmountMicros,
                            currencyCode = price.priceCurrencyCode
                        )
                    }
            },
            lifetime = queryOffers(ProProducts.LIFETIME_ID, BillingClient.ProductType.INAPP) { product ->
                listOfNotNull(
                    lifetimeOffer(
                        productId = product.productId,
                        offers = product.oneTimePurchaseOfferDetailsList?.map { it.toOneTimeOffer() },
                        singleOffer = product.oneTimePurchaseOfferDetails?.toOneTimeOffer()
                    )
                )
            }
        )
    }

    private suspend fun queryOffers(
        productId: String,
        productType: String,
        offersOf: (ProductDetails) -> List<PlanOffer>
    ): OffersResult {
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(
                listOf(
                    QueryProductDetailsParams.Product.newBuilder()
                        .setProductId(productId)
                        .setProductType(productType)
                        .build()
                )
            )
            .build()
        val (result, details) = suspendCancellableCoroutine { continuation ->
            client.queryProductDetailsAsync(params) { result, details ->
                continuation.resume(result to details.productDetailsList)
            }
        }
        if (result.status() != BillingStatus.OK) return OffersResult(result.status())
        details.forEach { productDetails[it.productId] = it }
        return OffersResult(BillingStatus.OK, details.flatMap(offersOf))
    }

    /** Both product types, so restore finds a lifetime purchase as well as a subscription. */
    override suspend fun queryPurchases(): PurchasesResult {
        val connected = connect()
        if (connected != BillingStatus.OK) return PurchasesResult(connected)
        return mergePurchases(
            subscriptions = queryPurchases(BillingClient.ProductType.SUBS),
            lifetime = queryPurchases(BillingClient.ProductType.INAPP)
        )
    }

    private suspend fun queryPurchases(productType: String): PurchasesResult {
        val params = QueryPurchasesParams.newBuilder().setProductType(productType).build()
        return suspendCancellableCoroutine { continuation ->
            client.queryPurchasesAsync(params) { result, purchases ->
                continuation.resume(PurchasesResult(result.status(), purchases.map { it.toOwned() }))
            }
        }
    }

    override suspend fun acknowledge(purchaseToken: String): BillingStatus {
        val connected = connect()
        if (connected != BillingStatus.OK) return connected
        val params = AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchaseToken).build()
        return suspendCancellableCoroutine { continuation ->
            client.acknowledgePurchase(params) { result -> continuation.resume(result.status()) }
        }
    }

    override fun launcher(activity: Activity): PurchaseLauncher = PurchaseLauncher { offer, oldPurchaseToken ->
        val details = productDetails[offer.productId]
        if (details == null || !client.isReady) return@PurchaseLauncher BillingStatus.UNAVAILABLE
        val product = BillingFlowParams.ProductDetailsParams.newBuilder()
            .setProductDetails(details)
            .apply { if (offer.offerToken.isNotEmpty()) setOfferToken(offer.offerToken) }
            .build()
        val params = BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(product))
        // Only a subscription replaces another plan; lifetime is bought beside it.
        if (oldPurchaseToken != null && !offer.plan.isLifetime) {
            // Changing plan: the new one starts now, with the unused time credited.
            // Billing 9 deprecates the replacement mode here for per-product
            // replacement params; move once a plan switch is tested with a license tester.
            @Suppress("DEPRECATION")
            params.setSubscriptionUpdateParams(
                BillingFlowParams.SubscriptionUpdateParams.newBuilder()
                    .setOldPurchaseToken(oldPurchaseToken)
                    .setSubscriptionReplacementMode(
                        BillingFlowParams.SubscriptionUpdateParams.ReplacementMode.WITH_TIME_PRORATION
                    )
                    .build()
            )
        }
        client.launchBillingFlow(activity, params.build()).status()
    }

    private fun BillingResult.status(): BillingStatus {
        val status = when (responseCode) {
            BillingResponseCode.OK -> BillingStatus.OK

            BillingResponseCode.USER_CANCELED -> BillingStatus.USER_CANCELED

            BillingResponseCode.ITEM_ALREADY_OWNED -> BillingStatus.ITEM_ALREADY_OWNED

            BillingResponseCode.BILLING_UNAVAILABLE,
            BillingResponseCode.SERVICE_UNAVAILABLE,
            BillingResponseCode.SERVICE_DISCONNECTED,
            BillingResponseCode.NETWORK_ERROR -> BillingStatus.UNAVAILABLE

            else -> BillingStatus.ERROR
        }
        if (status != BillingStatus.OK && status != BillingStatus.USER_CANCELED) {
            Log.w(TAG, "Play Billing $responseCode: $debugMessage")
        }
        return status
    }

    private fun Purchase.toOwned() = OwnedPurchase(
        productIds = products,
        state = when (purchaseState) {
            Purchase.PurchaseState.PURCHASED -> OwnedPurchase.State.PURCHASED
            Purchase.PurchaseState.PENDING -> OwnedPurchase.State.PENDING
            else -> OwnedPurchase.State.UNSPECIFIED
        },
        isAcknowledged = isAcknowledged,
        purchaseToken = purchaseToken
    )

    private fun ProductDetails.OneTimePurchaseOfferDetails.toOneTimeOffer() = OneTimeOffer(
        offerId = offerId,
        offerToken = offerToken,
        formattedPrice = formattedPrice,
        priceMicros = priceAmountMicros,
        currencyCode = priceCurrencyCode
    )

    private companion object {
        const val TAG = "TWAQIBilling"
    }
}
