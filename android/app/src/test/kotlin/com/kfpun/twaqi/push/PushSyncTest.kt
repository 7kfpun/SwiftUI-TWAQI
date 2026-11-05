package com.kfpun.twaqi.push

import java.time.Duration
import java.time.Instant
import java.time.LocalTime
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS push dual-write tests (`DirectusPushMirror`): saved on the phone first, then synced, never lost. */
class PushSyncTest {
    private val on = StationAlerts(above = 120)

    // MARK: - Device first, then sync

    @Test
    fun changeIsSavedOnThePhoneBeforeAnySync() {
        val h = SyncHarness()
        h.sync.stationChanged(126, "A12", on, settled = false)

        // Takes effect at once, with no network.
        assertEquals(mapOf(126 to on), h.sync.alertedStations.value)
        assertEquals(mapOf("126" to on), h.store.wanted)
        assertEquals(on, h.sync.alerts(126))
        assertTrue(h.api.upserts.isEmpty() && h.api.reconciles.isEmpty())
        // The push API copy waits for the slider to stop.
        assertEquals(listOf(PushSync.DEBOUNCE_MILLIS), h.scheduler.delays)
    }

    @Test
    fun syncWritesTheDeviceThenTheStation() = runTest {
        val h = SyncHarness()
        h.sync.stationChanged(126, "A12", on, settled = true)
        assertEquals(listOf(0L), h.scheduler.delays)

        assertEquals(PushSync.Outcome.DONE, h.sync.sync())

        assertEquals(1, h.api.restores)
        assertEquals(1, h.api.upserts.size)
        assertEquals("fcm-1", h.api.upserts.single().fcmToken)
        assertEquals(listOf(Triple("126", "A12", on)), h.api.reconciles)
        assertEquals(mapOf("126" to on), h.store.synced)
        assertEquals(7, h.store.deviceRowId)
        // The request was signed with this install's identity.
        assertEquals(h.identity.id(), h.configs.single().deviceId)

        // Nothing left: a second run writes nothing.
        assertEquals(PushSync.Outcome.DONE, h.sync.sync())
        assertEquals(1, h.api.upserts.size)
        assertEquals(1, h.api.reconciles.size)
    }

    @Test
    fun failedWriteIsRetriedAndNeverLost() = runTest {
        val h = SyncHarness()
        h.sync.stationChanged(126, null, on, settled = true)
        h.api.failReconcile = PushException.Offline()

        // WorkManager retries with backoff.
        assertEquals(PushSync.Outcome.RETRY, h.sync.sync())
        assertEquals(mapOf("126" to on), h.store.wanted)
        assertTrue(h.store.synced.isEmpty())
        assertEquals(mapOf(126 to on), h.sync.alertedStations.value)

        assertEquals(PushSync.Outcome.DONE, h.sync.sync())
        assertEquals(listOf(Triple("126", null, on)), h.api.reconciles)
        assertEquals(mapOf("126" to on), h.store.synced)
    }

    @Test
    fun failedDeviceWriteKeepsEverythingPending() = runTest {
        val h = SyncHarness()
        h.sync.stationChanged(126, null, on, settled = true)
        h.api.failUpsert = PushException.Server(502)

        assertEquals(PushSync.Outcome.RETRY, h.sync.sync())
        assertTrue(h.api.reconciles.isEmpty())
        assertNull(h.store.deviceRowId)
        assertEquals(mapOf("126" to on), h.store.wanted)

        assertEquals(PushSync.Outcome.DONE, h.sync.sync())
        assertEquals(1, h.api.reconciles.size)
    }

    @Test
    fun dndChangeStaysPendingUntilWritten() = runTest {
        val h = SyncHarness()
        h.sync.stationChanged(126, null, on, settled = true)
        h.sync.sync()
        val window = DndWindow(true, LocalTime.of(23, 0), LocalTime.of(6, 30))
        h.sync.dndChanged(window)
        assertEquals(window, h.store.dnd)
        assertTrue(h.store.dndEdited)

        h.api.failUpsert = PushException.Network()
        assertEquals(PushSync.Outcome.RETRY, h.sync.sync())
        assertEquals(PushSync.Outcome.DONE, h.sync.sync())
        val written = h.api.upserts.last()
        assertEquals(true, written.dndEnabled)
        assertEquals("23:00", written.dndStart)
        assertEquals("06:30", written.dndEnd)
    }

