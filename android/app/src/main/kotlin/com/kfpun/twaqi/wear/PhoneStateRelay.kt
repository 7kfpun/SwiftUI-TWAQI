package com.kfpun.twaqi.wear

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.wearable.PhoneState
import com.kfpun.twaqi.wearable.WearContract
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch

/**
 * Tells the Wear OS app (FOX-62) the reader's favourites, Pro (FOX-58) and app language (FOX-56)
 * over the Wearable Data Layer, as one [PhoneState] data item replaced on every change. The Data
 * Layer delivers it whenever the watch is next in reach, and ignores a write that changes nothing.
 *
 * Fed by `TwaqiApplication` (favourites), `ProGraph` (Pro, once the repository exists) and
 * `AppLocale` (language). Nothing is sent until the favourites are known; Pro stays "unknown"
 * (the watch keeps its last answer) until the phone has read it.
 */
object PhoneStateRelay {
    private const val TAG = "PhoneStateRelay"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val favourites = MutableStateFlow<List<Int>?>(null)
    private val isPro = MutableStateFlow<Boolean?>(null)
    private val language = MutableStateFlow<String?>(null)

    @Volatile
    private var started = false

    fun observeFavourites(context: Context, flow: Flow<List<Int>>) {
        start(context)
        scope.launch { flow.collect { favourites.value = it } }
    }

    fun observePro(context: Context, flow: Flow<Boolean>) {
        start(context)
        scope.launch { flow.collect { isPro.value = it } }
    }

    /** The app language changed, in the app or (Android 13+) in the phone's settings. */
    fun languageChanged(context: Context) {
        language.value = AppLocale.current(context).id
    }

    private fun start(context: Context) {
        if (started) return
        val app = context.applicationContext
        synchronized(this) {
            if (started) return
            started = true
        }
        languageChanged(app)
        scope.launch {
            combine(favourites.filterNotNull(), isPro, language.filterNotNull()) { ids, pro, languageId ->
                PhoneState(favouriteStationIds = ids, isPro = pro, languageId = languageId)
            }.distinctUntilChanged().collect { publish(app, it) }
        }
    }

    private fun publish(context: Context, state: PhoneState) {
        val request = PutDataMapRequest.create(WearContract.PHONE_STATE_PATH).apply {
            dataMap.putString(WearContract.KEY_PAYLOAD, state.encode())
        }.asPutDataRequest().setUrgent()
        // Phones without Wear OS (or without Play services) fail here; nothing else depends on it.
        runCatching {
            Wearable.getDataClient(context).putDataItem(request)
                .addOnFailureListener { Log.d(TAG, "No watch to tell: ${it.message}") }
        }.onFailure { Log.d(TAG, "Data Layer unavailable: ${it.message}") }
    }
}
