package com.kfpun.twaqi.ui

import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.data.FavouritesRepositoryTest.FakeAlerts
import com.kfpun.twaqi.data.FavouritesRepositoryTest.MemoryStore
import com.kfpun.twaqi.data.favourites.FavouritesRepository
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.repository.DataResult
import com.kfpun.twaqi.ui.favourites.FavouriteReadings
import com.kfpun.twaqi.ui.favourites.FavouritesViewModel
import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** iOS `FavouriteListViewModel` and the list's remove and move actions. */
@OptIn(ExperimentalCoroutinesApi::class)
class FavouritesViewModelTest {
    private val events = mutableListOf<Pair<String, Map<String, String>>>()

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private class FakeReadings(
        var saved: List<Pollutant> = emptyList(),
        var current: DataResult<List<Pollutant>> = DataResult.Failed(IOException("offline"))
    ) : FavouriteReadings {
        override suspend fun saved(stationIds: List<Int>) = saved.filter { it.stationId in stationIds }
        override suspend fun current(stationIds: List<Int>) = current
    }

    private fun model(readings: FakeReadings, favourites: FavouritesRepository) =
        FavouritesViewModel(favourites, readings) { name, params -> events += name to params }.also { it.refresh() }

    @Test
    fun readingsAreListedInTheReadersOrder() {
        val favourites = FavouritesRepository(MemoryStore(listOf(3, 1, 2)))
        val vm = model(FakeReadings(current = DataResult.Fresh(listOf(p(1), p(2), p(3)), Instant.EPOCH)), favourites)
        assertEquals(listOf(3, 1, 2), vm.uiState.value.pollutants.map { it.stationId })
        assertFalse(vm.uiState.value.isShowingLastGood)
    }

    @Test
    fun offlineShowsTheSavedReadingsAsStale() {
        val favourites = FavouritesRepository(MemoryStore(listOf(1, 2)))
        val vm = model(FakeReadings(saved = listOf(p(2))), favourites)
        assertEquals(listOf(2), vm.uiState.value.pollutants.map { it.stationId })
        assertTrue(vm.uiState.value.isShowingLastGood)
        assertFalse(vm.uiState.value.loadFailed)
    }

    @Test
    fun offlineWithNothingSavedFails() {
        val vm = model(FakeReadings(), FavouritesRepository(MemoryStore(listOf(1))))
        assertTrue(vm.uiState.value.pollutants.isEmpty())
        assertTrue(vm.uiState.value.loadFailed)
    }

    @Test
    fun movingSavesTheOrderAndLeavesAlertsAlone() {
        val alerts = FakeAlerts(setOf(1))
        val favourites = FavouritesRepository(MemoryStore(listOf(1, 2, 3, 4)), alerts)
        // 4 has no reading, so isn't listed.
        val vm = model(FakeReadings(current = DataResult.Fresh(listOf(p(1), p(2), p(3)), Instant.EPOCH)), favourites)
        vm.move(0, 2)
        assertEquals(listOf(2, 3, 1), vm.uiState.value.pollutants.map { it.stationId })
        assertEquals(listOf(2, 3, 1, 4), favourites.favourites.value)
        assertTrue(alerts.cleared.isEmpty())
        assertEquals(1, events.count { it.first == Analytics.FAVOURITE_STATION_REORDERED })
    }

    @Test
    fun removingAStationWithAlertsWaitsOnTheReader() {
        val alerts = FakeAlerts(setOf(2))
        val favourites = FavouritesRepository(MemoryStore(listOf(1, 2)), alerts)
        val vm = model(FakeReadings(current = DataResult.Fresh(listOf(p(1), p(2)), Instant.EPOCH)), favourites)

        vm.requestRemove(listOf(1))
        assertEquals(listOf(2), favourites.favourites.value)
        assertNull(vm.uiState.value.pendingRemoval)

        vm.requestRemove(listOf(2))
        assertEquals(listOf(2), vm.uiState.value.pendingRemoval)
        assertEquals(listOf(2), favourites.favourites.value)
        vm.cancelRemoval()
        assertEquals(listOf(2), favourites.favourites.value)

        vm.requestRemove(listOf(2))
        vm.confirmRemoval()
        assertTrue(favourites.favourites.value.isEmpty())
        assertTrue(vm.uiState.value.pollutants.isEmpty())
        assertEquals(listOf(2), alerts.cleared)
        assertEquals(
            listOf("1", "2"),
            events.filter { it.first == Analytics.FAVOURITE_STATION_SAVED }.map { it.second["stationId"] }
        )
    }

    private fun p(id: Int) = Pollutant(
        stationId = id,
        code = "s$id",
        lat = 25.0,
        lon = 121.0,
        aqi = 40.0 + id,
        pm25 = 7.0,
        pm10 = 26.0,
        no2 = 3.0,
        so2 = 1.2,
        co = 0.33,
        o3 = 52.0,
        windDirection = 0.0,
        windSpeed = 0.0,
        publishTime = "2026-11-06T00:00:00",
        name = "Station $id",
        nameLocal = "測站$id"
    )
}