    // MARK: - Switching off archives

    @Test
    fun switchingOffArchivesAndForgetsTheStation() = runTest {
        val h = SyncHarness()
        h.sync.stationChanged(126, null, on, settled = true)
        h.sync.sync()

        h.sync.stationChanged(126, null, StationAlerts.OFF, settled = true)
        assertTrue(h.sync.alertedStations.value.isEmpty())
        // Still there until the archive lands.
        assertEquals(mapOf("126" to StationAlerts.OFF), h.store.wanted)

        h.sync.sync()
        // Off goes to the Worker as nulls, which archives the rows; there is no delete call.
        assertEquals(Triple("126", null, StationAlerts.OFF), h.api.reconciles.last())
        assertTrue(h.store.wanted.isEmpty())
        assertTrue(h.store.synced.isEmpty())
    }

    @Test
    fun offNeverWrittenNeedsNothing() = runTest {
        val h = SyncHarness()
        h.sync.stationChanged(126, null, on, settled = true)
        h.sync.stationChanged(126, null, StationAlerts.OFF, settled = true)

        assertEquals(PushSync.Outcome.DONE, h.sync.sync())
        // No row yet and nothing to switch on: no device, no station call.
        assertTrue(h.api.upserts.isEmpty())
        assertTrue(h.api.reconciles.isEmpty())
        assertTrue(h.store.wanted.isEmpty())
    }

    @Test
    fun cancelAllArchivesEveryAlertOnTheDevice() = runTest {
        val h = SyncHarness()
        h.sync.stationChanged(126, null, on, settled = true)
        h.sync.stationChanged(7, null, StationAlerts(below = 20), settled = true)
        h.sync.sync()

        h.sync.cancelAll()
        assertTrue(h.sync.alertedStations.value.isEmpty())
        assertTrue(h.store.archiveAll)

        h.api.failArchiveAll = PushException.Offline()
        assertEquals(PushSync.Outcome.RETRY, h.sync.sync())
        // Kept until done.
        assertTrue(h.store.archiveAll)

        assertEquals(PushSync.Outcome.DONE, h.sync.sync())
        assertEquals(1, h.api.archiveAlls)
        assertFalse(h.store.archiveAll)
        assertTrue(h.store.wanted.isEmpty())
        assertTrue(h.store.synced.isEmpty())
    }

    // MARK: - Tokens, profile, configuration

    @Test
    fun newFcmTokenAloneRewritesTheRow() = runTest {
        val h = SyncHarness()
        h.sync.stationChanged(126, null, on, settled = true)
        h.sync.sync()

        h.sync.fcmTokenChanged("fcm-2")
        h.sync.sync()
        assertEquals(listOf("fcm-1", "fcm-2"), h.api.upserts.map { it.fcmToken })
        // The same token again is not a change.
        h.sync.fcmTokenChanged("fcm-2")
        assertEquals(2, h.scheduler.delays.size)
    }

    @Test
    fun languageOrProChangeRewritesTheRow() = runTest {
        val h = SyncHarness()
        h.sync.stationChanged(126, null, on, settled = true)
        h.sync.sync()

        h.profile.language = "zh-Hant"
        h.profile.pro = true
        h.sync.profileChanged()
        h.sync.sync()
        assertEquals("zh-Hant", h.api.upserts.last().locale)
        assertTrue(h.api.upserts.last().isPro)
        assertEquals(2, h.api.upserts.size)
    }

    @Test
    fun profileChangeWithoutARowWritesNothing() {
        val h = SyncHarness()
        h.sync.profileChanged()
        assertTrue(h.scheduler.delays.isEmpty())
    }

    @Test
    fun noFcmTokenOrNoPushApiKeepsAlertsOnThePhone() = runTest {
        val noToken = SyncHarness(store = InMemoryPushStore())
        noToken.sync.stationChanged(126, null, on, settled = true)
        assertEquals(PushSync.Outcome.DONE, noToken.sync.sync())
        assertTrue(noToken.api.upserts.isEmpty())
        assertEquals(mapOf(126 to on), noToken.sync.alertedStations.value)

        val unconfigured = SyncHarness(baseUrl = "")
        unconfigured.sync.stationChanged(126, null, on, settled = true)
        assertEquals(PushSync.Outcome.DONE, unconfigured.sync.sync())
        assertTrue(unconfigured.api.upserts.isEmpty())
    }

