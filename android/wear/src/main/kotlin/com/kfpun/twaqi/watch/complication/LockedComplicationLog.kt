package com.kfpun.twaqi.watch.complication

import com.kfpun.twaqi.watch.data.WatchStore
import com.kfpun.twaqi.wearable.LockedComplicationHit
import com.kfpun.twaqi.wearable.LockedComplicationPayload

/**
 * Gets locked-complication hits from the watch to Firebase, which only the phone has (iOS
 * `LockedComplicationLog`, FOX-63, FOX-44).
 *
 * The complication queues each hit ([record]); `PhoneRelay` sends the queue over the Data Layer
 * ([drain]) and the phone logs it. A setup counts once: complications update every 30 minutes,
 * and counting each update would measure how long a lock stayed on the face, not how many
 * readers met one.
 */
class LockedComplicationLog(private val store: WatchStore) {
    /** Queues [hit] unless this setup was counted before. Returns whether it was queued. */
    @Synchronized
    fun record(hit: LockedComplicationHit): Boolean {
        val counted = counted()
        val key = "${hit.style}|${hit.family}|${hit.index}"
        if (key in counted) return false
        val queue = pending()
        if (queue.size >= MAX_PENDING) return false
        save(queue + hit)
        store.setRaw(COUNTED, (counted + key).sorted().joinToString("\n"))
        return true
    }

    /** Hits not sent yet. */
    fun pending(): List<LockedComplicationHit> = LockedComplicationPayload.decode(store.raw(PENDING))

    /** Returns the queued hits and empties the queue. */
    @Synchronized
    fun drain(): List<LockedComplicationHit> {
        val queue = pending()
        if (queue.isNotEmpty()) store.setRaw(PENDING, null)
        return queue
    }

    /** Puts back hits that couldn't be sent, ahead of any queued since. They stay counted. */
    @Synchronized
    fun requeue(hits: List<LockedComplicationHit>) {
        if (hits.isEmpty()) return
        save((hits + pending()).distinct().take(MAX_PENDING))
    }

    private fun counted(): Set<String> = store.raw(COUNTED)?.split('\n')?.filter { it.isNotEmpty() }?.toSet().orEmpty()

    private fun save(queue: List<LockedComplicationHit>) {
        store.setRaw(PENDING, LockedComplicationPayload.encode(queue))
    }

    companion object {
        /** Bounded: style × type × index is well under this, and the queue drains on every send. */
        const val MAX_PENDING = 100

        private const val PENDING = "lockedComplicationPending"
        private const val COUNTED = "lockedComplicationCounted"
    }
}
