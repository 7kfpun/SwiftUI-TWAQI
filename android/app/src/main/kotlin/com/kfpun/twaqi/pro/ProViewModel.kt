package com.kfpun.twaqi.pro

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.kfpun.twaqi.analytics.Analytics
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class ProDialog { PURCHASE_FAILED, PURCHASE_PENDING }

data class ProUiState(
    val offers: List<PlanOffer> = emptyList(),
    val loadFailed: Boolean = false,
    /** A purchase or restore is running: the plans and restore are disabled. */
    val busy: Boolean = false,
    val purchasingPlan: ProPlan? = null,
    val dialog: ProDialog? = null,
    /** Pro is on: the screen closes, as on iOS. */
    val done: Boolean = false
)

/** The Pro screen's state and funnel events (iOS: `ProView`'s load / buy / restore). */
class ProViewModel(
    private val repository: ProRepository,
    private val source: ProScreenSource,
    private val logEvent: (String, Map<String, String>) -> Unit
) : ViewModel() {
    private val state = MutableStateFlow(ProUiState())
    val uiState: StateFlow<ProUiState> = state.asStateFlow()

    val entitlement = repository.entitlement

    init {
        logEvent(Analytics.PRO_SCREEN_OPENED, mapOf("source" to source.analyticsName))
        load()
    }

    fun load() {
        state.update { it.copy(loadFailed = false) }
        viewModelScope.launch {
            val result = repository.queryOffers()
            val offers = if (result.status == BillingStatus.OK) result.offers else emptyList()
            state.update { it.copy(offers = offers, loadFailed = offers.isEmpty()) }
        }
    }

    fun buy(offer: PlanOffer, launcher: PurchaseLauncher) {
        if (state.value.busy) return
        state.update { it.copy(busy = true, purchasingPlan = offer.plan) }
        val parameters = mapOf("plan" to offer.plan.analyticsName, "source" to source.analyticsName)
        logEvent(Analytics.PRO_PLAN_SELECTED, parameters)
        logEvent(Analytics.BUY_PRODUCT_STARTED, parameters)
        viewModelScope.launch {
            val outcome = runCatching { repository.purchase(offer, launcher) }.getOrDefault(PurchaseOutcome.FAILED)
            when (outcome) {
                PurchaseOutcome.PURCHASED -> logEvent(Analytics.BUY_PRODUCT_DONE, parameters)

                PurchaseOutcome.PENDING, PurchaseOutcome.NOT_COMPLETED ->
                    logEvent(Analytics.BUY_PRODUCT_NOT_COMPLETED, parameters)

                PurchaseOutcome.FAILED -> logEvent(Analytics.BUY_PRODUCT_FAILED, parameters)
            }
            state.update {
                it.copy(
                    busy = false,
                    purchasingPlan = null,
                    done = outcome == PurchaseOutcome.PURCHASED,
                    dialog = when (outcome) {
                        PurchaseOutcome.PENDING -> ProDialog.PURCHASE_PENDING
                        PurchaseOutcome.FAILED -> ProDialog.PURCHASE_FAILED
                        else -> null
                    }
                )
            }
        }
    }

    fun restore() {
        if (state.value.busy) return
        state.update { it.copy(busy = true) }
        val parameters = mapOf("source" to source.analyticsName)
        logEvent(Analytics.RESTORE_PURCHASE_STARTED, parameters)
        viewModelScope.launch {
            val outcome = runCatching { repository.restore() }.getOrDefault(RestoreOutcome.FAILED)
            logEvent(
                if (outcome ==
                    RestoreOutcome.RESTORED
                ) {
                    Analytics.RESTORE_PURCHASE_DONE
                } else {
                    Analytics.RESTORE_PURCHASE_FAILED
                },
                parameters
            )
            state.update {
                it.copy(
                    busy = false,
                    done = outcome == RestoreOutcome.RESTORED,
                    dialog = when (outcome) {
                        RestoreOutcome.RESTORED -> null
                        RestoreOutcome.PENDING -> ProDialog.PURCHASE_PENDING
                        else -> ProDialog.PURCHASE_FAILED
                    }
                )
            }
        }
    }

    fun dismissDialog() = state.update { it.copy(dialog = null) }

    companion object {
        fun factory(
            repository: ProRepository,
            source: ProScreenSource,
            logEvent: (String, Map<String, String>) -> Unit
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer { ProViewModel(repository, source, logEvent) }
        }
    }
}
