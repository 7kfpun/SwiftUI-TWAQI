package com.kfpun.twaqi

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.kfpun.twaqi.ads.AdConsent
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.pro.Entitlement
import com.kfpun.twaqi.pro.ProActivity
import com.kfpun.twaqi.pro.ProGraph
import com.kfpun.twaqi.pro.ProNavigation
import com.kfpun.twaqi.pro.ProScreenSource
import com.kfpun.twaqi.ui.MainTabs
import com.kfpun.twaqi.ui.debug.DataDebugScreen
import com.kfpun.twaqi.ui.navigation.DeepLink
import com.kfpun.twaqi.ui.navigation.StationDestination
import com.kfpun.twaqi.ui.navigation.StationRoute
import com.kfpun.twaqi.ui.theme.TWAQITheme
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

// AppCompatActivity, so AppCompatDelegate.setApplicationLocales applies the app language
// below Android 13 (FOX-56).
class MainActivity : AppCompatActivity() {
    /** A station a deep link (a widget tap, FOX-59) asked to open, until the home screen opens it. */
    private val linkedStation = mutableStateOf<Int?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        startPro()
        if (savedInstanceState == null) handleLink(intent)
        setContent {
            TWAQITheme {
                // Debug builds can open the data-layer check screen (FOX-53) until the real
                // screens land; back returns home.
                var showDataScreen by rememberSaveable { mutableStateOf(false) }
                if (showDataScreen) {
                    BackHandler { showDataScreen = false }
                    DataDebugScreen()
                } else {
                    HomeScreen(
                        onOpenDataScreen = if (BuildConfig.DEBUG) ({ showDataScreen = true }) else null,
                        linkedStation = linkedStation.value,
                        onLinkedStationOpened = { linkedStation.value = null }
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleLink(intent)
    }

    /** `twaqi://station` and `twaqi://pro` links, through the one router ([DeepLink]). */
    private fun handleLink(intent: Intent?) {
        val link = DeepLink.parse(intent?.data) ?: return
        lifecycleScope.launch {
            val isPro = ProGraph.repository(this@MainActivity).entitlement.filterNotNull().first() == Entitlement.PRO
            val known = (link as? DeepLink.Station)?.let { isKnownStation(it.stationId) } ?: true
            when (val routed = DeepLink.route(link, isPro) { known }) {
                is DeepLink.Station -> {
                    linkedStation.value = routed.stationId
                    Analytics.logEvent(
                        this@MainActivity,
                        Analytics.STATION_LINK_OPENED,
                        mapOf("source" to routed.source.analyticsName, "stationId" to routed.stationId.toString())
                    )
                }

                is DeepLink.Pro -> ProNavigation.open(this@MainActivity, routed.source)

                null -> Unit
            }
        }
    }

    /** A station the app has seen: in the saved readings or the saved station list. */
    private suspend fun isKnownStation(stationId: Int): Boolean {
        val airQuality = (application as TwaqiApplication).container.airQuality
        return airQuality.savedPollutants(listOf(stationId)).isNotEmpty() ||
            airQuality.savedStations()?.value?.any { it.id == stationId } == true
    }

    /** FOX-58: re-check Pro with Play whenever the app comes to the front; ask for ad consent if free. */
    private fun startPro() {
        if (BuildConfig.DEBUG &&
            intent.getBooleanExtra(ProActivity.EXTRA_DEMO_BILLING, false)
        ) {
            ProGraph.useDemoBilling()
        }
        val pro = ProGraph.repository(this)
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) { pro.refresh() }
        }
        lifecycleScope.launch {
            // Pro users see no ads, so no consent form; one who lapses gets it then.
            pro.entitlement.filterNotNull().first { it != Entitlement.PRO }
            AdConsent.gather(this@MainActivity)
        }
    }
}

/**
 * The tabs, with the map as home (FOX-54) and Help (FOX-97), and the station screen over them.
 * [onOpenDataScreen] (debug builds only) adds a button to the data-layer check screen.
 */
@Composable
fun HomeScreen(
    modifier: Modifier = Modifier,
    onOpenDataScreen: (() -> Unit)? = null,
    linkedStation: Int? = null,
    onLinkedStationOpened: () -> Unit = {}
) {
    val context = LocalContext.current
    val pro = remember(context) { ProGraph.repository(context) }
    val entitlement by pro.entitlement.collectAsState()
    var stationId by rememberSaveable { mutableStateOf<Int?>(null) }
    // The tabs leave composition while a station is open; this keeps their state (the selected tab,
    // the search text, the map's camera) so back returns to the tab the station was opened from.
    val tabsState = rememberSaveableStateHolder()
    // A deep link (a widget tap) opens its station over the tabs.
    LaunchedEffect(linkedStation) {
        if (linkedStation != null) {
            stationId = linkedStation
            onLinkedStationOpened()
        }
    }
    val station = stationId
    if (station != null) {
        BackHandler { stationId = null }
        StationDestination(StationRoute(station), onBack = { stationId = null }, modifier = modifier)
    } else {
        tabsState.SaveableStateProvider("tabs") {
            MainTabs(
                isPro = entitlement == Entitlement.PRO,
                onOpenPro = { ProNavigation.open(context, ProScreenSource.HELP_ROW) },
                onOpenStation = { stationId = it.stationId },
                onOpenDataScreen = onOpenDataScreen,
                modifier = modifier
            )
        }
    }
}
