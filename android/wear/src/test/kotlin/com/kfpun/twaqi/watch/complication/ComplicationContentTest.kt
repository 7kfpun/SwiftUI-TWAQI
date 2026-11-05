package com.kfpun.twaqi.watch.complication

import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirLevel
import com.kfpun.twaqi.watch.reading
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** What each complication slot draws for each style and access (iOS `ReadingWidgetView`, FOX-63). */
class ComplicationContentTest {
    private val words = object : ComplicationWords {
        override fun status(level: AirLevel) = level.key
        override val proLocked = "Pro · Open the app to unlock"
        override val noStation = "Open the app to choose a station"
    }

    /** AQI 42 (good), PM2.5 60 (unhealthy). */
    private val songshan = reading(aqi = 42.0, pm25 = 60.0).copy(name = "Songshan", nameLocal = "松山")

    private fun build(
        family: ComplicationFamily,
        style: ComplicationStyle,
        access: ComplicationAccess = ComplicationAccess.FULL,
        type: AirIndexType = AirIndexType.AQI,
        chinese: Boolean = false
    ) = ComplicationContent.build(family, songshan, type, style, access, words, chinese)

    private fun ComplicationContent.allText() = listOfNotNull(text, title, description).joinToString(" | ")

    @Test
    fun labelledShowsTheIndexAndTheNumber() {
        val ranged = build(ComplicationFamily.RANGED, ComplicationStyle.LABELLED)
        assertEquals("42", ranged.text)
        assertEquals("AQI", ranged.title)
        assertEquals(1f / 6, ranged.progress)

        val long = build(ComplicationFamily.LONG, ComplicationStyle.LABELLED, type = AirIndexType.PM25)
        assertEquals("unhealthy · PM2.5 60 μg/m3", long.text)
        assertEquals("Songshan", long.title)
        assertEquals(AirLevel.UNHEALTHY, long.face)
    }

    @Test
    fun numberOnlyDropsTheLabel() {
        val short = build(ComplicationFamily.SHORT, ComplicationStyle.NUMBER_ONLY)
        assertEquals("42", short.text)
        assertNull(short.title)
    }

    /** The free face (FOX-63): its level and face, never the number anywhere, read aloud included. */
    @Test
    fun theFreeFaceNeverShowsTheNumber() {
        for (family in ComplicationFamily.entries) {
            val content = build(family, ComplicationStyle.FACE, ComplicationAccess.FACE_ONLY)
            assertFalse("$family: ${content.allText()}", content.allText().contains("42"))
            assertFalse(content.locked)
            assertEquals("$family", AirLevel.GOOD, content.level)
        }
        // Without the number, the short slot names the index so a PM2.5 face isn't read as the AQI.
        assertEquals(
            "PM2.5",
            build(
                ComplicationFamily.SHORT,
                ComplicationStyle.FACE,
                ComplicationAccess.FACE_ONLY,
                AirIndexType.PM25
            ).text
        )
    }

    @Test
    fun proFaceAddsTheNumberWhereItFits() {
        assertEquals("42", build(ComplicationFamily.SHORT, ComplicationStyle.FACE).text)
        assertEquals(AirLevel.GOOD, build(ComplicationFamily.SHORT, ComplicationStyle.FACE).face)
        assertEquals("", build(ComplicationFamily.RANGED, ComplicationStyle.FACE).text)
    }

    @Test
    fun statusShowsTheLevelInWordsAndNamesTheIndex() {
        val long = build(ComplicationFamily.LONG, ComplicationStyle.STATUS, type = AirIndexType.PM25)
        assertEquals("unhealthy", long.text)
        assertEquals("PM2.5 · Songshan", long.title)
        assertFalse(long.allText().contains("60 "))
    }

    /** A Pro style without Pro: a lock reading "Pro", and nothing of the reading. */
    @Test
    fun aLockedStyleShowsNoReading() {
        for (family in ComplicationFamily.entries) {
            val content = build(family, ComplicationStyle.LABELLED, ComplicationAccess.LOCKED)
            assertTrue(content.locked)
            assertEquals(ComplicationIcon.LOCK, content.icon)
            assertNull(content.level)
            assertFalse(
                "$family: ${content.allText()}",
                content.allText().contains("42") || content.allText().contains("Songshan")
            )
        }
        assertEquals(
            "AQI · Pro",
            build(ComplicationFamily.LONG, ComplicationStyle.STATUS, ComplicationAccess.LOCKED).title
        )
    }

    @Test
    fun noStationYetAsksToOpenTheApp() {
        val empty = ComplicationContent.build(
            ComplicationFamily.LONG,
            null,
            AirIndexType.AQI,
            ComplicationStyle.LABELLED,
            ComplicationAccess.FULL,
            words,
            false
        )
        assertEquals(words.noStation, empty.text)
        val short = ComplicationContent.build(
            ComplicationFamily.SHORT,
            null,
            AirIndexType.AQI,
            ComplicationStyle.LABELLED,
            ComplicationAccess.FULL,
            words,
            false
        )
        assertEquals("AQI --", short.text)
    }

    @Test
    fun theStationIsNamedInTheWatchLanguage() {
        assertEquals("松山", build(ComplicationFamily.LONG, ComplicationStyle.LABELLED, chinese = true).title)
    }

    @Test
    fun theRingFillsByLevel() {
        assertEquals(
            listOf(1f / 6, 2f / 6, 3f / 6, 4f / 6, 5f / 6, 1f),
            AirLevel.showAllCases.map(ComplicationContent::bandProgress)
        )
        assertEquals(0f, ComplicationContent.bandProgress(AirLevel.UNKNOWN))
    }
}
