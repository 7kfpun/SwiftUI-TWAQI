package com.kfpun.twaqi.ui

import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.data.FavouritesRepositoryTest.FakeAlerts
import com.kfpun.twaqi.data.FavouritesRepositoryTest.MemoryStore
import com.kfpun.twaqi.data.favourites.FavouriteAlertsHint
import com.kfpun.twaqi.data.favourites.FavouritesRepository
import com.kfpun.twaqi.data.model.HistoricalPollutant
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.model.Station
import com.kfpun.twaqi.data.model.StationHistory
import com.kfpun.twaqi.data.repository.DataResult
import com.kfpun.twaqi.data.repository.NoCurrentReadingException
import com.kfpun.twaqi.ui.station.StationDataSource
import com.kfpun.twaqi.ui.station.StationDetailsUiState
import com.kfpun.twaqi.ui.station.StationDetailsViewModel
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
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** iOS `DetailsViewModel`: which state each pair of answers leaves the page in. */
@OptIn(ExperimentalCoroutinesApi::class)
class StationDetailsViewModelTest {
    private val now = Instant.parse("2026-11-05T17:30:00Z") // 01:30 on the 6th in Taiwan
    private val events = mutableListOf<Pair<String, Map<String, String>>>()

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private class FakeSource(
        var saved: Pollutant? = null,
        var current: DataResult<Pollutant> = DataResult.Failed(IOException("offline")),
        var history: DataResult<StationHistory> = DataResult.Failed(IOException("offline"))
    ) : StationDataSource {
        override suspend fun savedPollutant(stationId: Int) = saved
        override suspend fun currentPollutant(stationId: Int) = current
        override suspend fun history(stationId: Int) = history
    }

    private fun model(
        source: FakeSource,
        favourites: FavouritesRepository = FavouritesRepository(MemoryStore(emptyList()))
    ) = StationDetailsViewModel(91, source, favourites) { name, params ->
        events += name to params
    }.also { it.refresh() }

    @Test
    fun onlineShowsTheReadingTheRecordAndTheHistory() {
        val vm =
            model(
                FakeSource(
                    current = fresh(pollutant(54.0)),
                    history = fresh(StationHistory(station(), hours(62.0, 54.0)))
                )
            )
        val state = vm.uiState.value
        assertEquals(54.0, state.pollutant?.aqi)
        assertEquals(91, state.station?.id)
        assertEquals(2, state.history.size)
        assertFalse(state.loading)
        assertFalse(state.isShowingLastGood)
        assertFalse(state.loadFailed)
        assertFalse(state.isNotReporting)
        assertFalse(state.stationLoadFailed)
        assertEquals("2026-11-06T00:00:00", state.latestPublishTime)
        assertEquals(54.0, state.currentAqi(now), 0.0)
        assertTrue(state.showsHistory(now))
        // The map marker logs check_main_details (FOX-54, as iOS); the page itself doesn't.
        assertTrue(events.none { it.first == "check_main_details" })
    }

    @Test
    fun offlineWithASavedReadingIsStale() {
        val vm = model(FakeSource(saved = pollutant(40.0)))
        val state = vm.uiState.value
        assertEquals(40.0, state.pollutant?.aqi)
        assertTrue(state.isShowingLastGood)
        assertFalse(state.loadFailed)
        assertTrue(state.stationLoadFailed)
        // Known from the cache, so the heart can add it.
        assertTrue(state.canAddFavourite)
    }

    @Test
    fun aRefreshThatFailsKeepsTheReadingOnScreenAsLastGood() {
        val source =
            FakeSource(current = fresh(pollutant(54.0)), history = fresh(StationHistory(station(), hours(62.0, 54.0))))
        val vm = model(source)
        source.current = DataResult.Failed(IOException("offline"))
        source.history = DataResult.Failed(IOException("offline"))
        vm.refresh()
        val state = vm.uiState.value
        assertEquals(54.0, state.pollutant?.aqi)
        assertTrue(state.isShowingLastGood)
        assertFalse(state.loadFailed)
        // The record from earlier this visit stays, so the alerts row (FOX-57) still has a station.
        assertNotNull(state.station)
        assertFalse(state.stationLoadFailed)
    }

