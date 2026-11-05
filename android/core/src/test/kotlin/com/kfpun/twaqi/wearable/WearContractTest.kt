package com.kfpun.twaqi.wearable

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The phone ↔ watch payloads (FOX-62): what one side writes, the other reads back. */
class WearContractTest {
    private val circular = LockedComplicationHit(style = "labelled", family = "RANGED_VALUE", index = "aqi")

    @Test
    fun phoneStateRoundTrips() {
        val state = PhoneState(favouriteStationIds = listOf(126, 85, 3), isPro = true, languageId = "zh-Hant")
        assertEquals(state, PhoneState.decode(state.encode()))
    }

    /** Before the phone has read Pro from Play, the watch must keep its own last answer. */
    @Test
    fun unknownProStaysUnknown() {
        val state = PhoneState(favouriteStationIds = emptyList(), isPro = null, languageId = "system")
        assertNull(PhoneState.decode(state.encode())?.isPro)
    }

    @Test
    fun badPhoneStatesAreIgnoredOrRepaired() {
        assertNull(PhoneState.decode(null))
        assertNull(PhoneState.decode("not json"))
        assertNull(PhoneState.decode("[1, 2]"))
        val repaired = PhoneState.decode("""{"favouriteStationIds": [1, "x", 1, 2.5, 3]}""")
        assertEquals(listOf(1, 3), repaired?.favouriteStationIds)
        assertEquals(PhoneState.SYSTEM_LANGUAGE, repaired?.languageId)
    }

    /** iOS `testThePayloadSurvivesTheTrip`. */
    @Test
    fun lockedHitsSurviveTheTrip() {
        val hits = listOf(circular, LockedComplicationHit("numberOnly", "SHORT_TEXT", "o3"))
        assertEquals(hits, LockedComplicationPayload.decode(LockedComplicationPayload.encode(hits)))
    }

    /** iOS `testOtherPayloadsAreIgnored`. */
    @Test
    fun otherPayloadsAreIgnored() {
        assertEquals(emptyList<LockedComplicationHit>(), LockedComplicationPayload.decode(null))
        assertEquals(emptyList<LockedComplicationHit>(), LockedComplicationPayload.decode("{}"))
        assertEquals(emptyList<LockedComplicationHit>(), LockedComplicationPayload.decode("""{"other": 1}"""))
        assertEquals(
            emptyList<LockedComplicationHit>(),
            LockedComplicationPayload.decode("""{"${LockedComplicationPayload.KEY}": [{"style": "face"}]}""")
        )
    }

    @Test
    fun theEventCarriesOnlyStyleFamilyAndIndex() {
        assertEquals(mapOf("style" to "labelled", "family" to "RANGED_VALUE", "index" to "aqi"), circular.parameters)
    }
}
