package com.kfpun.twaqi.watch.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.kfpun.twaqi.watch.data.WatchLocale
import com.kfpun.twaqi.watch.data.WatchStore
import com.kfpun.twaqi.watch.relay.PhoneRelay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/** The watch app (iOS `TWAQIWatchApp`): the reading, the station picker and the Pro paywall. */
class WatchActivity : ComponentActivity() {
    private val model: WatchModel by viewModels()

    /** Set by a locked complication or tile: open on the paywall. */
    private val openPaywall = MutableStateFlow(false)

    private val askLocation = registerForActivityResult(ActivityResultContracts.RequestPermission()) { model.refresh() }

    /** The phone's chosen language when it has relayed one, else the watch's (FOX-56). */
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(WatchLocale.wrap(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val store = WatchStore.get(this)
        // Readings cached more than a week ago are never shown; drop them.
        store.purgeExpiredReadings()
        openPaywall.value = intent.getBooleanExtra(EXTRA_PAYWALL, false)

        setContent {
            WatchApp(model = model, openPaywall = openPaywall)
        }

        // A language relayed from the phone redraws everything in it.
        lifecycleScope.launch {
            store.changes.map { store.languageId }.distinctUntilChanged().drop(1).collect { recreate() }
        }
        // Every time the app comes to the front, as iOS does on `scenePhase == .active`.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                PhoneRelay.flush(this@WatchActivity)
                model.checkPro()
                model.refresh()
            }
        }

        // Home asks for a location once; a pinned station never needs it.
        if (savedInstanceState == null && store.pinnedStationId == null && !store.askedForLocation &&
            !Locator(this).hasPermission()
        ) {
            store.askedForLocation = true
            askLocation.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra(EXTRA_PAYWALL, false)) openPaywall.value = true
    }

    companion object {
        const val EXTRA_PAYWALL = "com.kfpun.twaqi.watch.extra.PAYWALL"

        /** For the complication's tap; `singleTop` in the manifest brings a running app forward. */
        fun intent(context: Context, openPaywall: Boolean = false): Intent =
            Intent(context, WatchActivity::class.java).putExtra(EXTRA_PAYWALL, openPaywall)
    }
}
