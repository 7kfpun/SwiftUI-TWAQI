package com.kfpun.twaqi.watch.complication

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `ComplicationStyleTests`: the face is free without its number, every other style needs Pro (FOX-63). */
class ComplicationStyleTest {
    @Test
    fun onlyTheFaceIsFree() {
        assertEquals(listOf(ComplicationStyle.FACE), ComplicationStyle.entries.filterNot { it.isPro })
    }

    @Test
    fun proUnlocksEveryStyleWithItsNumber() {
        for (style in ComplicationStyle.entries) {
            val access = ComplicationAccess.of(style, isPro = true)
            assertEquals("$style", ComplicationAccess.FULL, access)
            assertTrue("$style", access.showsNumber)
        }
    }

    @Test
    fun freeFaceShowsItsReadingWithoutTheNumber() {
        val access = ComplicationAccess.of(ComplicationStyle.FACE, isPro = false)
        assertEquals(ComplicationAccess.FACE_ONLY, access)
        assertFalse(access.showsNumber)
    }

    @Test
    fun freeReaderSeesALockOnEveryProStyle() {
        for (style in listOf(ComplicationStyle.LABELLED, ComplicationStyle.NUMBER_ONLY, ComplicationStyle.STATUS)) {
            val access = ComplicationAccess.of(style, isPro = false)
            assertEquals("$style", ComplicationAccess.LOCKED, access)
            assertFalse("$style", access.showsNumber)
        }
    }

    /** Saved complications store the id; renaming one would reset every complication already on a face. */
    @Test
    fun idsAreStableAndMatchIos() {
        assertEquals(listOf("labelled", "numberOnly", "face", "status"), ComplicationStyle.entries.map { it.id })
        assertEquals(ComplicationStyle.LABELLED, ComplicationStyle.fromId(null))
        assertEquals(ComplicationStyle.STATUS, ComplicationStyle.fromId("status"))
    }
}
