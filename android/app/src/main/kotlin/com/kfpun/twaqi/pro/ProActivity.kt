package com.kfpun.twaqi.pro

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.kfpun.twaqi.BuildConfig
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.ui.theme.TWAQITheme
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/**
 * The Pro screen, over whatever opened it (iOS presents `ProView` as a sheet).
 * Open it with [ProNavigation]; `twaqi://pro?source=…` opens it too.
 */
class ProActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (BuildConfig.DEBUG && intent.getBooleanExtra(EXTRA_DEMO_BILLING, false)) ProGraph.useDemoBilling()

        val link = intent.data
        if (link == null) {
            show(ProScreenSource.fromAnalyticsName(intent.getStringExtra(ProNavigation.EXTRA_SOURCE)))
            return
        }
        val source = ProDeepLink.source(
            link.scheme,
            link.host,
            link.path,
            link.getQueryParameter(ProDeepLink.SOURCE_PARAMETER)
        )
        if (source == null) {
            finish()
            return
        }
        // As on iOS, a Pro link does nothing for someone who already has Pro.
        lifecycleScope.launch {
            val entitlement = ProGraph.repository(this@ProActivity).entitlement.filterNotNull().first()
            if (entitlement == Entitlement.PRO) finish() else show(source)
        }
    }

    private fun show(source: ProScreenSource) {
        val repository = ProGraph.repository(this)
        val gateway = ProGraph.gateway(this)
        val appContext = applicationContext
        setContent {
            TWAQITheme {
                val model: ProViewModel = viewModel(
                    factory = ProViewModel.factory(repository, source) { name, parameters ->
                        Analytics.logEvent(appContext, name, parameters)
                    }
                )
                val state by model.uiState.collectAsStateWithLifecycle()
                val entitlement by model.entitlement.collectAsStateWithLifecycle()
                LaunchedEffect(state.done) { if (state.done) finish() }
                ProScreen(
                    state = state,
                    entitlement = entitlement,
                    onClose = ::finish,
                    onBuy = { model.buy(it, gateway.launcher(this)) },
                    onRetry = model::load,
                    onRestore = model::restore,
                    onDismissDialog = model::dismissDialog
                )
            }
        }
    }

    companion object {
        /** Debug builds: `adb shell am start … --ez demo_billing true` sells demo plans (DemoBillingGateway). */
        const val EXTRA_DEMO_BILLING = "demo_billing"
    }
}
