package com.kfpun.twaqi.ui.favourites

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.kfpun.twaqi.TwaqiApplication
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.data.favourites.FavouritesRepository
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.repository.AirQualityRepository
import com.kfpun.twaqi.data.repository.DataResult
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** What the Favourites list reads, so the view model can be tested without the network. */
interface FavouriteReadings {
    suspend fun saved(stationIds: List<Int>): List<Pollutant>
    suspend fun current(stationIds: List<Int>): DataResult<List<Pollutant>>
}

class RepositoryFavouriteReadings(private val repository: AirQualityRepository) : FavouriteReadings {
    override suspend fun saved(stationIds: List<Int>): List<Pollutant> =
        repository.savedPollutants(stationIds).map { it.value }

    override suspend fun current(stationIds: List<Int>): DataResult<List<Pollutant>> =
        repository.currentPollutants(stationIds)
}

/**
 * @property favouriteIds every saved favourite, the reader's order.
 * @property pollutants the favourites that have a reading to show, in that order.
 * @property isShowingLastGood the readings are the last good ones saved, because the request failed.
 * @property loadFailed the request failed and nothing was saved to show either.
 * @property alertedStationIds favourites with an alert on (FOX-57).
 * @property pendingRemoval stations waiting on the reader before they leave, because one has alerts on.
 */
data class FavouritesUiState(
    val favouriteIds: List<Int> = emptyList(),
    val pollutants: List<Pollutant> = emptyList(),
    val isShowingLastGood: Boolean = false,
    val loadFailed: Boolean = false,
    val alertedStationIds: Set<Int> = emptySet(),
    val pendingRemoval: List<Int>? = null
)

/** The Favourites tab (iOS `FavouriteListViewModel` and the list's edit actions). */
class FavouritesViewModel(
    private val favourites: FavouritesRepository,
    private val readings: FavouriteReadings,
    private val logEvent: (String, Map<String, String>) -> Unit = { _, _ -> }
) : ViewModel() {
    private val state = MutableStateFlow(FavouritesUiState(favouriteIds = favourites.favourites.value))
    val uiState: StateFlow<FavouritesUiState> = state.asStateFlow()

    init {
        viewModelScope.launch {
            favourites.alerts.alertedStationIds.collect { ids -> state.update { it.copy(alertedStationIds = ids) } }
        }
        viewModelScope.launch {
            // Favourited or removed on a station page: the list follows.
            favourites.favourites.collect { ids ->
                val before = state.value.favouriteIds
                state.update { s -> s.copy(favouriteIds = ids, pollutants = ordered(s.pollutants, ids)) }
                if (ids.any { it !in before }) refresh()
            }
        }
    }

    fun refresh() {
        viewModelScope.launch {
            val ids = favourites.favourites.value
            if (ids.isEmpty()) {
                state.update { it.copy(pollutants = emptyList(), isShowingLastGood = false, loadFailed = false) }
                return@launch
            }
            // The last saved readings at once, so saved favourites never look like none while the
            // request is on the wire (or failing).
            showSaved(ids)
            state.update { it.copy(loadFailed = false) }

            when (val result = readings.current(ids)) {
                is DataResult.Fresh -> state.update {
                    it.copy(
                        pollutants = ordered(result.value, favourites.favourites.value),
                        isShowingLastGood = false,
                        loadFailed = false
                    )
                }

                is DataResult.Stale, is DataResult.Failed -> {
                    showSaved(favourites.favourites.value)
                    state.update {
                        it.copy(isShowingLastGood = it.pollutants.isNotEmpty(), loadFailed = it.pollutants.isEmpty())
                    }
                }
            }
        }
    }

    /** The saved favourites, each from the list on screen or else the last good reading on disk. */
    private suspend fun showSaved(ids: List<Int>) {
        val saved = readings.saved(ids).associateBy { it.stationId }
        state.update { s ->
            val shown = s.pollutants.associateBy { it.stationId }
            s.copy(pollutants = ids.mapNotNull { shown[it] ?: saved[it] })
        }
    }

    // Removing

    /** Removes at once, unless an alert would go with it: then asks first. */
    fun requestRemove(stationIds: List<Int>) {
        if (favourites.needsConfirmation(stationIds)) {
            state.update { it.copy(pendingRemoval = stationIds) }
        } else {
            commitRemoval(stationIds)
        }
    }

    fun confirmRemoval() {
        state.value.pendingRemoval?.let(::commitRemoval)
    }

    fun cancelRemoval() {
        state.update { it.copy(pendingRemoval = null) }
    }

    private fun commitRemoval(stationIds: List<Int>) {
        val removed = favourites.remove(stationIds)
        state.update { s ->
            s.copy(pendingRemoval = null, pollutants = s.pollutants.filterNot { it.stationId in stationIds })
        }
        // One per station, as everywhere else.
        removed.forEach {
            logEvent(Analytics.FAVOURITE_STATION_SAVED, mapOf("label" to "off", "stationId" to it.toString()))
        }
    }

    // Reordering

    /** Moves the row at [from] to [to] in the list on screen and saves the order. Alerts stay as they are. */
    fun move(from: Int, to: Int) {
        val list = state.value.pollutants.toMutableList()
        if (from !in list.indices || to !in list.indices || from == to) return
        list.add(to, list.removeAt(from))
        state.update { it.copy(pollutants = list) }
        // Saved stations the list doesn't show keep their place after the rest.
        favourites.reorder(list.map { it.stationId })
        logEvent(Analytics.FAVOURITE_STATION_REORDERED, emptyMap())
    }

    /**
     * Saves a dropped drag: [stationIds] in their new order. By id, so it holds even when the list
     * was refreshed while the row was held; saved stations it doesn't name keep their place after
     * the rest (`FavouritesRepository.reorder`). Alerts stay as they are.
     */
    fun reorder(stationIds: List<Int>) {
        val before = favourites.favourites.value
        favourites.reorder(stationIds)
        val saved = favourites.favourites.value
        if (saved == before) return
        state.update { s ->
            val rank = saved.withIndex().associate { (i, id) -> id to i }
            s.copy(pollutants = s.pollutants.sortedBy { rank[it.stationId] ?: Int.MAX_VALUE })
        }
        logEvent(Analytics.FAVOURITE_STATION_REORDERED, emptyMap())
    }

    private fun ordered(list: List<Pollutant>, order: List<Int>): List<Pollutant> {
        val byId = list.associateBy { it.stationId }
        return order.mapNotNull { byId[it] }
    }

    companion object {
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer {
                val app = this[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY] as TwaqiApplication
                FavouritesViewModel(
                    app.container.favourites,
                    RepositoryFavouriteReadings(app.container.airQuality),
                    logEvent = { name, params -> Analytics.logEvent(app as Application, name, params) }
                )
            }
        }
    }
}
