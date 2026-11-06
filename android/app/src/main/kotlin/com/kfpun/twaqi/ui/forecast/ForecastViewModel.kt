package com.kfpun.twaqi.ui.forecast

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.kfpun.twaqi.TwaqiApplication
import com.kfpun.twaqi.data.model.AqiForecast
import com.kfpun.twaqi.data.model.AqiForecastMatcher
import com.kfpun.twaqi.data.model.ForecastTabArea
import com.kfpun.twaqi.data.model.ForecastTabOrdering
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.model.TaiwanTime
import com.kfpun.twaqi.data.repository.AirQualityRepository
import com.kfpun.twaqi.data.repository.ForecastRepository
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.ui.main.GeoPoint
import com.kfpun.twaqi.ui.main.LocationAccess
import com.kfpun.twaqi.ui.main.NearestStations
import java.time.Instant
import kotlin.coroutines.resume
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine

/** What the Forecast tab reads, so the view model can be tested without the network or GPS. */
interface ForecastTabSource {
    /** Forecast rows: fresh, or the last good copy when the refresh fails; empty when there is none. */
    suspend fun forecasts(): List<AqiForecast>

    /** The country list, saved copy first: it only names each station's area. Empty on failure. */
    suspend fun stations(): List<Pollutant>

    /** Saved readings of favourites missing from [stations] (not reporting now); they carry the area. */
    suspend fun savedPollutants(stationIds: List<Int>): List<Pollutant>

    /** Location is allowed; reading it never prompts. */
    fun isLocationAllowed(): Boolean

    /** A one-shot fix, or null. Only called once [isLocationAllowed]. */
    suspend fun location(): GeoPoint?
}

class AppForecastTabSource(
    private val app: TwaqiApplication,
    private val forecastRepository: ForecastRepository = app.container.forecasts,
    private val airQuality: AirQualityRepository = app.container.airQuality
) : ForecastTabSource {
    override suspend fun forecasts(): List<AqiForecast> = forecastRepository.forecasts().valueOrNull.orEmpty()

    override suspend fun stations(): List<Pollutant> =
        airQuality.savedPollutants()?.value ?: airQuality.currentPollutants().valueOrNull.orEmpty()

    override suspend fun savedPollutants(stationIds: List<Int>): List<Pollutant> =
        airQuality.savedPollutants(stationIds).map { it.value }

    override fun isLocationAllowed(): Boolean = LocationAccess.isGranted(app)

    override suspend fun location(): GeoPoint? = suspendCancellableCoroutine { continuation ->
        LocationAccess.current(app) { if (continuation.isActive) continuation.resume(it) }
    }
}

/** The Forecast tab's state (iOS `ForecastViewModel.State`). */
sealed interface ForecastUiState {
    data object Loading : ForecastUiState

    /** Every zone with a forecast from today on, in [ForecastTabOrdering] order. */
    data class Loaded(val areas: List<ForecastTabArea>) : ForecastUiState {
        /** The paragraph every zone repeats, shown once above the cards; null when they differ. */
        val sharedContent: String? get() = ForecastTabOrdering.sharedContent(areas)
    }

    /** Nothing fetched and nothing saved: offline on first use, or Directus not reachable. */
    data object Empty : ForecastUiState

    /** Rows came back, but none from today on: a saved copy older than its forecast. */
    data object NoCurrentForecast : ForecastUiState
}

/**
 * The Forecast tab (iOS `ForecastViewModel`, FOX-32): every 空品區's forecast, the reader's zone
 * first, then the favourites' zones, then the rest ([ForecastTabOrdering]).
 *
 * The list waits only on the forecast rows. The location fix (slow indoors) and the station list
 * each redraw it when they arrive: until then 北部 is first and favourites are named from their own
 * saved readings. Days are Taiwan days ([TaiwanTime]), never the device's.
 */
class ForecastViewModel(
    private val source: ForecastTabSource,
    private val chinese: () -> Boolean,
    private val now: () -> Instant = Instant::now
) : ViewModel() {
    private val state = MutableStateFlow<ForecastUiState>(ForecastUiState.Loading)
    val uiState: StateFlow<ForecastUiState> = state.asStateFlow()

    private var loadingForecasts = false
    private var loadingStations = false
    private var locating = false

    private var rows: List<AqiForecast>? = null
    private var stations: List<Pollutant> = emptyList()
    private var savedFavourites: Map<Int, Pollutant> = emptyMap()
    private var favouriteIds: List<Int> = emptyList()
    private var location: GeoPoint? = null

    /**
     * Loads, or reloads on each visit: the repository answers from memory inside its TTL, and
     * favourites may have changed since.
     */
    fun load(favouriteStationIds: List<Int>) {
        favouriteIds = favouriteStationIds
        // Favourites edited since the last visit re-pin at once.
        render()

        val allowed = source.isLocationAllowed()
        if (allowed && location == null && !locating) {
            locating = true
            viewModelScope.launch {
                location = source.location()
                locating = false
                render()
            }
        }

        // Only needed to name the reader's or a favourite's zone.
        if ((allowed || favouriteStationIds.isNotEmpty()) && !loadingStations) {
            loadingStations = true
            viewModelScope.launch {
                val fetched = source.stations()
                // A failed request keeps the list it had.
                if (fetched.isNotEmpty()) stations = fetched
                val known = stations.map { it.stationId }.toSet()
                val missing = favouriteIds.filter { it !in known }
                savedFavourites = if (missing.isEmpty()) {
                    emptyMap()
                } else {
                    source.savedPollutants(missing).associateBy { it.stationId }
                }
                loadingStations = false
                render()
            }
        }

        if (loadingForecasts) return
        loadingForecasts = true
        viewModelScope.launch {
            val fetched = source.forecasts()
            loadingForecasts = false
            // A reload that finds nothing keeps the last rows it had.
            if (fetched.isNotEmpty() || rows == null) rows = fetched
            render()
        }
    }

    private fun render() {
        val rows = rows ?: return
        if (rows.isEmpty()) {
            if (state.value !is ForecastUiState.Loaded) state.value = ForecastUiState.Empty
            return
        }
        val today = TaiwanTime.today(now())
        val areaNames = rows.filter { it.forecastDate >= today }.map { it.area }.toSortedSet().toList()
        val areaOf = { pollutant: Pollutant ->
            AqiForecastMatcher.area(pollutant.areaLocal, pollutant.countyLocal, areaNames)
        }
        val nearest = location?.let { NearestStations.closest(stations, it) }
        val areas = ForecastTabOrdering.areas(
            forecasts = rows,
            readerArea = nearest?.let(areaOf),
            favouriteAreas = favourites().map(areaOf),
            today = today,
            chinese = chinese()
        )
        state.value = if (areas.isEmpty()) ForecastUiState.NoCurrentForecast else ForecastUiState.Loaded(areas)
    }

    /** The favourite stations, in favourites order, as far as they are known. */
    private fun favourites(): List<Pollutant> {
        val byId = stations.associateBy { it.stationId }
        return favouriteIds.mapNotNull { byId[it] ?: savedFavourites[it] }
    }

    companion object {
        fun factory(app: TwaqiApplication): ViewModelProvider.Factory = viewModelFactory {
            initializer { ForecastViewModel(AppForecastTabSource(app), chinese = { AppLocale.isChinese(app) }) }
        }
    }
}