    @Test
    fun offlineWithNothingSavedFails() {
        val state = model(FakeSource()).uiState.value
        assertNull(state.pollutant)
        assertTrue(state.loadFailed)
        assertFalse(state.isShowingLastGood)
        assertFalse(state.canAddFavourite)
        assertFalse(state.canToggleFavourite)
        assertEquals(0.0, state.currentAqi(now), 0.0)
    }

    @Test
    fun aStationWithNoCurrentReadingIsNotReportingNotOffline() {
        val old = HistoricalPollutant(70.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, "2024-01-01T10:00:00")
        val vm = model(
            FakeSource(
                current = DataResult.Failed(NoCurrentReadingException(91)),
                history = fresh(StationHistory(station(), listOf(old, old)))
            )
        )
        val state = vm.uiState.value
        assertTrue(state.isNotReporting)
        assertFalse(state.isShowingLastGood)
        assertFalse(state.loadFailed)
        // Its last points are years old: not the air now, and not today's trend.
        assertFalse(state.hasRecentHistory(now))
        assertEquals(0.0, state.currentAqi(now), 0.0)
        assertFalse(state.showsHistory(now))
    }

    @Test
    fun notReportingKeepsASavedReadingWithoutCallingItOffline() {
        val vm = model(
            FakeSource(
                saved = pollutant(33.0),
                current = DataResult.Stale(pollutant(33.0), now, NoCurrentReadingException(91)),
                history = fresh(StationHistory(station(), emptyList()))
            )
        )
        val state = vm.uiState.value
        assertTrue(state.isNotReporting)
        assertFalse(state.isShowingLastGood)
        assertEquals(33.0, state.pollutant?.aqi)
    }

    @Test
    fun withoutACurrentReadingTheNewestRecentHourIsShown() {
        val vm = model(FakeSource(history = fresh(StationHistory(station(), hours(62.0, 58.0)))))
        val state = vm.uiState.value
        assertNull(state.pollutant)
        assertFalse(state.loadFailed)
        assertEquals(58.0, state.currentAqi(now), 0.0)
    }

    @Test
    fun anUnknownIdHasNoRecordAndCannotBeFavourited() {
        val blank = Station(0, 0, "", "", 0.0, 0.0, null, "", "")
        val favourites = FavouritesRepository(MemoryStore(emptyList()))
        val vm = model(
            FakeSource(
                current = DataResult.Failed(NoCurrentReadingException(91)),
                history = fresh(StationHistory(blank, emptyList()))
            ),
            favourites
        )
        assertTrue(vm.uiState.value.stationLoadFailed)
        assertNull(vm.uiState.value.station)
        vm.toggleFavourite()
        assertTrue(favourites.favourites.value.isEmpty())
    }

    @Test
    fun theHeartAddsAndRemoves() {
        val favourites = FavouritesRepository(MemoryStore(emptyList()))
        val vm = model(FakeSource(current = fresh(pollutant(54.0))), favourites)
        vm.toggleFavourite()
        assertEquals(listOf(91), favourites.favourites.value)
        assertTrue(vm.uiState.value.isFavourite)
        vm.toggleFavourite()
        assertTrue(favourites.favourites.value.isEmpty())
        assertFalse(vm.uiState.value.isFavourite)
        assertEquals(
            listOf("on", "off"),
            events.filter { it.first == Analytics.FAVOURITE_STATION_SAVED }.map { it.second["label"] }
        )
    }

