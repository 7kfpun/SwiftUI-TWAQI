package com.kfpun.twaqi.push

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.kfpun.twaqi.analytics.Analytics
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** The alert card's state: the switches and sliders, and whether other stations are at the limit. */
data class StationAlertsUiState(val setting: StationAlertSetting, val isAtCap: Boolean) {
    /** Only other stations being at the limit locks a switch that is off; one that is on stays switchable off. */
    val pollutionLocked: Boolean get() = isAtCap && !setting.isPollutionNotificationEnabled
    val cleanlinessLocked: Boolean get() = isAtCap && !setting.isCleanlinessNotificationEnabled
}

/**
 * A station page's alert card (iOS `SettingsRowViewModel`). A switch or slider move is saved on
 * the phone at once, the push API copy once the slider stops. Alerts changed elsewhere (cleared
 * from Favourites, switched on by favouriting, restored) follow here without being written back.
 *
 * @param siteId the station cam's MOENV site id, stored with the alerts when known (iOS matches it
 *   from the cam list; the Android cam list arrives with FOX-92, so it is null until then).
 */
class StationAlertsViewModel(
    private val stationId: Int,
    private val siteId: String?,
    private val alerts: FavouriteAlerts,
    private val logger: EventLogger
) : ViewModel() {
    private val state = MutableStateFlow(
        StationAlertsUiState(alerts.setting(stationId), alerts.isAtCap(stationId))
    )
    val uiState: StateFlow<StationAlertsUiState> = state.asStateFlow()

    private var loggedAlertLimit = false

    init {
        logAlertLimitIfShown()
        viewModelScope.launch {
            // Any station's change can move the limit.
            alerts.alertedStationIds.collect { ids ->
                state.update { it.copy(isAtCap = FavouriteAlerts.isAtCap(ids, excluding = stationId)) }
                logAlertLimitIfShown()
            }
        }
        viewModelScope.launch {
            alerts.changes.collect { change -> if (change.stationId == stationId) follow(change) }
        }
    }

    /** The user moved a switch or slider. Returns false when it couldn't switch on (the limit). */
    fun onChange(setting: StationAlertSetting): Boolean {
        if (!alerts.write(setting, stationId, siteId)) {
            // Other stations reached the limit since this page last looked: the switches go back off and lock.
            state.update {
                StationAlertsUiState(
                    it.setting.copy(isPollutionNotificationEnabled = false, isCleanlinessNotificationEnabled = false),
                    isAtCap = true
                )
            }
            logAlertLimitIfShown()
            return false
        }
        state.update { it.copy(setting = setting) }
        if (setting.isOn) alerts.addToFavourites(stationId)
        alerts.post(AlertChange(stationId, isOn = setting.isOn))
        return true
    }

    private fun follow(change: AlertChange) {
        val current = state.value.setting
        if (!change.isOn) {
            if (!current.isOn) return
            state.update {
                it.copy(
                    setting = current.copy(
                        isPollutionNotificationEnabled = false,
                        isCleanlinessNotificationEnabled = false
                    )
                )
            }
        } else if (change.setting != null && !current.isOn) {
            state.update { it.copy(setting = change.setting) }
        }
    }

    /** `alert_limit_shown` is logged once per station page, not on every read. */
    private fun logAlertLimitIfShown() {
        if (!state.value.isAtCap || loggedAlertLimit) return
        loggedAlertLimit = true
        logger.log(Analytics.ALERT_LIMIT_SHOWN, mapOf("stationId" to stationId.toString()))
    }

    companion object {
        fun factory(stationId: Int, siteId: String?, graph: PushGraph.Instances): ViewModelProvider.Factory =
            viewModelFactory {
                initializer { StationAlertsViewModel(stationId, siteId, graph.favouriteAlerts, graph.logger) }
            }
    }
}
