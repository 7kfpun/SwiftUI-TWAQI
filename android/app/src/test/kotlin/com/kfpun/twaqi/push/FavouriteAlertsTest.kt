package com.kfpun.twaqi.push

import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.data.FavouritesRepositoryTest.MemoryStore
import com.kfpun.twaqi.data.favourites.FavouriteAlertsHint
import com.kfpun.twaqi.data.favourites.FavouritesRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** An in-memory alert store that records each write (iOS `FavouriteAlertsTests.FakeServices`). */
class FakeAlertStore(initial: Map<Int, StationAlerts> = emptyMap()) : AlertStore {
    private val state = MutableStateFlow(initial)
    override val alertedStations: StateFlow<Map<Int, StationAlerts>> = state

    data class Write(val stationId: Int, val siteId: String?, val alerts: StationAlerts, val settled: Boolean)

    val writes = mutableListOf<Write>()
    var cancelledAll = 0

    override fun stationChanged(stationId: Int, siteId: String?, alerts: StationAlerts, settled: Boolean) {
        writes += Write(stationId, siteId, alerts, settled)
        state.value = if (alerts.isOff) state.value - stationId else state.value + (stationId to alerts)
    }

    override fun cancelAll() {
        cancelledAll++
        state.value = emptyMap()
    }
}

/** iOS `FavouriteAlertsTests` (FOX-20/31): keeping alerts and Favourites together. */
@OptIn(ExperimentalCoroutinesApi::class)
class FavouriteAlertsTest {
    private val above120 = StationAlerts(above = 120)

    private class Subject(
        val store: FakeAlertStore,
        val favourites: FakeFavourites,
        val logger: RecordingLogger,
        val alerts: FavouriteAlerts
    )

    private fun subject(
        scope: CoroutineScope,
        alerted: Map<Int, StationAlerts> = emptyMap(),
        favourites: List<Int> = alerted.keys.toList(),
        denied: Boolean = false
    ): Subject {
        val store = FakeAlertStore(alerted)
        val list = FakeFavourites(favourites)
        val logger = RecordingLogger()
        return Subject(store, list, logger, FavouriteAlerts(store, { list }, { denied }, logger, scope))
    }