    // MARK: - Recovering from the push API

    @Test
    fun anotherInstallHoldingTheIdGetsANewIdentityAndEveryAlertAgain() = runTest {
        val h = SyncHarness()
        h.sync.stationChanged(126, null, on, settled = true)
        h.sync.sync()
        val firstId = h.identity.id()

        h.sync.stationChanged(7, null, StationAlerts(below = 20), settled = true)
        h.api.failReconcile = PushException.Server(403)
        assertEquals(PushSync.Outcome.RETRY, h.sync.sync())
        assertEquals(1, h.identity.resets)
        assertNull(h.store.deviceRowId)
        assertTrue(h.store.synced.isEmpty())

        h.api.rowId = 8
        assertEquals(PushSync.Outcome.DONE, h.sync.sync())
        assertNotEquals(firstId, h.api.upserts.last().deviceId)
        // Both stations written again to the new row.
        assertEquals(setOf("126", "7"), h.api.reconciles.takeLast(2).map { it.first }.toSet())
        assertEquals(8, h.store.deviceRowId)
    }

    @Test
    fun recoveryFromThePushApi() {
        assertEquals(PushSync.Recovery.NEW_IDENTITY, PushSync.recovery(PushException.Server(403)))
        assertEquals(PushSync.Recovery.REGISTER, PushSync.recovery(PushException.Server(404)))
        assertEquals(PushSync.Recovery.NONE, PushSync.recovery(PushException.Server(502)))
        assertEquals(PushSync.Recovery.NONE, PushSync.recovery(PushException.Offline()))
    }

    // MARK: - Reinstall and restore

    @Test
    fun alertsRestoredFromBackupAreResyncedUnderTheNewDevice() = runTest {
        // A reinstall: Android backup brings back the alerts and quiet hours (push_settings), but
        // not the identity or the sync state, so the Keystore makes a new device id.
        val store = InMemoryPushStore().apply {
            wanted = mapOf("126" to on, "7" to StationAlerts(below = 20))
            siteIds = mapOf("126" to "A12")
            dnd = DndWindow(true, LocalTime.of(22, 0), LocalTime.of(7, 0))
            fcmToken = "fcm-new"
        }
        val h = SyncHarness(store = store)
        // Nothing under the new identity.
        h.api.restored = RestoredDevice(device = null, subscriptions = emptyList())
        h.api.rowId = 31

        assertEquals(PushSync.Outcome.DONE, h.sync.sync())

        assertEquals(1, h.api.restores)
        val row = h.api.upserts.single()
        assertEquals(h.identity.id(), row.deviceId)
        assertEquals("fcm-new", row.fcmToken)
        assertTrue(row.dndEnabled)
        assertEquals(
            setOf(Triple("126", "A12", on), Triple("7", null, StationAlerts(below = 20))),
            h.api.reconciles.toSet()
        )
        assertEquals(31, h.store.deviceRowId)
        assertEquals(store.wanted, h.store.synced)
    }

    @Test
    fun restoreTakesTheRowsAlertsAndAnnouncesThem() = runTest {
        val h = SyncHarness()
        var announced: Map<Int, StationAlerts> = emptyMap()
        h.sync.onRestored = { announced = it }
        h.api.restored = RestoredDevice(
            StoredDevice(id = 5, dndEnabled = true, dndStart = "23:00", dndEnd = "06:00"),
            listOf(PushSubscription(1, "126", null, PushDirection.ABOVE, 150, enabled = true))
        )
        h.api.rowId = 5

        h.sync.sync()
        assertEquals(mapOf(126 to StationAlerts(above = 150)), announced)
        assertEquals(mapOf(126 to StationAlerts(above = 150)), h.sync.alertedStations.value)
        // A fresh install takes the stored quiet hours.
        assertEquals(DndWindow(true, LocalTime.of(23, 0), LocalTime.of(6, 0)), h.store.dnd)
        // Adopted as it is: nothing written again.
        assertTrue(h.api.reconciles.isEmpty())
    }

    @Test
    fun failedRestoreWritesNothing() = runTest {
        val h = SyncHarness()
        h.sync.stationChanged(126, null, on, settled = true)
        h.api.failRestore = PushException.Network()
        assertEquals(PushSync.Outcome.RETRY, h.sync.sync())
        assertTrue(h.api.upserts.isEmpty())
        assertFalse(h.store.restored)
    }

