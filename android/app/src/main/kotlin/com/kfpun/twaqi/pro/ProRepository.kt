package com.kfpun.twaqi.pro

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** What the user holds. Only [PRO] unlocks anything; [PENDING] waits on Play. */
enum class Entitlement { FREE, PENDING, PRO }

enum class PurchaseOutcome {
    PURCHASED,

    /** Paid with a slow method; Pro turns on when Play confirms it. */
    PENDING,

    /** The sheet was closed. */
    NOT_COMPLETED,
    FAILED
}

enum class RestoreOutcome { RESTORED, PENDING, NOT_FOUND, FAILED }

/**
 * The one source of Pro (iOS: `IAPManager.isEntitled` + `SettingsStore.refreshPro`),
 * read by the ads, and later by the widgets and the alert limit.
 *
 * Pro is an active subscription or an owned, acknowledged lifetime purchase
 * (FOX-123), as on iOS. It follows Play rather than a flag set once on purchase:
 * Play's purchase lists leave out expired, refunded, revoked and on-hold
 * subscriptions and refunded or voided one-time purchases, so re-reading them on
 * every start ([refresh]) turns Pro off when any of those happen. A cancelled
 * subscription stays listed, and Pro, until its period ends.
 * When Play can't be reached the last confirmed value is kept, so a paying
 * user offline doesn't get ads.
 *
 * Purchases are acknowledged as soon as they're seen; Play refunds any left
 * unacknowledged for three days, so a failed acknowledgement is retried on the
 * next [refresh].
 */
class ProRepository(private val gateway: BillingGateway, private val store: EntitlementStore, scope: CoroutineScope) {
    private val state = MutableStateFlow<Entitlement?>(null)

    /** Null until the saved value is read (ads stay hidden till then); after that, never null. */
    val entitlement: StateFlow<Entitlement?> = state.asStateFlow()

    val isPro: Flow<Boolean> = entitlement.filterNotNull().map { it == Entitlement.PRO }.distinctUntilChanged()

    private val lock = Mutex()
    private var loaded = false

    /**
     * The active subscription, so buying another subscription plan switches it rather
     * than adding one. Lifetime is never switched from or to: it's bought beside it.
     */
    private var subscriptionToken: String? = null
    private val acknowledged = mutableSetOf<String>()

    /** Updates after [handleUpdate] has applied them, for [purchase] to wait on. */
    private val appliedUpdates = MutableSharedFlow<PurchasesResult>(extraBufferCapacity = 16)

    init {
        scope.launch { lock.withLock { loadSaved() } }
        scope.launch {
            gateway.purchaseUpdates.collect { update ->
                handleUpdate(update)
                appliedUpdates.emit(update)
            }
        }
    }

    /** Re-reads Pro from Play: on every app start, and after a purchase or restore. */
    suspend fun refresh(): Entitlement? {
        val result = gateway.queryPurchases()
        lock.withLock {
            loadSaved()
            if (result.status == BillingStatus.OK) apply(result.purchases)
        }
        return state.value
    }

    suspend fun queryOffers(): OffersResult = gateway.queryOffers()

    suspend fun purchase(offer: PlanOffer, launcher: PurchaseLauncher): PurchaseOutcome = coroutineScope {
        // Listen before the sheet opens, so a fast result isn't missed.
        val update = async(start = CoroutineStart.UNDISPATCHED) { appliedUpdates.first() }
        val oldToken = if (offer.plan.isLifetime) null else lock.withLock { subscriptionToken }
        val launched = launcher.launch(offer, oldToken)
        if (launched != BillingStatus.OK) {
            update.cancel()
            return@coroutineScope launchFailed(launched)
        }
        val result = update.await()
        when (result.status) {
            BillingStatus.OK -> when (lock.withLock { entitlementOf(result.purchases) }) {
                Entitlement.PRO -> PurchaseOutcome.PURCHASED

                Entitlement.PENDING -> PurchaseOutcome.PENDING

                // Not this update's purchase: Pro may already be on from another.
                Entitlement.FREE -> when (state.value) {
                    Entitlement.PRO -> PurchaseOutcome.PURCHASED
                    else -> PurchaseOutcome.FAILED
                }
            }

            else -> launchFailed(result.status)
        }
    }

