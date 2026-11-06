package com.kfpun.twaqi.wear

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.wearable.LockedComplicationPayload
import com.kfpun.twaqi.wearable.WearContract

/**
 * Logs to Firebase what the watch sends over the Data Layer (iOS `WatchEventRelay`): the watch
 * has no Firebase of its own. Today that is a free reader's complication set to a Pro style
 * (`LockedComplicationLog` on the watch, FOX-63), as `watch_complication_locked`.
 */
object WatchEventRelay {
    /** Logs every hit in [payload]; anything else in it is ignored. */
    fun logEvents(payload: String?, log: (String, Map<String, Any>) -> Unit) {
        for (hit in LockedComplicationPayload.decode(payload)) {
            log(Analytics.WATCH_COMPLICATION_LOCKED, hit.parameters)
        }
    }
}

/**
 * Started by Play services when the watch writes under [WearContract.WATCH_EVENTS_PATH], also when
 * the app isn't running. Each batch is logged once and then deleted, so it isn't delivered again.
 */
class WatchEventListenerService : WearableListenerService() {
    override fun onDataChanged(dataEvents: DataEventBuffer) {
        val client = Wearable.getDataClient(this)
        for (event in dataEvents) {
            if (event.type != DataEvent.TYPE_CHANGED) continue
            val item = event.dataItem
            if (item.uri.path?.startsWith(WearContract.WATCH_EVENTS_PATH) != true) continue
            val payload = DataMapItem.fromDataItem(item).dataMap.getString(WearContract.KEY_PAYLOAD)
            WatchEventRelay.logEvents(payload) { name, parameters -> Analytics.logEvent(this, name, parameters) }
            client.deleteDataItems(item.uri)
        }
    }
}
