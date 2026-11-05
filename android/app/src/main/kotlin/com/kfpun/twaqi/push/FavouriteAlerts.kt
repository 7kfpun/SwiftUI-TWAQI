package com.kfpun.twaqi.push

import com.kfpun.twaqi.analytics.Analytics
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

/** The favourites list as alerts need it: FOX-55's `FavouritesRepository` has the same two calls. */
interface FavouriteStations {
    fun contains(stationId: Int): Boolean

    /** Adds [stationId] at the end; returns whether it was added. */
    fun add(stationId: Int): Boolean
}

/**
 * A station's alerts switched on or off somewhere (iOS `FavouriteAlerts.changed`): on its
 * station page, cleared from Favourites, switched on by favouriting, or restored.
 *
 * @property setting the alerts just switched on elsewhere (a new favourite, a restore), for a
 *   station page already showing the switches to take as they are.
 * @property alertedStationCount with [setting]: stations with an alert on, this one included.
 */
data class AlertChange(
    val stationId: Int,
    val isOn: Boolean,
    val setting: StationAlertSetting? = null,
    val alertedStationCount: Int? = null
)

/** Logs analytics events; [Analytics.logEvent] in the app. */
fun interface EventLogger {
    fun log(name: String, parameters: Map<String, String>)
}

/**
 * Keeps a station's alerts and its place in Favourites together (iOS `FavouriteAlerts`): a
 * station with an alert on is always a favourite, and leaving Favourites turns its alerts off.
 * Reordering Favourites never comes here. Alerts are keyed by station id, and at most
 * [MAX_ALERTED_STATIONS] stations have them.
 *
 * Alerts live in [store] ([PushSync]): written on the phone at once, so a change here always
 * takes, and copied to the push API in the background, retried until it lands. Call from the
 * main thread.
 */
