package com.kfpun.twaqi

import android.app.Application
import android.content.res.Configuration
import android.util.Log
import com.kfpun.twaqi.data.AppContainer
import com.kfpun.twaqi.pro.ProGraph
import com.kfpun.twaqi.settings.AppAppearanceStore
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
        container = AppContainer(this)
        // FOX-59: widgets redraw when favourites or Pro change, and refresh while any is placed.
        WidgetUpdater.observe(this, container.favourites.favourites, ProGraph.repository(this).isPro)
        // iOS purges at launch too (OfflineCacheRetention.purgeInBackground).
        scope.launch {
            val removed = container.purgeExpiredCaches()
            if (removed.isNotEmpty()) Log.i("OfflineCacheRetention", "purged ${removed.map { it.name }}")
        }
    }

    /** Android 13+: the app language changed in the phone's settings; widgets follow it (FOX-56). */
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        WidgetUpdater.requestRedrawAll(this)
    }
}
