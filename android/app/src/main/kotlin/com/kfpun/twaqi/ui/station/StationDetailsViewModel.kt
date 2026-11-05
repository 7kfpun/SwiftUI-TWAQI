package com.kfpun.twaqi.ui.station

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.kfpun.twaqi.TwaqiApplication
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.data.favourites.FavouritesRepository
import com.kfpun.twaqi.data.model.HistoricalPollutant
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.model.Station
import com.kfpun.twaqi.data.model.StationHistory
import com.kfpun.twaqi.data.repository.AirQualityRepository
import com.kfpun.twaqi.data.repository.DataResult
import com.kfpun.twaqi.data.repository.NoCurrentReadingException
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** What the station page reads, so the view model can be tested without the network. */
interface StationDataSource {
    /** The last good reading saved, from either endpoint; null when none (or a week old). */
    suspend fun savedPollutant(stationId: Int): Pollutant?
    suspend fun currentPollutant(stationId: Int): DataResult<Pollutant>
    suspend fun history(stationId: Int): DataResult<StationHistory>
}

class RepositoryStationDataSource(private val repository: AirQualityRepository) : StationDataSource {
    override suspend fun savedPollutant(stationId: Int): Pollutant? =
        repository.savedPollutants(listOf(stationId)).firstOrNull()?.value

    override suspend fun currentPollutant(stationId: Int): DataResult<Pollutant> =
        repository.currentPollutant(stationId)

    override suspend fun history(stationId: Int): DataResult<StationHistory> = repository.history(stationId)
}

/**
 * What the station page shows (iOS `DetailsViewModel`'s published state).
 *
 * @property station the station record from the history request; null until it loads, or when
 *   the API has none for this id.
 * @property pollutant the current reading: live, or the last good one saved.
 * @property history the last 24 hours, oldest first.
 * @property isShowingLastGood [pollutant] is the last good reading saved, because the latest
 *   request failed.
 * @property loadFailed both requests failed and there was nothing saved to show.
 * @property isNotReporting the API answered and has no current reading for this station (retired,
 *   or offline for maintenance). Not an outage.
 * @property stationLoadFailed the station record didn't load, so there is no alerts row (FOX-57)
 *   to show; the page says why instead.
 * @property confirmingUnfavourite unfavouriting waits on the reader: it would also turn alerts off.
 */
data class StationDetailsUiState(
    val stationId: Int,
    val station: Station? = null,
    val pollutant: Pollutant? = null,
    val history: List<HistoricalPollutant> = emptyList(),
    val loading: Boolean = true,
    val isShowingLastGood: Boolean = false,
    val loadFailed: Boolean = false,
    val isNotReporting: Boolean = false,
    val stationLoadFailed: Boolean = false,
    val isFavourite: Boolean = false,
    val confirmingUnfavourite: Boolean = false
) {
    /**
     * Whether this id is a station at all: its record or a reading loaded, now or from the cache.
     * Until then the heart can't add it, so a page opened for an unknown id never puts that id in
     * Favourites (iOS FOX-74). Removing one already there is always allowed.
     */
    val canAddFavourite: Boolean get() = station != null || pollutant != null

    val canToggleFavourite: Boolean get() = isFavourite || canAddFavourite

    /** Most recent reading's publish time, preferring the current reading over history. */
    val latestPublishTime: String? get() = pollutant?.publishTime ?: history.lastOrNull()?.publishTime

    /**
     * The newest history point is from the last day, so the 24-hour chart is still about today. A
     * station that stopped reporting long ago still returns its last 24 points.
     */
    fun hasRecentHistory(now: Instant): Boolean {
        val date = history.lastOrNull()?.publishedAt ?: return false
        return Duration.between(date, now) < Duration.ofHours(24)
    }

    /**
     * The current reading when there is one, else the newest history point, unless the station has
     * stopped reporting, when that point may be years old and must not be shown as the air now.
     */
    fun currentAqi(now: Instant): Double {
        pollutant?.let { return it.aqi }
        if (isNotReporting && !hasRecentHistory(now)) return 0.0
        return history.lastOrNull()?.aqi ?: 0.0
    }

    /** A retired station still returns its last 24 points, which would read as today's trend. */
    fun showsHistory(now: Instant): Boolean = !isNotReporting || hasRecentHistory(now)
}

/**
 * The station page (iOS `DetailsViewModel`): the current reading and the 24-hour history, each
 * from its own request, with the last good reading shown at once and kept when a refresh fails.
 */
