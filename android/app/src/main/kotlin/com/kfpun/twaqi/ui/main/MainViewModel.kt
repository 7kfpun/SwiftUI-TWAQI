package com.kfpun.twaqi.ui.main

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.kfpun.twaqi.TwaqiApplication
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.Country
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.repository.AirQualityRepository
import com.kfpun.twaqi.data.repository.DataResult
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * What the map and the station list show.
 *
 * @property countryPollutants readings by country code: the supported country, plus the country
 *   nearest the map centre as context.
 * @property lastGoodCountryCodes countries whose readings are the last saved ones, because the
 *   latest request failed. Their card says so with its age.
 * @property center the map centre; the closest-station card follows it.
 * @property userLocation where the reader is, once location is allowed; the list sorts by it.
 */
data class MainUiState(
    val countries: List<Country> = emptyList(),
    val supportedCountryCode: String? = null,
    val countryPollutants: Map<String, List<Pollutant>> = emptyMap(),
    val lastGoodCountryCodes: Set<String> = emptySet(),
    val indexType: AirIndexType = AirIndexType.AQI,
    val mapMode: MapMode = MapMode.POLLUTANT,
    val center: GeoPoint = GeoPoint(MapHome.LATITUDE, MapHome.LONGITUDE),
    val userLocation: GeoPoint? = null,
    val loading: Boolean = true,
    /** Nothing could be loaded and nothing was saved. */
    val failed: Boolean = false
) {
    /** The supported country's readings: the only stations that open, and the ones the list shows. */
    val supportedPollutants: List<Pollutant>
        get() = countryPollutants[supportedCountryCode ?: Country.SUPPORTED_CODE].orEmpty()

    /** The station nearest the map centre, from any loaded country (iOS `checkClosestStation`). */
    val closest: Pollutant?
        get() = NearestStations.closest(countryPollutants.values.flatten(), center)

    /** The country code whose readings hold [pollutant]; ids are only unique within a country. */
    fun countryOf(pollutant: Pollutant): String? = countryPollutants.entries.firstOrNull { pollutant in it.value }?.key

    /** Only the supported country's stations open; the rest are drawn for context. */
    fun isInteractive(pollutant: Pollutant): Boolean =
        countryOf(pollutant) == (supportedCountryCode ?: Country.SUPPORTED_CODE)

    fun isLastGood(pollutant: Pollutant): Boolean = countryOf(pollutant) in lastGoodCountryCodes
}

/**
 * Loads countries and readings for the map and the list (iOS `GoogleMapViewController`'s API
 * calls), and holds the selected index and map centre. Shared by the map and the Search tab, so
 * the index picked on one recolours the other.
 */
class MainViewModel(
    private val airQuality: AirQualityRepository,
    private val preferences: MapPreferences?,
    private val now: () -> Instant = Instant::now
) : ViewModel() {
    private val state = MutableStateFlow(
        MainUiState(
            indexType = preferences?.indexType ?: AirIndexType.AQI,
            center = preferences?.initialCamera?.let { GeoPoint(it.lat, it.lon) }
                ?: GeoPoint(MapHome.LATITUDE, MapHome.LONGITUDE)
        )
    )
    val uiState: StateFlow<MainUiState> = state.asStateFlow()

    /** Country codes with a readings request on the wire; the camera settles several times at launch. */
    private val inFlight = mutableSetOf<String>()
    private var lastRefresh: Instant? = null
    private var refreshJob: Job? = null

    init {
        refresh()
    }

    /** On every return to the foreground: what failed is retried at once, the rest every 15 minutes. */
    fun refreshIfNeeded() {
        if (refreshJob?.isActive == true) return
        val last = lastRefresh
        val current = state.value
        if (last == null || current.countries.isEmpty() || current.lastGoodCountryCodes.isNotEmpty() ||
            Duration.between(last, now()) >= REFRESH_INTERVAL
        ) {
            refresh()
        }
    }

    fun refresh() {
        if (refreshJob?.isActive == true) return
        lastRefresh = now()
        refreshJob = viewModelScope.launch {
            val countries = airQuality.countries().valueOrNull.orEmpty()
            val supported = countries.firstOrNull { it.isSupported }?.code ?: Country.SUPPORTED_CODE
            state.update {
                it.copy(countries = countries.ifEmpty { it.countries }, supportedCountryCode = supported)
            }
            // Offline launch: the countries list is only needed to know which country to load, and the
            // repository falls back to the last saved list; without one, Taiwan.
            loadPollutants(supported)
            state.value.countryPollutants.keys.filter { it != supported }.forEach { loadPollutants(it) }
            loadClosestCountry()
        }
    }

    fun selectIndex(type: AirIndexType) {
        preferences?.indexType = type
        state.update { it.copy(indexType = type) }
    }

    /** The camera settled: the closest-station card follows it, and the nearest country loads. */
    fun onCameraIdle(target: MapTarget) {
        preferences?.saveCamera(target)
        state.update { it.copy(center = GeoPoint(target.lat, target.lon)) }
        viewModelScope.launch { loadClosestCountry() }
    }

    fun onUserLocation(location: GeoPoint?) {
        if (location != null) state.update { it.copy(userLocation = location) }
    }

    /** Hook for FOX-91's wind button. */
    fun setMapMode(mode: MapMode) = state.update { it.copy(mapMode = mode) }

    private suspend fun loadClosestCountry() {
        val current = state.value
        val closest = NearestStations.closestCountry(current.countries, current.center) ?: return
        if (closest.code !in current.countryPollutants) loadPollutants(closest.code)
    }

    private suspend fun loadPollutants(countryCode: String) {
        if (!inFlight.add(countryCode)) return
        try {
            val result = airQuality.currentPollutants(countryCode)
            state.update { current ->
                val shown = current.countryPollutants[countryCode]
                when (result) {
                    is DataResult.Fresh -> current.copy(
                        countryPollutants = current.countryPollutants + (countryCode to result.value),
                        lastGoodCountryCodes = current.lastGoodCountryCodes - countryCode
                    )

                    // Keep what is on screen; with nothing on screen yet, the last saved readings.
                    is DataResult.Stale -> current.copy(
                        countryPollutants = current.countryPollutants + (countryCode to (shown ?: result.value)),
                        lastGoodCountryCodes = current.lastGoodCountryCodes + countryCode
                    )

                    is DataResult.Failed -> if (shown != null) {
                        current.copy(lastGoodCountryCodes = current.lastGoodCountryCodes + countryCode)
                    } else {
                        current
                    }
                }.let { next ->
                    val supported = next.supportedCountryCode ?: Country.SUPPORTED_CODE
                    if (countryCode == supported) {
                        next.copy(loading = false, failed = next.countryPollutants[supported].isNullOrEmpty())
                    } else {
                        next
                    }
                }
            }
        } finally {
            inFlight.remove(countryCode)
        }
    }

    companion object {
        val REFRESH_INTERVAL: Duration = Duration.ofMinutes(15)

        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer {
                val app = this[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY] as TwaqiApplication
                MainViewModel(app.container.airQuality, MapPreferences(app))
            }
        }
    }
}