    suspend fun restore(): RestoreOutcome {
        val result = gateway.queryPurchases()
        if (result.status != BillingStatus.OK) return RestoreOutcome.FAILED
        lock.withLock {
            loadSaved()
            apply(result.purchases)
        }
        return when (state.value) {
            Entitlement.PRO -> RestoreOutcome.RESTORED
            Entitlement.PENDING -> RestoreOutcome.PENDING
            else -> RestoreOutcome.NOT_FOUND
        }
    }

    private suspend fun launchFailed(status: BillingStatus): PurchaseOutcome = when (status) {
        BillingStatus.USER_CANCELED -> PurchaseOutcome.NOT_COMPLETED

        // Bought on another device, or Play hasn't told us yet.
        BillingStatus.ITEM_ALREADY_OWNED -> when (restore()) {
            RestoreOutcome.RESTORED -> PurchaseOutcome.PURCHASED
            RestoreOutcome.PENDING -> PurchaseOutcome.PENDING
            else -> PurchaseOutcome.FAILED
        }

        else -> PurchaseOutcome.FAILED
    }

    /**
     * A purchase from the sheet, or a pending one completing. The update only
     * carries that purchase, so the full list is re-read; if Play can't give
     * it, the update alone can still turn Pro on, never off.
     */
    private suspend fun handleUpdate(update: PurchasesResult) {
        if (update.status != BillingStatus.OK) return
        val full = gateway.queryPurchases()
        lock.withLock {
            loadSaved()
            if (full.status == BillingStatus.OK) {
                val tokens = full.purchases.map { it.purchaseToken }.toSet()
                apply(full.purchases + update.purchases.filter { it.purchaseToken !in tokens })
            } else {
                acknowledgeNew(update.purchases)
                val fromUpdate = entitlementOf(update.purchases)
                if (fromUpdate.ordinal > (state.value ?: Entitlement.FREE).ordinal) save(fromUpdate)
            }
        }
    }

    /** Call with [lock] held. */
    private suspend fun apply(purchases: List<OwnedPurchase>) {
        acknowledgeNew(purchases)
        subscriptionToken = purchases.firstOrNull { it.isSubscription && it.state == OwnedPurchase.State.PURCHASED }
            ?.purchaseToken
        save(entitlementOf(purchases))
    }

    private suspend fun acknowledgeNew(purchases: List<OwnedPurchase>) {
        purchases
            .filter { it.isPro && it.state == OwnedPurchase.State.PURCHASED && !it.isAcknowledged }
            .filter { it.purchaseToken !in acknowledged }
            .forEach { purchase ->
                if (gateway.acknowledge(purchase.purchaseToken) == BillingStatus.OK) {
                    acknowledged += purchase.purchaseToken
                } else {
                    Log.w(TAG, "Acknowledge failed; retried on the next refresh")
                }
            }
    }

    /** Call with [lock] held. A fresh install with nothing saved starts free. */
    private suspend fun loadSaved() {
        if (loaded) return
        loaded = true
        if (state.value == null) {
            state.value = runCatching { store.read() }.getOrNull() ?: Entitlement.FREE
        }
    }

    private suspend fun save(entitlement: Entitlement) {
        if (state.value == entitlement) return
        state.value = entitlement
        runCatching { store.write(entitlement) }.onFailure { Log.w(TAG, "Couldn't save Pro", it) }
    }

    /**
     * Call with [lock] held, after [acknowledgeNew]. A paid subscription is Pro at once
     * (its acknowledgement is retried if it fails). A paid lifetime purchase is Pro once
     * acknowledged, by Play's flag or by our call: until then Play may still refund it,
     * so it waits as [Entitlement.PENDING] and is acknowledged again on the next refresh.
     */
    private fun entitlementOf(purchases: List<OwnedPurchase>): Entitlement {
        val paid = purchases.filter { it.isPro && it.state == OwnedPurchase.State.PURCHASED }
        val ownsLifetime = paid.any { it.isLifetime && (it.isAcknowledged || it.purchaseToken in acknowledged) }
        return when {
            ownsLifetime || paid.any { it.isSubscription } -> Entitlement.PRO

            paid.isNotEmpty() || purchases.any { it.isPro && it.state == OwnedPurchase.State.PENDING } ->
                Entitlement.PENDING

            else -> Entitlement.FREE
        }
    }

    private companion object {
        const val TAG = "TWAQIPro"
    }
}
