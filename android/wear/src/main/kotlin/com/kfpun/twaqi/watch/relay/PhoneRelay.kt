package com.kfpun.twaqi.watch.relay

import android.content.Context
import android.net.Uri
import android.util.Log
import com.google.android.gms.tasks.Task
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import com.kfpun.twaqi.watch.WatchSurfaces
import com.kfpun.twaqi.watch.complication.LockedComplicationLog
import com.kfpun.twaqi.watch.data.WatchStore
import com.kfpun.twaqi.wearable.LockedComplicationPayload
import com.kfpun.twaqi.wearable.PhoneState
import com.kfpun.twaqi.wearable.WearContract
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * The watch's side of the Data Layer (iOS `PhoneRelay`): reads the phone's favourites, Pro and
 * language ([PhoneState]), and sends the complication's locked-style hits to the phone, which logs
 * them to Firebase. The watch has no Firebase.
 */
object PhoneRelay {
    private const val TAG = "PhoneRelay"

    /** Saves a phone state and redraws whatever depends on what changed. */
    fun apply(context: Context, state: PhoneState) {
        val change = WatchStore.get(context).apply(state)
        // The complication and tile lock or unlock with Pro, and speak the app's language.
        if (change.pro || change.language) WatchSurfaces.requestUpdate(context)
    }

    /**
     * Reads the phone state the Data Layer already holds, e.g. for "Restore purchase" or at start.
     * Returns whether there was one.
     */
    suspend fun refreshFromPhone(context: Context): Boolean {
        val uri = Uri.Builder().scheme("wear").path(WearContract.PHONE_STATE_PATH).build()
        val items = runCatching { Wearable.getDataClient(context).getDataItems(uri).await() }
            .onFailure { Log.d(TAG, "Data Layer unavailable: ${it.message}") }
            .getOrNull() ?: return false
        val states = try {
            items.mapNotNull {
                PhoneState.decode(DataMapItem.fromDataItem(it).dataMap.getString(WearContract.KEY_PAYLOAD))
            }
        } finally {
            items.release()
        }
        states.lastOrNull()?.let { apply(context, it) } ?: return false
        return true
    }

    /**
     * Hands the queued locked-complication hits to the Data Layer, which keeps them until the phone
     * has them, also when the phone app isn't running (iOS `transferUserInfo`). Nothing is lost when
     * the Data Layer can't be reached: the hits go back in the queue.
     */
    fun flush(context: Context) {
        val log = LockedComplicationLog(WatchStore.get(context))
        val hits = log.drain()
        if (hits.isEmpty()) return
        val request = PutDataMapRequest.create("${WearContract.WATCH_EVENTS_PATH}/${UUID.randomUUID()}").apply {
            dataMap.putString(WearContract.KEY_PAYLOAD, LockedComplicationPayload.encode(hits))
        }.asPutDataRequest().setUrgent()
        runCatching {
            Wearable.getDataClient(context).putDataItem(request).addOnFailureListener {
                Log.d(TAG, "Kept for later: ${it.message}")
                log.requeue(hits)
            }
        }.onFailure {
            Log.d(TAG, "Data Layer unavailable: ${it.message}")
            log.requeue(hits)
        }
    }
}

/** Started by Play services when the phone's state changes, also when the watch app isn't running. */
class PhoneStateListenerService : WearableListenerService() {
    override fun onDataChanged(dataEvents: DataEventBuffer) {
        for (event in dataEvents) {
            if (event.type != DataEvent.TYPE_CHANGED) continue
            val item = event.dataItem
            if (item.uri.path != WearContract.PHONE_STATE_PATH) continue
            val state = PhoneState.decode(DataMapItem.fromDataItem(item).dataMap.getString(WearContract.KEY_PAYLOAD))
            if (state != null) PhoneRelay.apply(this, state)
        }
    }
}

private suspend fun <T> Task<T>.await(): T = suspendCancellableCoroutine { continuation ->
    addOnSuccessListener { continuation.resume(it) }
    addOnFailureListener { continuation.resumeWithException(it) }
}
