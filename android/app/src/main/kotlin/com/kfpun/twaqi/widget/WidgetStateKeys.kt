package com.kfpun.twaqi.widget

import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import com.kfpun.twaqi.data.model.AirIndexType
import java.time.Instant

/**
 * One widget's state in Glance's per-widget DataStore (`PreferencesGlanceStateDefinition`): its
 * settings, its page state (iOS `WidgetPageStore`, which needs one key per widget because WidgetKit
 * doesn't tell widgets apart; Android gives every widget its own id and file), whether the last
 * refresh failed, and a version that every redraw bumps so a running session recomposes.
 */
object WidgetStateKeys {
    val STATION = stringPreferencesKey("station")
    val INDEX = stringPreferencesKey("index")
    val CONFIGURED = booleanPreferencesKey("configured")
    val PAGE_STATION = intPreferencesKey("pageStationId")
    val PAGE_INDEX = stringPreferencesKey("pageIndex")
    val TAPPED_AT = longPreferencesKey("tappedAt")
    val REFRESHED_AT = longPreferencesKey("refreshedAt")
    val OFFLINE = booleanPreferencesKey("offline")
    val VERSION = longPreferencesKey("version")

    fun config(prefs: Preferences): WidgetConfig = WidgetConfig(
        station = StationChoice.fromId(prefs[STATION]),
        index = AirIndexType.fromKey(prefs[INDEX]) ?: AirIndexType.AQI
    )

    /** Saves [config] and starts the page state afresh, as iOS keys the page state by the configuration. */
    fun writeConfig(prefs: MutablePreferences, config: WidgetConfig) {
        prefs[STATION] = config.station.id
        prefs[INDEX] = config.index.key
        prefs[CONFIGURED] = true
        writePageState(prefs, WidgetPageState(refreshedAt = pageState(prefs).refreshedAt))
    }

    fun pageState(prefs: Preferences): WidgetPageState = WidgetPageState(
        stationId = prefs[PAGE_STATION],
        index = prefs[PAGE_INDEX],
        tappedAt = prefs[TAPPED_AT]?.let(Instant::ofEpochMilli),
        refreshedAt = prefs[REFRESHED_AT]?.let(Instant::ofEpochMilli)
    )

    fun writePageState(prefs: MutablePreferences, state: WidgetPageState) {
        prefs.setOrRemove(PAGE_STATION, state.stationId)
        prefs.setOrRemove(PAGE_INDEX, state.index)
        prefs.setOrRemove(TAPPED_AT, state.tappedAt?.toEpochMilli())
        prefs.setOrRemove(REFRESHED_AT, state.refreshedAt?.toEpochMilli())
    }

    /** Marks the state changed, so the widget redraws from what is saved. */
    fun bumpVersion(prefs: MutablePreferences, now: Instant) {
        prefs[VERSION] = maxOf(now.toEpochMilli(), (prefs[VERSION] ?: 0L) + 1)
    }

    private fun <T> MutablePreferences.setOrRemove(key: Preferences.Key<T>, value: T?) {
        if (value == null) remove(key) else set(key, value)
    }
}