    @Test
    fun dndEditedDuringRestoreIsKept() {
        assertTrue(PushSync.restoresDnd(isFreshInstall = true, editedLocally = false))
        assertFalse(PushSync.restoresDnd(isFreshInstall = true, editedLocally = true))
        assertFalse(PushSync.restoresDnd(isFreshInstall = false, editedLocally = false))
    }

    @Test
    fun cancelAllDuringRestoreKeepsAlertsOff() {
        assertTrue(PushSync.keepsCancelAll(hasDevice = false, restored = false))
        assertTrue(PushSync.keepsCancelAll(hasDevice = true, restored = true))
        assertFalse(PushSync.keepsCancelAll(hasDevice = false, restored = true))

        val remote = mapOf("105" to StationAlerts(above = 120), "126" to StationAlerts(below = 30))
        assertEquals(
            mapOf("105" to StationAlerts.OFF),
            PushSync.restoredWanted(mapOf("105" to StationAlerts.OFF), remote, cancelPending = true)
        )
        assertEquals(
            mapOf("105" to StationAlerts(above = 150), "126" to StationAlerts(below = 30)),
            PushSync.restoredWanted(mapOf("105" to StationAlerts(above = 150)), remote, cancelPending = false)
        )
    }

    // MARK: - Decisions

    @Test
    fun deviceWithNoPendingAlertsStillSyncs() {
        assertTrue(PushSync.needsDevice(hasDevice = true, pending = emptyMap()))
        assertFalse(PushSync.needsDevice(hasDevice = false, pending = emptyMap()))
        assertFalse(PushSync.needsDevice(hasDevice = false, pending = mapOf("5" to StationAlerts.OFF)))
        assertTrue(PushSync.needsDevice(hasDevice = false, pending = mapOf("5" to StationAlerts(above = 120))))
    }

    @Test
    fun isDeviceCurrent() {
        val now = Instant.parse("2026-11-06T00:00:00Z")
        val recent = now.minusSeconds(60)
        fun current(
            token: String = "t",
            fcm: String? = "fcm-1",
            lastSync: Instant? = recent,
            synced: String? = "en|false",
            profile: String? = "en|false"
        ) = PushSync.isDeviceCurrent("t", token, "fcm-1", fcm, lastSync, synced, profile, now)

        assertTrue(current())
        assertFalse(current(fcm = "fcm-2"))
        // FCM hasn't issued a token yet: not a change.
        assertTrue(current(fcm = null))
        assertFalse(current(token = "t2"))
        assertFalse(current(lastSync = null))
        assertFalse(current(lastSync = now.minus(PushSync.DEVICE_REFRESH_INTERVAL).minus(Duration.ofSeconds(1))))
        assertFalse(current(profile = "zh-Hant|false"))
        assertFalse(current(synced = null))
    }

    @Test
    fun storedAlertsReadOnlyStationsWithAnAlertOn() {
        val wanted = mapOf(
            "126" to StationAlerts(above = 150),
            "7" to StationAlerts.OFF,
            "x" to StationAlerts(below = 20)
        )
        assertEquals(mapOf(126 to StationAlerts(above = 150)), PushSync.alertedFrom(wanted))
        // The stored form round-trips, nulls and all.
        assertEquals(wanted, StationAlerts.decodeMap(StationAlerts.encodeMap(wanted)))
        assertTrue(StationAlerts.decodeMap("not json").isEmpty())
    }

    @Test
    fun settingRoundTripsThroughAlerts() {
        assertEquals(StationAlerts(above = 120), StationAlerts.from(FavouriteAlerts.DEFAULT_ALERTS))
        val setting = StationAlertSetting(true, true, pollutionThreshold = 150.0, cleanlinessThreshold = 20.0)
        assertEquals(setting, StationAlertSetting.from(StationAlerts.from(setting)))
        // Switched off, the slider keeps its default.
        assertEquals(StationAlertSetting.OFF, StationAlertSetting.from(StationAlerts.OFF))
        assertEquals(
            StationAlerts.OFF,
            StationAlerts.from(
                setting.copy(isPollutionNotificationEnabled = false, isCleanlinessNotificationEnabled = false)
            )
        )
    }
}
