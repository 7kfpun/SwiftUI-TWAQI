package com.kfpun.twaqi.push

import android.util.Log
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** What the device row says about the app besides its tokens. */
interface DeviceProfileSource {
    suspend fun isPro(): Boolean

    /** "zh-Hant" or "en": the app's language (FOX-56), which the sender writes alerts in. */
    fun locale(): String

    /** Whether Android shows the app's notifications; null before the user was asked. */
    fun notificationsAllowed(): Boolean?

    val appVersion: String?
    val isDebug: Boolean
}

/** Runs [PushSync.sync] in the background, after [delayMillis], retrying until it lands (WorkManager in the app). */
fun interface SyncScheduler {
    fun schedule(delayMillis: Long)
}

/** The alerts store [FavouriteAlerts] writes to (iOS `FavouriteAlerts.Services`); [PushSync] in the app. */
interface AlertStore {
    /** Stations with at least one alert on, written to the push API or not. */
    val alertedStations: StateFlow<Map<Int, StationAlerts>>

    fun alerts(stationId: Int): StationAlerts = alertedStations.value[stationId] ?: StationAlerts.OFF

    /** Saves a station's alerts; `settled` false waits for a slider to stop before the push API copy. */
    fun stationChanged(stationId: Int, siteId: String?, alerts: StationAlerts, settled: Boolean)

    /** Help's "cancel all". */
    fun cancelAll()
}

/**
 * Keeps the push settings — each station's alerts and the do-not-disturb window — in the push
 * Worker's API, where the FCM sender reads them (iOS `DirectusPushMirror`).
 *
 * Every change is saved in [store] first, so it takes effect on the phone at once, and written
 * to the push API after, by [scheduler] (WorkManager): a failure is logged and retried with
 * backoff, on the next change, launch or token change, and never reaches the user. Switching
 * off archives the station's alerts; nothing is deleted.
 *
 * The device row is keyed by this install's [identity] and carries the FCM token. A row is only
 * made once an alert is switched on; after that it follows every token and profile change.
 */
