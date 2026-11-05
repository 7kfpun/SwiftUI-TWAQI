package com.kfpun.twaqi

import android.app.Application
import android.util.Log
import com.kfpun.twaqi.data.AppContainer
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
        container = AppContainer(this)
        // iOS purges at launch too (OfflineCacheRetention.purgeInBackground).
        scope.launch {
            val removed = container.purgeExpiredCaches()
            if (removed.isNotEmpty()) Log.i("OfflineCacheRetention", "purged ${removed.map { it.name }}")
        }
    }
}
