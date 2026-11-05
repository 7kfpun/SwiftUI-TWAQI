package com.kfpun.twaqi.watch.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.kfpun.twaqi.watch.WatchSurfaces
import com.kfpun.twaqi.watch.data.HistoryPoint
import com.kfpun.twaqi.watch.data.WatchApi
import com.kfpun.twaqi.watch.data.WatchPro
import com.kfpun.twaqi.watch.data.WatchReading
import com.kfpun.twaqi.watch.data.WatchRepository
import com.kfpun.twaqi.watch.data.WatchStore
import com.kfpun.twaqi.watch.relay.PhoneRelay
import java.io.IOException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** How the station on screen was chosen (iOS `WatchModel.Source`). */
enum class StationSource {
    /** Picked by hand in the station list. */
    PINNED,

    /** Home, from the reader's location. */
    CLOSEST,

    /** Home without a location: the station nearest 中正. */
    FALLBACK
}

data class WatchUiState(
    val reading: WatchReading?,
    val home: WatchReading?,
    val history: List<HistoryPoint> = emptyList(),
    val source: StationSource,
    val stations: List<WatchReading> = emptyList(),
    /** The phone's favourites with their latest readings, in the reader's order. */
    val favourites: List<WatchReading> = emptyList(),
    val isLoading: Boolean = false,
    val isLoadingHistory: Boolean = false,
    val failed: Boolean = false,
    val isPro: Boolean,
    val developerMode: Boolean,
    val proOverride: WatchPro.Override
) {
    val isHome: Boolean get() = source != StationSource.PINNED
}

/** The watch app's state (iOS `WatchModel`): the reading on screen, its history, the station list. */
class WatchModel(application: Application) : AndroidViewModel(application) {
    private val app = application
    private val store = WatchStore.get(application)
    private val api = WatchRepository.api()
    private val locator = Locator(application)

    private val mutableState = MutableStateFlow(
        WatchUiState(
            reading = store.latestReading,
            home = store.homeReading,
            source = if (store.pinnedStationId == null) StationSource.FALLBACK else StationSource.PINNED,
            favourites = cachedFavourites(emptyList()),
            isPro = WatchPro.isUnlocked(store),
            developerMode = store.developerMode,
            proOverride = WatchPro.Override.fromId(store.proOverride)
        )
    )
    val state: StateFlow<WatchUiState> = mutableState.asStateFlow()

    init {
        // Pro, favourites and the developer switches can change from the phone or the picker.
        viewModelScope.launch {
            store.changes.collect {
                mutableState.update { current ->
                    current.copy(
                        isPro = WatchPro.isUnlocked(store),
                        favourites = cachedFavourites(current.stations),
                        developerMode = store.developerMode,
                        proOverride = WatchPro.Override.fromId(store.proOverride)
                    )
                }
            }
        }
    }

    /** Re-reads the phone's state the Data Layer holds; a Pro bought on the phone lands here. */
    fun checkPro() {
        viewModelScope.launch { PhoneRelay.refreshFromPhone(app) }
    }

    fun refresh() {
        if (mutableState.value.isLoading) return
        mutableState.update { it.copy(isLoading = true) }
        viewModelScope.launch {
            try {
                val pinned = store.pinnedStationId
                val reading = if (pinned != null) {
                    mutableState.update { it.copy(source = StationSource.PINNED) }
                    api.currentPollutant(pinned)
                } else {
                    // Home needs the whole list to find the nearest station, which also fills the picker.
                    val stations = api.currentPollutants()
                    val location = locator.current()
                    val nearest = WatchApi.closest(
                        location?.latitude ?: WatchApi.DEFAULT_LATITUDE,
                        location?.longitude ?: WatchApi.DEFAULT_LONGITUDE,
                        stations
                    )
                    if (nearest != null) {
                        store.homeReading = nearest
                        store.homeIsLocated = location != null
                    }
                    mutableState.update {
                        it.copy(
                            stations = stations,
                            favourites = cachedFavourites(stations),
                            source = if (location == null) StationSource.FALLBACK else StationSource.CLOSEST,
                            home = nearest ?: it.home
                        )
                    }
                    nearest
                } ?: throw WatchApiFailure()

                if (reading.stationId != mutableState.value.reading?.stationId) {
                    mutableState.update { it.copy(history = emptyList()) }
                }
                show(reading)
                mutableState.update { it.copy(failed = false, isLoadingHistory = true) }

                // The reading is already on screen; a missing chart shouldn't fail it.
                val history = runCatching { api.history(reading.stationId, HISTORY_HOURS) }.getOrDefault(emptyList())
                mutableState.update { it.copy(history = history, isLoadingHistory = false) }
            } catch (e: IOException) {
                mutableState.update { it.copy(failed = true, isLoadingHistory = false) }
            } finally {
                mutableState.update { it.copy(isLoading = false) }
            }
            loadFavourites()
        }
    }

    fun loadStations() {
        viewModelScope.launch {
            try {
                val stations = api.currentPollutants()
                mutableState.update {
                    it.copy(stations = stations, favourites = cachedFavourites(stations), failed = false)
                }
            } catch (e: IOException) {
                mutableState.update { it.copy(failed = true) }
            }
        }
    }

    /** The favourites' current readings, cached so they list offline. */
    fun loadFavourites() {
        val ids = store.favouriteStationIds
        if (ids.isEmpty()) return
        viewModelScope.launch {
            val fresh = runCatching { api.currentPollutants(ids) }.getOrNull() ?: return@launch
            store.cacheFavouriteReadings(fresh)
            mutableState.update { it.copy(favourites = cachedFavourites(it.stations)) }
        }
    }

    /** Pins a station, or returns to home with null. */
    fun pin(reading: WatchReading?) {
        store.pinnedStationId = reading?.stationId
        if (reading != null) {
            mutableState.update { it.copy(source = StationSource.PINNED, history = emptyList()) }
            show(reading)
        }
        refresh()
    }

    fun setProOverride(override: WatchPro.Override) {
        store.proOverride = override.id
        WatchSurfaces.requestUpdate(app)
    }

    fun toggleDeveloperMode() {
        store.developerMode = !store.developerMode
    }

    private fun show(reading: WatchReading) {
        mutableState.update { it.copy(reading = reading) }
        store.latestReading = reading
        WatchSurfaces.requestUpdate(app)
    }

    /** Favourites in the phone's order: a fresh station-list reading, else the cached one. */
    private fun cachedFavourites(stations: List<WatchReading>): List<WatchReading> {
        val fromList = stations.associateBy { it.stationId }
        val cached = store.favouriteReadings.associateBy { it.stationId }
        return store.favouriteStationIds.mapNotNull { fromList[it] ?: cached[it] }
    }

    private class WatchApiFailure : IOException("no reading")

    companion object {
        /** Half the phone's 24: a day of bars is too thin to read on a watch. */
        const val HISTORY_HOURS = 12
    }
}