class PushSync(
    private val store: PushStore,
    private val identity: PushIdentity,
    private val baseUrl: String?,
    private val apiFactory: (PushConfig) -> PushApi,
    private val profile: DeviceProfileSource,
    private val scheduler: SyncScheduler,
    private val clock: () -> Instant = Instant::now
) : AlertStore {
    /** Restored alerts for stations this install didn't have: [FavouriteAlerts] makes them favourites again. */
    var onRestored: (Map<Int, StationAlerts>) -> Unit = {}

    private val lock = Any()
    private val flushLock = Mutex()
    private val alerted = MutableStateFlow(alertedFrom(store.wanted))

    override val alertedStations: StateFlow<Map<Int, StationAlerts>> = alerted.asStateFlow()

    /** Do-not-disturb as last set. */
    val dnd: DndWindow get() = synchronized(lock) { store.dnd }

    // MARK: - Entry points

    /** At launch and back in the foreground: catches up on anything an earlier attempt couldn't write. */
    fun start() = scheduler.schedule(0)

    /** From FCM, at launch and whenever it rotates the token. */
    fun fcmTokenChanged(token: String?) {
        if (token.isNullOrEmpty()) return
        synchronized(lock) {
            if (token == store.fcmToken) return
            store.fcmToken = token
        }
        scheduler.schedule(0)
    }

    override fun stationChanged(stationId: Int, siteId: String?, alerts: StationAlerts, settled: Boolean) {
        val key = stationId.toString()
        synchronized(lock) {
            if (siteId != null) store.siteIds = store.siteIds + (key to siteId)
            val wanted = store.wanted
            if (wanted[key] == alerts && store.synced[key] == alerts) return
            saveWanted(wanted + (key to alerts))
        }
        scheduler.schedule(if (settled) 0 else DEBOUNCE_MILLIS)
    }

    /**
     * Help's do-not-disturb. Marked as a local edit, so a restore still in flight can't overwrite
     * it, and synced whenever there is a row: the window is part of the row's profile, so the
     * write is retried until it lands. With no row and no alert on, the sync writes nothing.
     */
    fun dndChanged(window: DndWindow) {
        synchronized(lock) {
            store.dnd = window
            store.dndEdited = true
        }
        scheduler.schedule(DEBOUNCE_MILLIS)
    }

    /** The user answered the notification prompt (or changed it in Settings): `notifications_allowed` is written now. */
    fun notificationsChanged() = scheduler.schedule(0)

    /** Android 13+: the app is about to ask for the notification permission. */
    fun notificationsAsked() = synchronized(lock) { store.notificationsAsked = true }

    val wasAskedForNotifications: Boolean get() = synchronized(lock) { store.notificationsAsked }

    /** The app language or Pro changed. Only updates a device that already has a row. */
    fun profileChanged() {
        if (synchronized(lock) { store.deviceRowId } == null) return
        scheduler.schedule(DEBOUNCE_MILLIS)
    }

    /** Help's "cancel all": archives every live alert on this device, including any for stations this install never opened. */
    override fun cancelAll() {
        synchronized(lock) {
            val all = store.wanted.keys + store.synced.keys
            saveWanted(all.associateWith { StationAlerts.OFF })
            // Kept until done, so a cancel made offline still happens later, and one made while a
            // restore is pending stops the restore bringing the alerts back.
            store.archiveAll = keepsCancelAll(hasDevice = store.deviceRowId != null, restored = store.restored)
        }
        scheduler.schedule(0)
    }

    // MARK: - Sync

    /** What a background run reports: done (nothing left, or nothing possible yet) or retry later. */
    enum class Outcome { DONE, RETRY }

    /** Writes whatever differs between the phone and the push API. One at a time. */
    suspend fun sync(): Outcome = flushLock.withLock { flushOnce() }

    private suspend fun flushOnce(): Outcome {
        val baseUrl = baseUrl?.takeIf(String::isNotBlank) ?: return Outcome.DONE
        // FCM hasn't issued a token yet (or this build has no Firebase): fcmTokenChanged brings us back.
        val token = synchronized(lock) { store.fcmToken } ?: return Outcome.DONE
        val config = config(baseUrl) ?: return Outcome.RETRY
        val api = apiFactory(config)

        if (!synchronized(lock) { store.restored }) {
            // Writing now could overwrite the row being restored from.
            attempt("restore") { restore(api) } ?: return Outcome.RETRY
        }

        if (synchronized(lock) { store.archiveAll && store.deviceRowId != null }) {
            attempt("cancel all") { api.archiveAll() } ?: return Outcome.RETRY
            synchronized(lock) {
                store.archiveAll = false
                // Everything is archived now; only changes made since remain.
                saveWanted(store.wanted.filterValues { !it.isOff })
                store.synced = emptyMap()
            }
        }

        val (wanted, pending, hasDevice) = synchronized(lock) {
            var wanted = store.wanted
            var synced = store.synced
            // An alert that's off and was never written needs nothing.
            val untouched = wanted.filter { (key, alerts) ->
                alerts.isOff && (synced[key] ?: StationAlerts.OFF).isOff
            }.keys
            wanted = wanted - untouched
            synced = synced - untouched
            saveWanted(wanted)
            store.synced = synced
            Triple(wanted, wanted.filter { synced[it.key] != it.value }, store.deviceRowId != null)
        }
        if (!needsDevice(hasDevice, pending)) return Outcome.DONE

        attempt("device") { deviceId(api, config.deviceId, token) } ?: return Outcome.RETRY

        // A new row starts with no alerts: everything is written again.
        var outcome = Outcome.DONE
        val (refreshed, siteIds) = synchronized(lock) { store.synced to store.siteIds }
        for ((key, alerts) in wanted) {
            if (refreshed[key] == alerts) continue
            val done = attempt("station $key") { api.reconcile(key, siteIds[key], alerts) }
            if (done == null) {
                outcome = Outcome.RETRY
                continue
            }
            synchronized(lock) {
                var synced = store.synced + (key to alerts)
                val latest = store.wanted
                if (alerts.isOff && latest[key] == alerts) {
                    synced = synced - key
                    saveWanted(latest - key)
                }
                store.synced = synced
            }
        }
        return outcome
    }

    /**
     * Once per install: finds the row this install already has and takes its alerts, and on a
     * fresh install its do-not-disturb window. Local changes not yet written win over what's
     * restored. (On Android a reinstall has a new identity, so this mostly finds nothing; the
     * alerts restored from backup are then written to the new row.)
     */
    private suspend fun restore(api: PushApi) {
        val restored = api.restore()
        val restoredStations = synchronized(lock) {
            val isFreshInstall = store.deviceRowId == null
            val stored = restored.device
            if (stored == null) {
                // Nothing for this install: a pending cancel has nothing to archive.
                store.archiveAll = false
                store.restored = true
                return
            }
            val remote = StationAlerts.byStation(restored.subscriptions)
            if (restoresDnd(isFreshInstall, store.dndEdited)) {
                val current = store.dnd
                store.dnd = DndWindow(
                    enabled = stored.dndEnabled ?: current.enabled,
                    start = StoredDevice.time(stored.dndStart) ?: current.start,
                    end = StoredDevice.time(stored.dndEnd) ?: current.end
                )
            }
            val local = store.wanted
            val wanted = restoredWanted(local, remote, cancelPending = store.archiveAll)
            saveWanted(wanted)
            // The row is this device's: adopting its id keeps the device step from treating it
            // as new and writing every alert again.
            if (store.deviceRowId != stored.id) {
                store.deviceRowId = stored.id
                store.lastDeviceSyncAt = null
                store.synced = remote
            } else {
                store.synced = remote + store.synced
            }
            store.restored = true
            wanted.filterKeys { it !in local }
                .mapNotNull { (key, alerts) -> key.toIntOrNull()?.let { it to alerts } }
                .filter { !it.second.isOff }
                .toMap()
        }
        if (restoredStations.isNotEmpty()) onRestored(restoredStations)
    }

    /** This device's row, created or refreshed when its tokens, DND, language, Pro or age call for it. */
    private suspend fun deviceId(api: PushApi, deviceId: String, fcmToken: String): Int {
        val (dnd, known) = synchronized(lock) { store.dnd to store.deviceRowId }
        val payload = PushDevicePayload.make(
            deviceId = deviceId,
            fcmToken = fcmToken,
            dnd = dnd,
            isPro = profile.isPro(),
            notificationsAllowed = profile.notificationsAllowed(),
            locale = profile.locale(),
            appVersion = profile.appVersion,
            debug = profile.isDebug,
            now = clock()
        )
        val current = synchronized(lock) {
            isDeviceCurrent(
                syncedToken = store.syncedDeviceToken,
                token = payload.deviceToken,
                syncedFcmToken = store.syncedFcmToken,
                fcmToken = payload.fcmToken,
                lastSync = store.lastDeviceSyncAt,
                syncedProfile = store.syncedProfile,
                profile = payload.profile,
                now = clock()
            )
        }
        if (known != null && current) return known

        val id = api.upsertDevice(payload)
        synchronized(lock) {
            if (id != known) store.synced = emptyMap()
            store.deviceRowId = id
            store.syncedDeviceToken = payload.deviceToken
            payload.fcmToken?.let { store.syncedFcmToken = it }
            store.syncedProfile = payload.profile
            store.lastDeviceSyncAt = clock()
        }
        return id
    }

    private fun config(baseUrl: String): PushConfig? {
        val id = identity.id() ?: return null
        val secret = identity.secret() ?: return null
        return PushConfig.make(baseUrl, id, secret)
    }

    /** Runs [block]; on a push API failure logs it, applies its [recovery] and returns null. */
    private suspend fun <T> attempt(what: String, block: suspend () -> T): T? = try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        Log.w(TAG, "$what failed: ${e.message}")
        recover(e)
        null
    }

    /**
     * After either recovery the next run (a change, launch or backoff retry, never at once, so a
     * refusing API can't spin it) registers a row and, seeing a new id, writes every alert again.
     */
    private fun recover(error: Exception) {
        val recovery = recovery(error)
        if (recovery == Recovery.NONE) return
        if (recovery == Recovery.NEW_IDENTITY) identity.reset()
        synchronized(lock) {
            store.deviceRowId = null
            store.syncedDeviceToken = null
            store.syncedFcmToken = null
            store.syncedProfile = null
            store.lastDeviceSyncAt = null
            store.synced = emptyMap()
        }
    }

    private fun saveWanted(wanted: Map<String, StationAlerts>) {
        store.wanted = wanted
        alerted.value = alertedFrom(wanted)
    }

    enum class Recovery {
        /** Another install holds this device id (403): start over with a new id and secret, and a new row. */
        NEW_IDENTITY,

        /** The row is gone (404, retired by a newer registration): register again with the same identity. */
        REGISTER,
        NONE
    }

    companion object {
        /** A launch refreshes `last_seen_at` at most this often. */
        val DEVICE_REFRESH_INTERVAL: Duration = Duration.ofHours(6)

        /** Sliders send a value per step; write once they settle. */
        const val DEBOUNCE_MILLIS = 800L

        private const val TAG = "PushSync"

        fun alertedFrom(wanted: Map<String, StationAlerts>): Map<Int, StationAlerts> =
            wanted.mapNotNull { (key, alerts) ->
                key.toIntOrNull()?.takeIf { !alerts.isOff }?.let { it to alerts }
            }.toMap()

        fun recovery(error: Throwable): Recovery = when ((error as? PushException.Server)?.statusCode) {
            403 -> Recovery.NEW_IDENTITY
            404 -> Recovery.REGISTER
            else -> Recovery.NONE
        }

        /** Whether "cancel all" must be remembered until it can be done: with a row to archive, or while a restore may still find one. */
        fun keepsCancelAll(hasDevice: Boolean, restored: Boolean): Boolean = hasDevice || !restored

        /** A restore takes the stored DND window only on a fresh install, and never over a change made here meanwhile. */
        fun restoresDnd(isFreshInstall: Boolean, editedLocally: Boolean): Boolean = isFreshInstall && !editedLocally

        /** The push API's alerts under any not yet written here, unless "cancel all" was tapped meanwhile. */
        fun restoredWanted(
            local: Map<String, StationAlerts>,
            remote: Map<String, StationAlerts>,
            cancelPending: Boolean
        ): Map<String, StationAlerts> = if (cancelPending) local else remote + local

        /** Always once a row exists (so a token change alone is written), otherwise only for an alert to turn on. */
        fun needsDevice(hasDevice: Boolean, pending: Map<String, StationAlerts>): Boolean =
            hasDevice || pending.values.any { !it.isOff }

        /**
         * Whether the row already holds these tokens and was refreshed recently enough to skip the
         * upsert. A new FCM token is always written; a missing one is not a change. A new
         * profile (language, Pro, notifications, DND) is written too.
         */
        fun isDeviceCurrent(
            syncedToken: String?,
            token: String,
            syncedFcmToken: String?,
            fcmToken: String?,
            lastSync: Instant?,
            syncedProfile: String? = null,
            profile: String? = null,
            now: Instant = Instant.now()
        ): Boolean {
            if (syncedToken != token || lastSync == null) return false
            if (fcmToken != null && fcmToken != syncedFcmToken) return false
            if (profile != null && profile != syncedProfile) return false
            return Duration.between(lastSync, now) < DEVICE_REFRESH_INTERVAL
        }
    }
}
