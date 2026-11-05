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
import com.kfpun.twaqi.analytics.TrackingManager
import com.kfpun.twaqi.pro.Entitlement
import com.kfpun.twaqi.pro.ProActivity
import com.kfpun.twaqi.pro.ProGraph
import com.kfpun.twaqi.pro.ProNavigation
import com.kfpun.twaqi.pro.ProScreenSource
import com.kfpun.twaqi.push.AlertNotifications
import com.kfpun.twaqi.push.PushGraph
import com.kfpun.twaqi.push.PushMessaging
import com.kfpun.twaqi.review.ReviewPrompt
import com.kfpun.twaqi.shortcuts.AirQualityAnswerActivity
import com.kfpun.twaqi.shortcuts.StationShortcuts
import com.kfpun.twaqi.ui.MainTabs
import com.kfpun.twaqi.ui.debug.DataDebugScreen
import com.kfpun.twaqi.ui.navigation.DeepLink
import com.kfpun.twaqi.ui.navigation.KnownStations
import com.kfpun.twaqi.ui.navigation.StationDestination
import com.kfpun.twaqi.ui.navigation.StationLinkSource
import com.kfpun.twaqi.ui.navigation.StationRoute
import com.kfpun.twaqi.ui.theme.TWAQITheme
import com.kfpun.twaqi.widget.WidgetLocation
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

// AppCompatActivity, so AppCompatDelegate.setApplicationLocales applies the app language
// below Android 13 (FOX-56).
class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        startPro()
        startPush(savedInstanceState == null)
        if (savedInstanceState == null) handleLink(intent)
        startTracking(savedInstanceState)
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
                        openStation = openStation
                    )
                }
            }
        }
    }

    /** A tapped alert's station (FOX-57) or a widget's `twaqi://station` link (FOX-59), for [HomeScreen] to open. */
    private val openStation = MutableStateFlow<Int?>(null)

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        AlertNotifications.stationId(intent)?.let { openStation.value = it }
        handleLink(intent)
    }

    /**
     * FOX-57: each time the app comes to the front, catch up on alert changes and hand FCM's token
     * over (iOS does both at launch and in the foreground). The channel follows the app language,
     * and Pro changes reach the device row. A tapped alert opens its station.
     */
    private fun startPush(firstCreate: Boolean) {
        if (firstCreate) AlertNotifications.stationId(intent)?.let { openStation.value = it }
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                AlertNotifications.ensureChannel(this@MainActivity)
                PushMessaging.start(this@MainActivity)
            }
        }
        lifecycleScope.launch {
            ProGraph.repository(this@MainActivity).isPro.drop(1).collect {
                PushGraph.sync(this@MainActivity).profileChanged()
            }
        }
        // Debug builds: post a sample alert for screenshots (`--ez demo_alert true`).
        if (BuildConfig.DEBUG && firstCreate && intent.getBooleanExtra(EXTRA_DEMO_ALERT, false)) {
            AlertNotifications.show(this, AlertNotifications.demo(this))
        }
    }

    override fun onResume() {
        super.onResume()
        // FOX-59: a widget's background refresh can't read the last fix; keep it while the app is open.
        WidgetLocation.remember(this)
    }

    /**
     * FOX-95: names of stations first loaded this visit reach the launcher's shortcuts. Nothing is
     * written when they are unchanged, so this stays clear of the launcher's rate limit.
     */
    override fun onStop() {
        super.onStop()
        StationShortcuts.requestRefresh(this)
    }

    /** `twaqi://station`, `twaqi://pro` and `twaqi://air-quality` links, through the one router ([DeepLink]). */
    private fun handleLink(intent: Intent?) {
        val link = DeepLink.parse(intent?.data) ?: return
        lifecycleScope.launch {
            val isPro = ProGraph.repository(this@MainActivity).entitlement.filterNotNull().first() == Entitlement.PRO
            val known =
                (link as? DeepLink.Station)?.let { KnownStations.contains(this@MainActivity, it.stationId) } ?: true
            when (val routed = DeepLink.route(link, isPro) { known }) {
                is DeepLink.Station -> {
                    openStation.value = routed.stationId
                    Analytics.logEvent(
                        this@MainActivity,
                        Analytics.STATION_LINK_OPENED,
                        mapOf("source" to routed.source.analyticsName, "stationId" to routed.stationId.toString())
                    )
                    // FOX-95: a station's launcher shortcut or Assistant ran "Open station" (iOS `OpenStationIntent`).
                    if (routed.source == StationLinkSource.SHORTCUT) {
                        Analytics.logEvent(
                            this@MainActivity,
                            Analytics.APP_INTENT_RUN,
                            mapOf("intent" to "open_station", "station" to "station", "result" to "opened")
                        )
                    }
                }

                is DeepLink.Pro -> ProNavigation.open(this@MainActivity, routed.source)

                // FOX-95: the "What's the air?" card has its own activity.
                is DeepLink.AirQuality ->
                    startActivity(AirQualityAnswerActivity.intent(this@MainActivity, routed.stationId))

                null -> Unit
            }
        }
    }

    /**
     * FOX-60: count the app open for the review prompt, once per process start (not when a
     * language or appearance change recreates the activity). Debug builds started with
     * `--ez analytics_debug true` send events to Firebase DebugView.
     */
    private fun startTracking(savedInstanceState: Bundle?) {
        if (BuildConfig.DEBUG &&
            intent.getBooleanExtra(TrackingManager.EXTRA_ANALYTICS_DEBUG, false)
        ) {
            TrackingManager.get(this).enableDebugView()
        }
        if (savedInstanceState != null || appOpenCounted) return
        appOpenCounted = true
        val appContext = applicationContext
        ReviewPrompt.onAppOpen(this) { name, parameters -> Analytics.logEvent(appContext, name, parameters) }
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

    companion object {
        /** Debug builds: post a sample alert notification at launch (FOX-57 screenshots). */
        const val EXTRA_DEMO_ALERT = "demo_alert"

        /** This process has counted its app open. */
        private var appOpenCounted = false
    }
}

/**
 * The tabs, with the map as home (FOX-54) and Help (FOX-97), and the station screen over them.
 * [onOpenDataScreen] (debug builds only) adds a button to the data-layer check screen.
 * [openStation] carries a tapped alert's station (FOX-57) or a widget's station link (FOX-59).
 */
@Composable
fun HomeScreen(
    modifier: Modifier = Modifier,
    onOpenDataScreen: (() -> Unit)? = null,
    openStation: MutableStateFlow<Int?>? = null
) {
    val context = LocalContext.current
    val pro = remember(context) { ProGraph.repository(context) }
    val entitlement by pro.entitlement.collectAsState()
    var stationId by rememberSaveable { mutableStateOf<Int?>(null) }
    // A tapped alert (FOX-57) or a widget's station link (FOX-59) opens its station.
    LaunchedEffect(openStation) {
        openStation?.filterNotNull()?.collect {
            stationId = it
            openStation.value = null
        }
    }
    // The tabs leave composition while a station is open; this keeps their state (the selected tab,
    // the search text, the map's camera) so back returns to the tab the station was opened from.
    val tabsState = rememberSaveableStateHolder()
    val station = stationId
    // FOX-95: an opened station becomes a recent one, for the launcher's shortcuts.
    LaunchedEffect(station) { station?.let { StationShortcuts.stationOpened(context, it) } }
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
