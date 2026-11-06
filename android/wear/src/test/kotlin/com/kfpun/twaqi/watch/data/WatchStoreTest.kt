package com.kfpun.twaqi.watch.data

import com.kfpun.twaqi.watch.MapKeyValueStore
import com.kfpun.twaqi.watch.publishTime
import com.kfpun.twaqi.watch.reading
import com.kfpun.twaqi.wearable.PhoneState
import java.time.Duration
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The watch's own state and what the phone relays (FOX-62). */
class WatchStoreTest {
    private val values = MapKeyValueStore()
    private var now = Instant.parse("2026-11-06T02:00:00Z")
    private val store = WatchStore(values) { now }

    private fun hoursAgo(hours: Long) = publishTime(now.minus(Duration.ofHours(hours)))

    @Test
    fun readingsRoundTrip() {
        val fresh = reading(aqi = 42.0, publishTime = hoursAgo(1), latitude = 25.0, longitude = 121.5)
        store.latestReading = fresh
        store.homeReading = fresh
        assertEquals(fresh, store.latestReading)
        assertEquals(fresh, store.homeReading)
        assertEquals(now, store.latestFetchedAt)
    }

    /** iOS `maxReadingAge`: past a week a cached reading is never shown, and is purged. */
    @Test
    fun weekOldReadingsAreHiddenAndPurged() {
        val old = reading(aqi = 42.0, publishTime = hoursAgo(7 * 24 + 1))
        val fresh = reading(stationId = 2, aqi = 42.0, publishTime = hoursAgo(1))
        store.latestReading = old
        store.cacheFavouriteReadings(listOf(old, fresh))
        assertNull(store.latestReading)
        assertEquals(listOf(fresh), store.favouriteReadings)

        store.purgeExpiredReadings()
        assertFalse(values.values.getValue("favouriteReadings").contains("\"stationId\":1,"))
        assertNull(values.values["latestReading"])
    }

    @Test
    fun freshFavouriteReadingsReplaceOlderOnes() {
        store.cacheFavouriteReadings(listOf(reading(stationId = 1, aqi = 10.0, publishTime = hoursAgo(2))))
        store.cacheFavouriteReadings(listOf(reading(stationId = 1, aqi = 20.0, publishTime = hoursAgo(1))))
        assertEquals(listOf(20.0), store.favouriteReadings.map { it.aqi })
    }

    @Test
    fun thePhoneStateIsAppliedAndReportsWhatChanged() {
        val first = store.apply(PhoneState(listOf(126, 85), isPro = true, languageId = "zh-Hant"))
        assertEquals(WatchStore.PhoneStateChange(favourites = true, pro = true, language = true), first)
        assertEquals(listOf(126, 85), store.favouriteStationIds)
        assertTrue(store.isProUnlocked)
        assertEquals("zh-Hant", store.languageId)

        assertFalse(store.apply(PhoneState(listOf(126, 85), isPro = true, languageId = "zh-Hant")).any)
    }

    /** Before the phone has read Pro from Play it sends no answer; the watch keeps its own. */
    @Test
    fun anUnknownProKeepsTheLastAnswer() {
        store.apply(PhoneState(emptyList(), isPro = true, languageId = "system"))
        val change = store.apply(PhoneState(emptyList(), isPro = null, languageId = "system"))
        assertFalse(change.pro)
        assertTrue(store.isProUnlocked)
    }

    @Test
    fun complicationConfigIsKeptPerComplication() {
        store.setComplicationConfig(7, "pm25", "face")
        assertEquals("pm25" to "face", store.complicationConfig(7))
        assertEquals(null to null, store.complicationConfig(8))
        store.removeComplicationConfig(7)
        assertEquals(null to null, store.complicationConfig(7))
    }

    @Test
    fun everyWriteTicksTheChanges() {
        val before = store.changes.value
        store.pinnedStationId = 126
        assertEquals(126, store.pinnedStationId)
        assertTrue(store.changes.value > before)
    }
}
