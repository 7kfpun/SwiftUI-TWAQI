package com.kfpun.twaqi.watch.complication

import com.kfpun.twaqi.watch.MapKeyValueStore
import com.kfpun.twaqi.watch.data.WatchStore
import com.kfpun.twaqi.wearable.LockedComplicationHit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * iOS `LockedComplicationLogTests`: a free reader's locked complication reaches Firebase once per
 * setup, by way of the phone (FOX-63, FOX-44). The payload and the phone's side are tested in
 * `:core` (`WearContractTest`) and `:app` (`WatchEventRelayTest`).
 */
class LockedComplicationLogTest {
    private val log = LockedComplicationLog(WatchStore(MapKeyValueStore()))
    private val circular = LockedComplicationHit(style = "labelled", family = "RANGED_VALUE", index = "aqi")

    /** Complications update every 30 minutes; only the first one counts. */
    @Test
    fun aSetupCountsOnceAcrossUpdates() {
        assertTrue(log.record(circular))
        assertFalse(log.record(circular))
        assertEquals(listOf(circular), log.pending())
    }

    /** Still once after the queue was sent: sending isn't a new encounter. */
    @Test
    fun aSentSetupIsNotCountedAgain() {
        log.record(circular)
        assertEquals(listOf(circular), log.drain())
        assertFalse(log.record(circular))
        assertEquals(emptyList<LockedComplicationHit>(), log.drain())
    }

    @Test
    fun eachStyleFamilyAndIndexCountsSeparately() {
        val hits = listOf(
            circular,
            LockedComplicationHit("status", "RANGED_VALUE", "aqi"),
            LockedComplicationHit("labelled", "SHORT_TEXT", "aqi"),
            LockedComplicationHit("labelled", "RANGED_VALUE", "pm25")
        )
        hits.forEach { assertTrue(log.record(it)) }
        assertEquals(hits, log.drain())
        assertEquals(emptyList<LockedComplicationHit>(), log.pending())
    }

    @Test
    fun theQueueIsBounded() {
        repeat(LockedComplicationLog.MAX_PENDING + 5) { number ->
            log.record(LockedComplicationHit("labelled", "RANGED_VALUE", "$number"))
        }
        assertEquals(LockedComplicationLog.MAX_PENDING, log.pending().size)
    }

    /** A batch the Data Layer couldn't take goes back in the queue, still counted once. */
    @Test
    fun anUnsentBatchIsRequeuedWithoutCountingAgain() {
        log.record(circular)
        val sent = log.drain()
        log.record(LockedComplicationHit("status", "SHORT_TEXT", "o3"))
        log.requeue(sent)
        assertEquals(listOf(circular, LockedComplicationHit("status", "SHORT_TEXT", "o3")), log.pending())
        assertFalse(log.record(circular))
    }
}
