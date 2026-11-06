package com.kfpun.twaqi.data

import com.kfpun.twaqi.data.favourites.FavouriteAlertsGateway
import com.kfpun.twaqi.data.favourites.FavouritesRepository
import com.kfpun.twaqi.data.favourites.FavouritesStore
import com.kfpun.twaqi.data.favourites.SharedPreferencesFavouritesStore
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FavouritesRepositoryTest {
    /** Stands in for shared preferences: what one repository writes, the next one reads. */
    class MemoryStore(var saved: List<Int>? = null) : FavouritesStore {
        var writes = 0
        override fun read(): List<Int>? = saved

        override fun write(stationIds: List<Int>) {
            writes += 1
            saved = stationIds
        }
    }

    class FakeAlerts(on: Set<Int> = emptySet()) : FavouriteAlertsGateway {
        override val alertedStationIds = MutableStateFlow(on)
        val cleared = mutableListOf<Int>()

        /** Like iOS `FavouriteAlerts.clear`: nothing to do when they are off already. */
        override fun clear(stationId: Int) {
            if (stationId !in alertedStationIds.value) return
            cleared += stationId
            alertedStationIds.value -= stationId
        }

        /** Why a new favourite's alerts stay off, or null to switch them on. */
        var hint: com.kfpun.twaqi.data.favourites.FavouriteAlertsHint? = null
        val enabled = mutableListOf<Int>()

        override fun enableForNewFavourite(
            stationId: Int,
            isStillFavourite: () -> Boolean
        ): com.kfpun.twaqi.data.favourites.FavouriteAlertsHint? {
            if (hint == null && isStillFavourite()) {
                enabled += stationId
                alertedStationIds.value += stationId
            }
            return hint
        }
    }

    @Test
    fun newInstallStartsWithTheDefaultFavourite() {
        assertEquals(listOf(126), FavouritesRepository(MemoryStore()).favourites.value)
    }

    @Test
    fun anEmptyListTheReaderLeftStaysEmpty() {
        assertEquals(emptyList<Int>(), FavouritesRepository(MemoryStore(emptyList())).favourites.value)
    }

    @Test
    fun addAppendsOnceAndSaves() {
        val store = MemoryStore(listOf(1))
        val repository = FavouritesRepository(store)
        assertTrue(repository.add(2))
        assertFalse(repository.add(2))
        assertEquals(listOf(1, 2), repository.favourites.value)
        assertEquals(listOf(1, 2), store.saved)
        assertTrue(repository.contains(2))
    }

    @Test
    fun favouritesSurviveARestart() {
        val store = MemoryStore(emptyList())
        FavouritesRepository(store).apply {
            add(5)
            add(7)
            add(9)
            move(2, 0)
            remove(7)
        }
        assertEquals(listOf(9, 5), FavouritesRepository(store).favourites.value)
    }

    @Test
    fun removeTakesStationsOutAndClearsTheirAlerts() {
        val alerts = FakeAlerts(setOf(2))
        val repository = FavouritesRepository(MemoryStore(listOf(1, 2, 3)), alerts)
        assertEquals(listOf(2, 3), repository.remove(listOf(2, 3, 99)))
        assertEquals(listOf(1), repository.favourites.value)
        // The removed station with alerts has them turned off.
        assertEquals(listOf(2), alerts.cleared)
        assertTrue(alerts.alertedStationIds.value.isEmpty())
    }

    @Test
    fun removingANonFavouriteChangesNothing() {
        val store = MemoryStore(listOf(1))
        val repository = FavouritesRepository(store)
        assertFalse(repository.remove(42))
        assertEquals(0, store.writes)
    }

    @Test
    fun removalNeedsConfirmationOnlyWhenAnAlertIsOn() {
        val repository = FavouritesRepository(MemoryStore(listOf(1, 2)), FakeAlerts(setOf(2)))
        assertFalse(repository.needsConfirmation(listOf(1)))
        assertTrue(repository.needsConfirmation(listOf(1, 2)))
    }

    @Test
    fun reorderKeepsUnlistedStationsAfterTheRestAndLeavesAlertsAlone() {
        val alerts = FakeAlerts(setOf(1, 3))
        val store = MemoryStore(listOf(1, 2, 3, 4))
        val repository = FavouritesRepository(store, alerts)
        // The list shows 3, 1, 2 (4 has no reading yet).
        repository.reorder(listOf(3, 1, 2))
        assertEquals(listOf(3, 1, 2, 4), repository.favourites.value)
        assertEquals(listOf(3, 1, 2, 4), store.saved)
        assertTrue(alerts.cleared.isEmpty())
        assertEquals(setOf(1, 3), alerts.alertedStationIds.value)
    }

    @Test
    fun reorderIgnoresIdsThatAreNotFavourites() {
        val repository = FavouritesRepository(MemoryStore(listOf(1, 2)))
        repository.reorder(listOf(2, 99, 1))
        assertEquals(listOf(2, 1), repository.favourites.value)
    }

    @Test
    fun moveOutOfRangeDoesNothing() {
        val store = MemoryStore(listOf(1, 2))
        val repository = FavouritesRepository(store)
        repository.move(0, 5)
        repository.move(1, 1)
        assertEquals(listOf(1, 2), repository.favourites.value)
        assertEquals(0, store.writes)
    }

    @Test
    fun storedTextRoundTripsAndToleratesJunk() {
        assertEquals("126,85", SharedPreferencesFavouritesStore.encode(listOf(126, 85)))
        assertEquals(listOf(126, 85), SharedPreferencesFavouritesStore.decode("126,85"))
        assertEquals(listOf(1, 3), SharedPreferencesFavouritesStore.decode("1, x,3,1,"))
        assertEquals(emptyList<Int>(), SharedPreferencesFavouritesStore.decode(""))
    }
}