class FavouriteAlerts(
    private val store: AlertStore,
    private val favourites: () -> FavouriteStations,
    private val notificationsDenied: () -> Boolean,
    private val logger: EventLogger,
    scope: CoroutineScope
) {
    private val changeEvents = MutableSharedFlow<AlertChange>(extraBufferCapacity = 64)

    /** Every [AlertChange], for station pages that are open. */
    val changes: SharedFlow<AlertChange> = changeEvents.asSharedFlow()

    /** Stations with an alert on (FOX-55's `FavouriteAlertsGateway.alertedStationIds`). */
    val alertedStationIds: StateFlow<Set<Int>> = store.alertedStations
        .map { it.keys }
        .stateIn(scope, SharingStarted.Eagerly, store.alertedStations.value.keys)

    private fun currentAlerted(): Set<Int> = store.alertedStations.value.keys

    fun isOn(stationId: Int): Boolean = stationId in currentAlerted()

    fun setting(stationId: Int): StationAlertSetting = StationAlertSetting.from(store.alerts(stationId))

    fun isAtCap(stationId: Int): Boolean = isAtCap(currentAlerted(), excluding = stationId)

    fun post(change: AlertChange) {
        changeEvents.tryEmit(change)
    }

    // MARK: - The station page's switches

    /**
     * Writes a station's alerts as set on its page; the push API copy waits for a slider to stop.
     *
     * Returns false, writing nothing, when it would switch on a station past the cap: checked
     * here, against what is saved, so two screens whose switches both looked unlocked can't
     * both get past it. Changing or switching off a station that is on always works.
     */
    fun write(setting: StationAlertSetting, stationId: Int, siteId: String?): Boolean {
        val alerts = StationAlerts.from(setting)
        val alerted = currentAlerted()
        if (!alerts.isOff && stationId !in alerted && isAtCap(alerted, excluding = stationId)) return false
        store.stationChanged(stationId, siteId, alerts, settled = false)
        return true
    }

    /** An alert switched on makes the station a favourite, so it is in the list where it can be found and removed. */
    fun addToFavourites(stationId: Int) {
        if (!favourites().add(stationId)) return
        logger.log(
            FAVOURITE_STATION_SAVED,
            mapOf("label" to "on", "stationId" to stationId.toString(), "source" to "alert")
        )
    }

    // MARK: - Leaving Favourites turns alerts off

    /** Turns both of a station's alerts off as it leaves Favourites; nothing to do when they're off. */
    fun clear(stationId: Int) {
        if (!isOn(stationId)) return
        store.stationChanged(stationId, null, StationAlerts.OFF, settled = true)
        logger.log(Analytics.STATION_ALERTS_CLEARED_BY_UNFAVOURITE, mapOf("stationId" to stationId.toString()))
        post(AlertChange(stationId, isOn = false))
    }

    // MARK: - Help's "cancel all"

    /** Turns every station's alerts off, including any in the push API for stations this install never opened. */
    fun cancelAll() {
        val alerted = currentAlerted()
        store.cancelAll()
        alerted.sorted().forEach { post(AlertChange(it, isOn = false)) }
    }

    // MARK: - A new favourite switches its alerts on (FOX-31)

    /** What favouriting a station does to its alerts. */
    sealed interface NewFavouriteOutcome {
        /** Switched on with [DEFAULT_ALERTS]. */
        data class Enabled(val setting: StationAlertSetting) : NewFavouriteOutcome

        /** Already on: left as they are. */
        data object AlreadyOn : NewFavouriteOutcome

        /** [MAX_ALERTED_STATIONS] other stations already have alerts. */
        data object CapReached : NewFavouriteOutcome

        /** Notifications are turned off for the app. */
        data object NotificationsDenied : NewFavouriteOutcome

        /** The station stopped being a favourite before it was written. */
        data object NotChanged : NewFavouriteOutcome
    }

    /**
     * Switches a just-favourited station's alerts on, unless it is past the cap or notifications
     * are off; the favourite stands either way. [isStillFavourite] is asked just before writing.
     * Do-not-disturb is not touched.
     */
    fun enableForNewFavourite(stationId: Int, siteId: String?, isStillFavourite: () -> Boolean): NewFavouriteOutcome {
        val outcome = when {
            notificationsDenied() -> NewFavouriteOutcome.NotificationsDenied

            !isStillFavourite() -> NewFavouriteOutcome.NotChanged

            else -> {
                val alerted = currentAlerted()
                val decision = newFavouriteDecision(alerted, stationId)
                if (decision is NewFavouriteOutcome.Enabled) {
                    store.stationChanged(stationId, siteId, StationAlerts.from(decision.setting), settled = true)
                    post(
                        AlertChange(
                            stationId,
                            isOn = true,
                            setting = decision.setting,
                            alertedStationCount =
                                alerted.size + 1
                        )
                    )
                }
                decision
            }
        }
        val name = when (outcome) {
            is NewFavouriteOutcome.Enabled -> "enabled"
            NewFavouriteOutcome.AlreadyOn -> "already_on"
            NewFavouriteOutcome.CapReached -> "cap_reached"
            NewFavouriteOutcome.NotificationsDenied -> "notifications_denied"
            NewFavouriteOutcome.NotChanged -> "not_changed"
        }
        logger.log(Analytics.STATION_ALERTS_ON_FAVOURITE, mapOf("outcome" to name, "stationId" to stationId.toString()))
        return outcome
    }

    // MARK: - Restored after a reinstall

    /** Restored alerts reach the pages showing them, and their stations are favourites again. */
    fun restored(stations: Map<Int, StationAlerts>) {
        if (stations.isEmpty()) return
        val list = favourites()
        stations.keys.sorted().forEach { if (!list.contains(it)) list.add(it) }
        val count = currentAlerted().size
        stations.forEach { (id, alerts) ->
            post(AlertChange(id, isOn = true, setting = StationAlertSetting.from(alerts), alertedStationCount = count))
        }
    }

    companion object {
        /**
         * Alerts can be on for at most this many stations; the station page locks its switches
         * once other stations reach it. Enforced in the app only: the Worker takes whatever the
         * app sends (iOS `FavouriteAlerts.maxAlertedStations`).
         */
        const val MAX_ALERTED_STATIONS = 3

        /** iOS `TrackingManager`'s `favourite_station_saved`. */
        const val FAVOURITE_STATION_SAVED = "favourite_station_saved"

        /**
         * What favouriting switches on: the "above" alert at the station page's starting
         * threshold (AQI 120). The "below" alert stays off: it is the clean-air nudge.
         */
        val DEFAULT_ALERTS =
            StationAlertSetting(isPollutionNotificationEnabled = true, isCleanlinessNotificationEnabled = false)

        /** [MAX_ALERTED_STATIONS] *other* stations already have alerts, so this one's switches that are off stay locked. */
        fun isAtCap(alertedStationIds: Set<Int>, excluding: Int): Boolean =
            (alertedStationIds - excluding).size >= MAX_ALERTED_STATIONS

        fun newFavouriteDecision(alertedStationIds: Set<Int>, stationId: Int): NewFavouriteOutcome = when {
            stationId in alertedStationIds -> NewFavouriteOutcome.AlreadyOn
            isAtCap(alertedStationIds, excluding = stationId) -> NewFavouriteOutcome.CapReached
            else -> NewFavouriteOutcome.Enabled(DEFAULT_ALERTS)
        }
    }
}
