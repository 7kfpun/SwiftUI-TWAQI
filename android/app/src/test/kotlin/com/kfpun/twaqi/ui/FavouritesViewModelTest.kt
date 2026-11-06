package com.kfpun.twaqi.ui

import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.data.FavouritesRepositoryTest.FakeAlerts
import com.kfpun.twaqi.data.FavouritesRepositoryTest.MemoryStore
import com.kfpun.twaqi.data.favourites.FavouritesRepository
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.repository.DataResult
import com.kfpun.twaqi.push.FakeAlertStore
import com.kfpun.twaqi.push.FavouriteAlerts
import com.kfpun.twaqi.push.RecordingLogger
import com.kfpun.twaqi.push.RepositoryFavouriteStations
import com.kfpun.twaqi.push.StationAlerts
import com.kfpun.twaqi.ui.favourites.FavouriteReadings
import com.kfpun.twaqi.ui.favourites.FavouritesViewModel
import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
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

    // FOX-121: a drag drops as one move, a swipe removes, both through the real alerts rule.

    /** Favourites wired to the real [FavouriteAlerts] over an in-memory alert store, as `PushGraph` wires them. */
    private class WithAlerts(scope: CoroutineScope, saved: List<Int>, alerted: Map<Int, StationAlerts>) {
        val store = MemoryStore(saved)
        val alertStore = FakeAlertStore(alerted)
        val logger = RecordingLogger()
        lateinit var favourites: FavouritesRepository
        val alerts = FavouriteAlerts(alertStore, { RepositoryFavouriteStations(favourites) }, { false }, logger, scope)

        init {
            favourites = FavouritesRepository(store, alerts)
        }
    }

    /** Runs the alerts' state at once, so the list sees alerts go off within the test. */
    private fun TestScope.eagerScope() =
        CoroutineScope(backgroundScope.coroutineContext + UnconfinedTestDispatcher(testScheduler))

    @Test
    fun aDroppedDragIsSavedAndReadBackAfterARestart() = runTest {
        val w = WithAlerts(eagerScope(), listOf(1, 2, 3, 4), alerted = mapOf(3 to StationAlerts(above = 120)))
        val vm = model(FakeReadings(current = DataResult.Fresh((1..4).map(::p), Instant.EPOCH)), w.favourites)

        // Held at the bottom and dragged to the top: one save on drop.
        vm.reorder(listOf(4, 1, 2, 3))

        assertEquals(listOf(4, 1, 2, 3), vm.uiState.value.pollutants.map { it.stationId })
        assertEquals(listOf(4, 1, 2, 3), FavouritesRepository(w.store).favourites.value)
        assertEquals(1, events.count { it.first == Analytics.FAVOURITE_STATION_REORDERED })
    }

    @Test
    fun reorderingNeverTouchesAlerts() = runTest {
        val alerted = mapOf(1 to StationAlerts(above = 120), 3 to StationAlerts(below = 30))
        val w = WithAlerts(eagerScope(), listOf(1, 2, 3), alerted)
        val vm = model(FakeReadings(current = DataResult.Fresh((1..3).map(::p), Instant.EPOCH)), w.favourites)

        vm.reorder(listOf(2, 3, 1))
        vm.reorder(listOf(2, 1, 3))
        vm.move(0, 2)

        assertEquals(listOf(1, 3, 2), w.favourites.favourites.value)
        assertTrue(w.alertStore.writes.isEmpty())
        assertEquals(alerted, w.alertStore.alertedStations.value)
        assertEquals(setOf(1, 3), vm.uiState.value.alertedStationIds)
        assertTrue(w.logger.events.isEmpty())
    }

    @Test
    fun aDropSavesTheDraggedStationsEvenWhenTheListRefreshedMidDrag() {
        // Saved 1, 2, 3; only 1 and 3 have a cached reading, so the list opens as 1, 3.
        val favourites = FavouritesRepository(MemoryStore(listOf(1, 2, 3)))
        val readings = FakeReadings(saved = listOf(p(1), p(3)))
        val vm = model(readings, favourites)
        assertEquals(listOf(1, 3), vm.uiState.value.pollutants.map { it.stationId })

        // 3 is held and dragged above 1; before the finger lifts, the request returns all three.
        readings.current = DataResult.Fresh((1..3).map(::p), Instant.EPOCH)
        vm.refresh()
        assertEquals(listOf(1, 2, 3), vm.uiState.value.pollutants.map { it.stationId })
        vm.reorder(listOf(3, 1))

        // 3 moved, not 2, which wasn't on screen when the drag started and goes after the rest.
        assertEquals(listOf(3, 1, 2), favourites.favourites.value)
        assertEquals(listOf(3, 1, 2), vm.uiState.value.pollutants.map { it.stationId })
        assertEquals(1, events.count { it.first == Analytics.FAVOURITE_STATION_REORDERED })
    }

    @Test
    fun aDropOfAStationRemovedMidDragKeepsTheRest() {
        val favourites = FavouritesRepository(MemoryStore(listOf(1, 2, 3)))
        val vm = model(FakeReadings(current = DataResult.Fresh((1..3).map(::p), Instant.EPOCH)), favourites)

        // 3 is held while 1 is removed elsewhere (e.g. its station page), then dropped on top.
        favourites.remove(listOf(1))
        vm.reorder(listOf(3, 1, 2))

        assertEquals(listOf(3, 2), favourites.favourites.value)
    }

    @Test
    fun aDropThatChangesNothingSavesNothing() {
        val favourites = FavouritesRepository(MemoryStore(listOf(1, 2)))
        val vm = model(FakeReadings(current = DataResult.Fresh(listOf(p(1), p(2)), Instant.EPOCH)), favourites)

        vm.reorder(listOf(1, 2))

        assertEquals(0, events.count { it.first == Analytics.FAVOURITE_STATION_REORDERED })
    }

    @Test
    fun swipingAwayAStationWithAlertsTurnsThemOffOnTheDevice() = runTest {
        val w = WithAlerts(eagerScope(), listOf(1, 2), alerted = mapOf(2 to StationAlerts(above = 120, below = 30)))
        val vm = model(FakeReadings(current = DataResult.Fresh(listOf(p(1), p(2)), Instant.EPOCH)), w.favourites)

        // A swipe asks first; the reader confirms.
        vm.requestRemove(listOf(2))
        assertEquals(listOf(2), vm.uiState.value.pendingRemoval)
        assertTrue(w.alertStore.writes.isEmpty())
        vm.confirmRemoval()

        assertEquals(listOf(1), w.favourites.favourites.value)
        // Off, written to the phone's alert store at once (PushSync archives it in the push API later).
        assertEquals(listOf(FakeAlertStore.Write(2, null, StationAlerts.OFF, settled = true)), w.alertStore.writes)
        assertTrue(vm.uiState.value.alertedStationIds.isEmpty())
        assertEquals(Analytics.STATION_ALERTS_CLEARED_BY_UNFAVOURITE, w.logger.events.single().first)
        assertEquals(
            listOf(mapOf("label" to "off", "stationId" to "2")),
            events.filter { it.first == Analytics.FAVOURITE_STATION_SAVED }.map { it.second }
        )
    }

    @Test
    fun swipingAwayAStationWithoutAlertsRemovesItAtOnce() = runTest {
        val w = WithAlerts(eagerScope(), listOf(1, 2), alerted = mapOf(2 to StationAlerts(above = 120)))
        val vm = model(FakeReadings(current = DataResult.Fresh(listOf(p(1), p(2)), Instant.EPOCH)), w.favourites)

        vm.requestRemove(listOf(1))

        assertNull(vm.uiState.value.pendingRemoval)
        assertEquals(listOf(2), w.favourites.favourites.value)
        assertEquals(listOf(2), vm.uiState.value.pollutants.map { it.stationId })
        assertTrue(w.alertStore.writes.isEmpty())
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
