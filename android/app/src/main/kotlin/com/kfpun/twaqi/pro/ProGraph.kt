package com.kfpun.twaqi.pro

import android.content.Context
import com.kfpun.twaqi.BuildConfig
import com.kfpun.twaqi.widget.WidgetUpdater
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/**
 * The app-wide [ProRepository]. Widgets, the alert limit and anything else that
 * asks "is this Pro?" read `ProGraph.repository(context).isPro`.
 */
object ProGraph {
    @Volatile
    private var gateway: BillingGateway? = null

    @Volatile
    private var repository: ProRepository? = null

    fun repository(context: Context): ProRepository = repository ?: synchronized(this) {
        repository ?: ProRepository(
            gateway = gateway(context),
            store = DataStoreEntitlementStore(context),
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        ).also {
            repository = it
            // FOX-59: widgets redraw when Pro changes.
            WidgetUpdater.observePro(context, it.isPro)
        }
    }

    fun gateway(context: Context): BillingGateway = gateway ?: synchronized(this) {
        gateway ?: PlayBillingGateway(context).also { gateway = it }
    }

    /**
     * Debug builds only: sell the plans from [DemoBillingGateway] instead of Play, for
     * emulators without Play and for screenshots. Must run before the first [repository].
     */
    fun useDemoBilling() {
        if (!BuildConfig.DEBUG) return
        synchronized(this) {
            if (repository == null) gateway = DemoBillingGateway()
        }
    }
}