    @Test
    fun removingAStationWithAlertsAsksFirstAndClearsThem() {
        val alerts = FakeAlerts(setOf(91))
        val favourites = FavouritesRepository(MemoryStore(listOf(91)), alerts)
        val vm = model(FakeSource(current = fresh(pollutant(54.0))), favourites)
        vm.toggleFavourite()
        assertTrue(vm.uiState.value.confirmingUnfavourite)
        assertEquals(listOf(91), favourites.favourites.value)

        vm.dismissUnfavourite()
        assertFalse(vm.uiState.value.confirmingUnfavourite)
        assertEquals(listOf(91), favourites.favourites.value)

        vm.toggleFavourite()
        vm.removeFromFavourites()
        assertTrue(favourites.favourites.value.isEmpty())
        assertEquals(listOf(91), alerts.cleared)
    }

    @Test
    fun aNewFavouriteSwitchesItsAlertsOn() {
        // iOS FOX-31: favouriting from the station page turns its alerts on.
        val alerts = FakeAlerts()
        val favourites = FavouritesRepository(MemoryStore(emptyList()), alerts)
        val vm = model(FakeSource(current = fresh(pollutant(54.0))), favourites)
        vm.toggleFavourite()
        assertEquals(listOf(91), alerts.enabled)
        assertNull(vm.uiState.value.favouriteAlertsHint)
    }

    @Test
    fun aNewFavouriteWhoseAlertsStayOffSaysWhy() {
        for (hint in FavouriteAlertsHint.entries) {
            val alerts = FakeAlerts().apply { this.hint = hint }
            val favourites = FavouritesRepository(MemoryStore(emptyList()), alerts)
            val vm = model(FakeSource(current = fresh(pollutant(54.0))), favourites)
            vm.toggleFavourite()
            // The favourite stands either way.
            assertEquals(listOf(91), favourites.favourites.value)
            assertEquals(hint, vm.uiState.value.favouriteAlertsHint)
            vm.dismissFavouriteAlertsHint()
            assertNull(vm.uiState.value.favouriteAlertsHint)
        }
    }

    @Test
    fun aFavouriteChangedElsewhereShowsOnTheHeart() {
        val favourites = FavouritesRepository(MemoryStore(emptyList()))
        val vm = model(FakeSource(), favourites)
        assertFalse(vm.uiState.value.isFavourite)
        favourites.add(91)
        assertTrue(vm.uiState.value.isFavourite)
        // Already a favourite, so the heart can always remove it, even with nothing loaded.
        assertTrue(vm.uiState.value.canToggleFavourite)
    }

    @Test
    fun recentHistoryIsUnderADayOld() {
        val state = StationDetailsUiState(91, history = hours(50.0))
        assertTrue(state.hasRecentHistory(now))
        assertFalse(state.hasRecentHistory(now.plusSeconds(2 * 24 * 3600)))
    }

    private fun <T> fresh(value: T) = DataResult.Fresh(value, now)

    private fun station() = Station(
        id = 91,
        countryId = 3,
        countryCode = "twn",
        code = "基隆",
        lat = 25.129167,
        lon = 121.760056,
        imageUrl = null,
        name = "Keelung",
        nameLocal = "基隆"
    )

    private fun pollutant(aqi: Double) = Pollutant(
        stationId = 91,
        code = "基隆",
        lat = 25.129167,
        lon = 121.760056,
        aqi = aqi,
        pm25 = 7.0,
        pm10 = 26.0,
        no2 = 3.0,
        so2 = 1.2,
        co = 0.33,
        o3 = 52.0,
        windDirection = 85.0,
        windSpeed = 1.6,
        publishTime = "2026-11-06T00:00:00",
        name = "Keelung",
        nameLocal = "基隆"
    )

    /** Hourly readings ending at 01:00 on 2026-11-06, Taiwan time. */
    private fun hours(vararg aqi: Double) = aqi.mapIndexed { index, value ->
        val hour = 1 - (aqi.size - 1 - index)
        val time = if (hour >= 0) "2026-11-06T%02d:00:00".format(hour) else "2026-11-05T%02d:00:00".format(24 + hour)
        HistoricalPollutant(value, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, time)
    }
}