    /** The changes posted while [work] runs. */
    private fun kotlinx.coroutines.test.TestScope.posts(alerts: FavouriteAlerts, work: () -> Unit): List<AlertChange> {
        val seen = mutableListOf<AlertChange>()
        val job = backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            alerts.changes.collect { seen += it }
        }
        work()
        job.cancel()
        return seen
    }

    @Test
    fun capIsThreeAndCountsOtherStationsOnly() {
        assertEquals(3, FavouriteAlerts.MAX_ALERTED_STATIONS)
        assertFalse(FavouriteAlerts.isAtCap(setOf(1, 3), excluding = 2))
        assertTrue(FavouriteAlerts.isAtCap(setOf(1, 3, 4), excluding = 2))
        // Its own alerts don't count against it.
        assertFalse(FavouriteAlerts.isAtCap(setOf(1, 2, 3), excluding = 2))
    }

    @Test
    fun defaultAlertsAreTheStationPagesFirstAboveAlert() {
        assertEquals(above120, StationAlerts.from(FavouriteAlerts.DEFAULT_ALERTS))
    }

    @Test
    fun newFavouriteDecision() {
        val enabled = FavouriteAlerts.NewFavouriteOutcome.Enabled(FavouriteAlerts.DEFAULT_ALERTS)
        assertEquals(enabled, FavouriteAlerts.newFavouriteDecision(setOf(1), 2))
        assertEquals(enabled, FavouriteAlerts.newFavouriteDecision(setOf(1, 3), 2))
        assertEquals(
            FavouriteAlerts.NewFavouriteOutcome.CapReached,
            FavouriteAlerts.newFavouriteDecision(setOf(1, 3, 4), 2)
        )
        assertEquals(
            FavouriteAlerts.NewFavouriteOutcome.AlreadyOn,
            FavouriteAlerts.newFavouriteDecision(setOf(1, 2, 3), 2)
        )
    }

    @Test
    fun enablingWritesAndTellsTheStationPage() = runTest {
        val s = subject(backgroundScope, alerted = mapOf(1 to StationAlerts(below = 20)), favourites = listOf(1, 126))
        var outcome: FavouriteAlerts.NewFavouriteOutcome? = null
        val seen = posts(s.alerts) { outcome = s.alerts.enableForNewFavourite(126, null) { true } }

        assertEquals(FavouriteAlerts.NewFavouriteOutcome.Enabled(FavouriteAlerts.DEFAULT_ALERTS), outcome)
        assertEquals(listOf(FakeAlertStore.Write(126, null, above120, settled = true)), s.store.writes)
        assertEquals(listOf(AlertChange(126, true, FavouriteAlerts.DEFAULT_ALERTS, alertedStationCount = 2)), seen)
        assertEquals(
            Analytics.STATION_ALERTS_ON_FAVOURITE to mapOf("outcome" to "enabled", "stationId" to "126"),
            s.logger.events.single()
        )
    }

    @Test
    fun alreadyOnKeepsItsThresholds() = runTest {
        val s = subject(backgroundScope, alerted = mapOf(126 to StationAlerts(above = 90)))
        assertEquals(FavouriteAlerts.NewFavouriteOutcome.AlreadyOn, s.alerts.enableForNewFavourite(126, null) { true })
        assertTrue(s.store.writes.isEmpty())
        assertEquals(StationAlerts(above = 90), s.store.alerts(126))
    }

    @Test
    fun capReachedWritesNothing() = runTest {
        val s = subject(backgroundScope, alerted = mapOf(1 to above120, 3 to above120, 4 to StationAlerts(below = 30)))
        assertEquals(FavouriteAlerts.NewFavouriteOutcome.CapReached, s.alerts.enableForNewFavourite(126, null) { true })
        assertTrue(s.store.writes.isEmpty())
    }

    @Test
    fun writeRefusesAStationPastTheCap() = runTest {
        // Two screens: both switches still looked unlocked, the first already saved.
        val s = subject(backgroundScope, alerted = mapOf(1 to above120, 2 to above120, 3 to StationAlerts(below = 30)))
        val on = StationAlertSetting(isPollutionNotificationEnabled = true, isCleanlinessNotificationEnabled = false)
        assertFalse(s.alerts.write(on, 126, null))
        assertTrue(s.store.writes.isEmpty())
        assertNull(s.store.alertedStations.value[126])

        // A station already on can still change, and any can go off...
        assertTrue(s.alerts.write(on, 2, null))
        assertTrue(s.alerts.write(StationAlertSetting.OFF, 3, null))
        // ...which makes room.
        assertTrue(s.alerts.write(on, 126, null))
    }

    @Test
    fun notificationsDeniedWritesNothing() = runTest {
        val s = subject(backgroundScope, denied = true)
        assertEquals(
            FavouriteAlerts.NewFavouriteOutcome.NotificationsDenied,
            s.alerts.enableForNewFavourite(126, null) {
                true
            }
        )
        assertTrue(s.store.writes.isEmpty())
    }

    @Test
    fun unfavouritedBeforeTheWriteIsLeftAlone() = runTest {
        val s = subject(backgroundScope)
        assertEquals(
            FavouriteAlerts.NewFavouriteOutcome.NotChanged,
            s.alerts.enableForNewFavourite(126, null) {
                false
            }
        )
        assertTrue(s.store.writes.isEmpty())
    }

    // MARK: - Leaving Favourites, cancel all, the switches

    @Test
    fun removingAFavouriteTurnsItsAlertsOffAndSaysSo() = runTest {
        val s = subject(backgroundScope, alerted = mapOf(126 to StationAlerts(above = 120, below = 30)))
        val seen = posts(s.alerts) { s.alerts.clear(126) }

        assertEquals(listOf(FakeAlertStore.Write(126, null, StationAlerts.OFF, settled = true)), s.store.writes)
        assertNull(s.store.alertedStations.value[126])
        assertEquals(listOf(AlertChange(126, isOn = false)), seen)
        assertEquals(Analytics.STATION_ALERTS_CLEARED_BY_UNFAVOURITE, s.logger.events.single().first)
    }

    @Test
    fun clearWithAlertsOffWritesNothing() = runTest {
        val s = subject(backgroundScope)
        val seen = posts(s.alerts) { s.alerts.clear(126) }
        assertTrue(s.store.writes.isEmpty())
        assertTrue(seen.isEmpty())
    }

    @Test
    fun cancelAllTurnsEveryStationOff() = runTest {
        val s = subject(backgroundScope, alerted = mapOf(126 to above120, 7 to StationAlerts(below = 20)))
        val seen = posts(s.alerts) { s.alerts.cancelAll() }

        assertEquals(1, s.store.cancelledAll)
        assertTrue(s.store.alertedStations.value.isEmpty())
        assertEquals(listOf(7, 126), seen.map { it.stationId })
        assertTrue(seen.none { it.isOn })
    }

    @Test
    fun switchWriteWaitsForTheSliderToStop() = runTest {
        val s = subject(backgroundScope)
        val setting =
            StationAlertSetting(
                isPollutionNotificationEnabled = true,
                isCleanlinessNotificationEnabled = false,
                pollutionThreshold = 150.0
            )
        s.alerts.write(setting, 126, "12")
        assertEquals(
            FakeAlertStore.Write(126, "12", StationAlerts(above = 150), settled = false),
            s.store.writes.single()
        )
    }

    @Test
    fun alertOnMakesTheStationAFavourite() = runTest {
        val s = subject(backgroundScope, favourites = listOf(1))
        s.alerts.addToFavourites(126)
        s.alerts.addToFavourites(126)
        assertEquals(listOf(1, 126), s.favourites.list)
        // Logged once, as iOS does, with the alert as its source.
        assertEquals(
            FavouriteAlerts.FAVOURITE_STATION_SAVED to mapOf(
                "label" to "on",
                "stationId" to "126",
                "source" to "alert"
            ),
            s.logger.events.single()
        )
    }

    @Test
    fun restoredAlertsMakeTheirStationsFavouritesAgain() = runTest {
        val s = subject(backgroundScope, alerted = mapOf(126 to above120), favourites = listOf(5))
        val seen = posts(s.alerts) { s.alerts.restored(mapOf(126 to above120)) }
        assertEquals(listOf(5, 126), s.favourites.list)
        assertEquals(listOf(AlertChange(126, true, StationAlertSetting.from(above120), alertedStationCount = 1)), seen)
    }

    @Test
    fun alertedStationIdsFollowTheStore() = runTest {
        val s = subject(backgroundScope)
        s.store.stationChanged(126, null, above120, settled = true)
        testScheduler.runCurrent()
        assertEquals(setOf(126), s.alerts.alertedStationIds.value)
    }

    @Test
    fun withTheRealSyncReorderingFavouritesLeavesAlertsAlone() = runTest {
        // Favourites order lives in the favourites list; alerts are keyed by station id, so
        // moving stations around never writes to the alert store.
        val h = SyncHarness()
        val list = FakeFavourites(listOf(126, 7, 5))
        val alerts = FavouriteAlerts(h.sync, { list }, { false }, RecordingLogger(), backgroundScope)
        h.sync.stationChanged(126, null, above120, settled = true)
        h.sync.stationChanged(7, null, StationAlerts(below = 20), settled = true)
        val before = h.store.wanted
        val scheduled = h.scheduler.delays.size

        list.list.reverse()

        assertEquals(before, h.store.wanted)
        assertEquals(scheduled, h.scheduler.delays.size)
        testScheduler.runCurrent()
        assertEquals(setOf(126, 7), alerts.alertedStationIds.value)
    }

    // MARK: - With FOX-55's FavouritesRepository, as the app wires them

    private class Wired(scope: CoroutineScope, favourites: List<Int>, denied: Boolean = false) {
        val h = SyncHarness()
        val repository: FavouritesRepository
        val alerts =
            FavouriteAlerts(h.sync, { RepositoryFavouriteStations(repository) }, { denied }, RecordingLogger(), scope)

        init {
            repository = FavouritesRepository(MemoryStore(favourites), alerts)
        }
    }

    @Test
    fun withTheRepositoryRemovingAFavouriteTurnsItsAlertsOff() = runTest {
        val w = Wired(backgroundScope, listOf(126, 7))
        w.h.sync.stationChanged(126, null, above120, settled = true)
        w.h.sync.stationChanged(7, null, above120, settled = true)
        testScheduler.runCurrent()
        assertTrue(w.repository.needsConfirmation(listOf(126)))

        w.repository.remove(126)

        assertEquals(listOf(7), w.repository.favourites.value)
        assertEquals(StationAlerts.OFF, w.h.store.wanted["126"])
        testScheduler.runCurrent()
        assertEquals(setOf(7), w.alerts.alertedStationIds.value)
    }

    @Test
    fun withTheRepositoryReorderingLeavesAlertsAlone() = runTest {
        val w = Wired(backgroundScope, listOf(126, 7, 5))
        w.h.sync.stationChanged(126, null, above120, settled = true)
        val before = w.h.store.wanted
        val scheduled = w.h.scheduler.delays.size

        w.repository.reorder(listOf(5, 7, 126))
        w.repository.move(0, 2)

        assertEquals(before, w.h.store.wanted)
        assertEquals(scheduled, w.h.scheduler.delays.size)
    }

    @Test
    fun withTheRepositoryAnAlertSwitchedOnMakesAFavourite() = runTest {
        val w = Wired(backgroundScope, emptyList())
        assertTrue(w.alerts.write(StationAlertSetting.from(above120), 91, siteId = null))
        w.alerts.addToFavourites(91)
        assertEquals(listOf(91), w.repository.favourites.value)
    }

    @Test
    fun withTheRepositoryANewFavouriteSwitchesOnOrSaysWhyNot() = runTest {
        val w = Wired(backgroundScope, listOf(1, 2, 3))
        w.repository.add(91)
        assertNull(w.alerts.enableForNewFavourite(91) { w.repository.contains(91) })
        assertEquals(above120, w.h.store.wanted["91"])

        val full = Wired(backgroundScope, listOf(1, 2, 3, 4))
        listOf(1, 2, 3).forEach { full.h.sync.stationChanged(it, null, above120, settled = true) }
        full.repository.add(4)
        assertEquals(FavouriteAlertsHint.CAP_REACHED, full.alerts.enableForNewFavourite(4) { true })

        val denied = Wired(backgroundScope, emptyList(), denied = true)
        assertEquals(FavouriteAlertsHint.NOTIFICATIONS_DENIED, denied.alerts.enableForNewFavourite(9) { true })
    }

    @Test
    fun restoredAlertsAreFavouritesInTheRepository() = runTest {
        val w = Wired(backgroundScope, listOf(126))
        w.alerts.restored(mapOf(7 to above120))
        assertEquals(listOf(126, 7), w.repository.favourites.value)
    }
}