class StationDetailsViewModel(
    private val stationId: Int,
    private val source: StationDataSource,
    private val favourites: FavouritesRepository,
    private val logEvent: (String, Map<String, String>) -> Unit = { _, _ -> }
) : ViewModel() {
    private val state = MutableStateFlow(
        StationDetailsUiState(stationId = stationId, isFavourite = favourites.contains(stationId))
    )
    val uiState: StateFlow<StationDetailsUiState> = state.asStateFlow()

    /**
     * Answers from the latest [refresh], so `loadFailed` is decided once both requests have
     * answered; answers from an older pair are not counted.
     */
    private var generation = 0
    private val answers = mutableListOf<Boolean>()
    private var loggedOpen = false

    init {
        viewModelScope.launch {
            favourites.favourites.collect { ids -> state.update { it.copy(isFavourite = stationId in ids) } }
        }
    }

    /** Loads the page; the screen calls it each time it shows (iOS `onAppear`). */
    fun refresh() {
        generation += 1
        val generation = generation
        answers.clear()
        state.update { it.copy(loadFailed = false, loading = true) }

        viewModelScope.launch {
            // The last good reading at once, so a station opened offline is not a blank page.
            if (state.value.pollutant == null) {
                source.savedPollutant(stationId)?.let { saved ->
                    state.update { if (it.pollutant == null) it.copy(pollutant = saved) else it }
                    logOpen()
                }
            }
            launch { loadHistory(generation) }
            launch { loadCurrent(generation) }
        }
    }

    private suspend fun loadHistory(generation: Int) {
        val result = source.history(stationId)
        // An answer from an older pair says nothing about whether the record will load.
        val isLatest = generation == this.generation
        when (result) {
            is DataResult.Fresh -> {
                // The API sends a blank record for an id it doesn't know.
                val fetched = result.value.station.takeIf { it.id != 0 }
                state.update {
                    // An older answer without the record doesn't take away one already loaded.
                    val station = if (fetched != null || isLatest) fetched else it.station
                    it.copy(
                        station = station,
                        stationLoadFailed = if (station != null || isLatest) station == null else it.stationLoadFailed,
                        history = result.value.readings
                    )
                }
                logOpen()
                finished(failed = false, generation = generation)
            }

            is DataResult.Stale, is DataResult.Failed -> {
                if (isLatest) state.update { it.copy(stationLoadFailed = it.station == null) }
                finished(failed = true, generation = generation)
            }
        }
    }

    private suspend fun loadCurrent(generation: Int) {
        val result = source.currentPollutant(stationId)
        val notReporting = (result as? DataResult.Failed)?.error is NoCurrentReadingException ||
            (result as? DataResult.Stale)?.error is NoCurrentReadingException
        when {
            result is DataResult.Fresh -> {
                state.update {
                    it.copy(pollutant = result.value, isShowingLastGood = false, isNotReporting = false)
                }
                logOpen()
                finished(failed = false, generation = generation)
            }

            notReporting -> {
                // An empty answer keeps a saved reading rather than blanking it, but the API is
                // still saying it has no current reading: the page says so, and the saved one
                // shows its own age. Online, so nothing on screen is an offline fallback.
                state.update {
                    it.copy(
                        pollutant = it.pollutant ?: result.valueOrNull,
                        isNotReporting = true,
                        isShowingLastGood = false
                    )
                }
                finished(failed = false, generation = generation)
            }

            else -> {
                // Whatever is on screen, the saved reading or one from earlier this visit, is
                // now the last good one.
                state.update {
                    val pollutant = it.pollutant ?: result.valueOrNull
                    it.copy(pollutant = pollutant, isShowingLastGood = pollutant != null)
                }
                finished(failed = true, generation = generation)
            }
        }
    }

    private fun finished(failed: Boolean, generation: Int) {
        if (generation != this.generation) return
        answers += failed
        if (answers.size < 2) return
        state.update {
            it.copy(
                loading = false,
                loadFailed = answers.all { failed -> failed } && it.pollutant == null && it.history.isEmpty()
            )
        }
    }

    // Favourites

    /** The heart: adds, removes, or asks first when the station has alerts on (FOX-57). */
    fun toggleFavourite() {
        val current = state.value
        when {
            !current.isFavourite -> {
                if (!current.canAddFavourite) return
                if (favourites.add(stationId)) logFavourite(on = true)
                // FOX-57: a new favourite switches its alerts on (iOS FOX-31) here.
            }

            favourites.needsConfirmation(listOf(stationId)) -> state.update { it.copy(confirmingUnfavourite = true) }

            else -> removeFromFavourites()
        }
    }

    /** Takes the station out of Favourites, turning its alerts off with it when it has any. */
    fun removeFromFavourites() {
        state.update { it.copy(confirmingUnfavourite = false) }
        if (favourites.remove(stationId)) logFavourite(on = false)
    }

    fun dismissUnfavourite() {
        state.update { it.copy(confirmingUnfavourite = false) }
    }

    private fun logFavourite(on: Boolean) {
        logEvent(
            Analytics.FAVOURITE_STATION_SAVED,
            mapOf("label" to if (on) "on" else "off", "stationId" to stationId.toString())
        )
    }

    /** Once per page, when the station's names are known (iOS logs it as a map marker opens the page). */
    private fun logOpen() {
        if (loggedOpen) return
        val current = state.value
        val name = current.pollutant?.name ?: current.station?.name ?: return
        val nameLocal = current.pollutant?.nameLocal ?: current.station?.nameLocal ?: return
        loggedOpen = true
        logEvent(
            Analytics.CHECK_MAIN_DETAILS,
            mapOf("name" to name, "nameLocal" to nameLocal, "stationId" to stationId.toString())
        )
    }

    companion object {
        /** Takes [app] rather than reading it from the creation extras, so any store owner works. */
        fun factory(stationId: Int, app: TwaqiApplication): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                StationDetailsViewModel(
                    stationId,
                    RepositoryStationDataSource(app.container.airQuality),
                    app.container.favourites,
                    logEvent = { name, params -> Analytics.logEvent(app, name, params) }
                )
            }
        }
    }
}
