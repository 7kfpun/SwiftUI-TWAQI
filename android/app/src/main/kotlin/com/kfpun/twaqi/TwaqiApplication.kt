package com.kfpun.twaqi

import android.app.Application
import android.content.res.Configuration
import android.util.Log
import com.kfpun.twaqi.analytics.TrackingManager
import com.kfpun.twaqi.data.AppContainer
import com.kfpun.twaqi.push.AlertNotifications
import com.kfpun.twaqi.settings.AppAppearanceStore
import com.kfpun.twaqi.shortcuts.StationShortcuts
import com.kfpun.twaqi.widget.WidgetUpdater
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class TwaqiApplication : Application() {
    lateinit var container: AppContainer
        private set

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()
        // Help › Appearance (FOX-97), before any activity (the Pro screen can be the first one).
        AppAppearanceStore.applyStored(this)
        // Before anything is logged: debug builds and opted-out installs don't report (FOX-60).
        TrackingManager.get(this).applyAtLaunch()
        container = AppContainer(this)
        // FOX-59: widgets redraw when favourites change (Pro: ProGraph), and refresh while any is placed.
        WidgetUpdater.observeFavourites(this, container.favourites.favourites)
        WidgetUpdater.redrawIfLanguageChanged(this)
        // FOX-95: the launcher's station shortcuts follow the favourites (and are rebuilt at start).
        StationShortcuts.observe(this, container.favourites.favourites)
        // Push alerts (FOX-57): the channel in the app language, before any alert arrives.
        AlertNotifications.ensureChannel(this)
        // iOS purges at launch too (OfflineCacheRetention.purgeInBackground).
        scope.launch {
            val removed = container.purgeExpiredCaches()
            if (removed.isNotEmpty()) Log.i("OfflineCacheRetention", "purged ${removed.map { it.name }}")
        }
    }

    /** Android 13+: the app language changed in the phone's settings; widgets and shortcuts follow it (FOX-56). */
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        WidgetUpdater.requestRedrawAll(this)
        StationShortcuts.requestRefresh(this)
    }
}
