package com.kfpun.twaqi.wear

import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.wearable.LockedComplicationHit
import com.kfpun.twaqi.wearable.LockedComplicationPayload
import org.junit.Assert.assertEquals
import org.junit.Test

/** The phone side of the watch's locked-complication event (iOS `LockedComplicationLogTests`, FOX-62). */
class WatchEventRelayTest {
    /** iOS `testThePhoneLogsEachHitAsTheFirebaseEvent`: one event per hit, style, family and index only. */
    @Test
    fun thePhoneLogsEachHitAsTheFirebaseEvent() {
        val logged = mutableListOf<Pair<String, Map<String, Any>>>()
        val payload = LockedComplicationPayload.encode(listOf(LockedComplicationHit("labelled", "RANGED_VALUE", "aqi")))
        WatchEventRelay.logEvents(payload) { name, parameters -> logged += name to parameters }

        assertEquals(1, logged.size)
        assertEquals(Analytics.WATCH_COMPLICATION_LOCKED, logged.first().first)
        assertEquals(mapOf("style" to "labelled", "family" to "RANGED_VALUE", "index" to "aqi"), logged.first().second)
        assertEquals("watch_complication_locked", Analytics.WATCH_COMPLICATION_LOCKED)
    }

    @Test
    fun otherPayloadsLogNothing() {
        var count = 0
        WatchEventRelay.logEvents("""{"other": 1}""") { _, _ -> count++ }
        WatchEventRelay.logEvents(null) { _, _ -> count++ }
        assertEquals(0, count)
    }
}
