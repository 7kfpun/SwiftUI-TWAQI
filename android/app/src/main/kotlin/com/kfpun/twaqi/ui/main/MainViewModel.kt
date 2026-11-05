package com.kfpun.twaqi.ui.main

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.kfpun.twaqi.TwaqiApplication
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.Country
import com.kfpun.twaqi.data.model.HistoricalPollutant
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.model.StationHistory
import com.kfpun.twaqi.data.repository.AirQualityRepository
import com.kfpun.twaqi.data.repository.DataResult
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
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
    val failed: Boolean = false,
    /** Hours before the latest reading the map shows (FOX-91); 0 is live. */
    val timelineHoursAgo: Int = 0,
    val timelinePlaying: Boolean = false,
    /** Stations loaded out of those asked for, while history is arriving; null otherwise. */
    val historyProgress: HistoryProgress? = null,
    /** Bumped when history arrives for the hour on screen, so the markers recolour. */
    val historyVersion: Int = 0
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

    /** The timeline is labelled in the supported country's clock (Taiwan): its latest publish time. */
    val timelineAnchor: String?
        get() = (
            countryPollutants[supportedCountryCode ?: Country.SUPPORTED_CODE]
                ?: countryPollutants.values.firstOrNull()
            )
            ?.let(MapTimeline::anchor)
}

/**
 * Loads countries and readings for the map and the list (iOS `GoogleMapViewController`'s API
 * calls), and holds the selected index and map centre. Shared by the map and the Search tab, so
 * the index picked on one recolours the other.
 */
class MainViewModel(
    private val airQuality: AirQualityRepository,
    private val preferences: MapPreferences?,
    private val now: () -> Instant = Instant::now,
    private val historyFetch: (suspend (stationId: Int, limit: Int) -> DataResult<StationHistory>)? = null
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

    /** The past 24 hours for the timeline, fetched only once it is touched. */
    private val history = MapHistoryStore(viewModelScope, historyFetch ?: airQuality::history)
    private var visibleArea: MapArea? = null
    private var playJob: Job? = null
    private var historyRedrawScheduled = false

    init {
        refresh()
        viewModelScope.launch { history.changes.collect { historyDidChange() } }
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
    fun onCameraIdle(target: MapTarget, area: MapArea? = null) {
        preferences?.saveCamera(target)
        if (area != null) visibleArea = area
        state.update { it.copy(center = GeoPoint(target.lat, target.lon)) }
        viewModelScope.launch { loadClosestCountry() }
        // Panned back in time and on to new stations: fetch theirs too.
        if (state.value.timelineHoursAgo > 0) requestVisibleHistory()
    }

    fun onUserLocation(location: GeoPoint?) {
        if (location != null) state.update { it.copy(userLocation = location) }
    }

    fun setMapMode(mode: MapMode) = state.update { it.copy(mapMode = mode) }

    /** The wind button (iOS `toggleIsWindMode`). Returns the new mode, for the analytics label. */
    fun toggleWindMode(): MapMode {
        val mode = if (state.value.mapMode == MapMode.WIND) MapMode.POLLUTANT else MapMode.WIND
        setMapMode(mode)
        return mode
    }

    // Timeline (FOX-91, iOS `GoogleMapViewController`'s timeline).

    /** That hour's reading for a station, once its history is in. */
    fun historyReading(stationId: Int, hour: String): HistoricalPollutant? = history.reading(stationId, hour)

    /** What [live] shows at the timeline's hour (the closest card), and whether there is a reading behind it. */
    fun displayed(live: Pollutant): Pair<Pollutant, Boolean> {
        val current = state.value
        val country = current.countryOf(live)?.let { current.countryPollutants[it] }.orEmpty()
        val hour = MarkerSource.timelineHour(country, current.timelineHoursAgo)
        return MarkerSource.displayed(live, hour, history::reading)
    }

    /**
     * A finger came down on the track, before any change: playback stops and history starts loading
     * for [area], the map's view right now (the first camera idle can come before the map has one).
     */
    fun onTimelineInteraction(area: MapArea?) {
        if (area != null) visibleArea = area
        stopPlaying()
        requestVisibleHistory()
    }

    /** The scrubber moved. Hours before the latest reading; 0 is live. */
    fun setTimelineHoursAgo(hoursAgo: Int) {
        val clamped = hoursAgo.coerceIn(0, MapTimeline.HOURS)
        state.update { it.copy(timelineHoursAgo = clamped) }
    }

    /**
     * Play steps forward an hour at a time to "now"; from "now" it starts 24 hours back. Returns
     * true when playback started (for the `map_timeline_play` event).
     */
    fun togglePlay(area: MapArea?): Boolean {
        if (playJob != null) {
            stopPlaying()
            return false
        }
        if (area != null) visibleArea = area
        requestVisibleHistory()
        state.update {
            it.copy(
                timelinePlaying = true,
                timelineHoursAgo = if (it.timelineHoursAgo == 0) MapTimeline.HOURS else it.timelineHoursAgo
            )
        }
        playJob = viewModelScope.launch {
            while (true) {
                delay(PLAY_STEP)
                // Holds while the hour on screen is still filling in, so playback doesn't race ahead
                // of a cold cache.
                val progress = history.progress
                if (progress.isLoading && progress.done == 0) continue
                val next = (state.value.timelineHoursAgo - 1).coerceAtLeast(0)
                state.update { it.copy(timelineHoursAgo = next) }
                if (next == 0) break
            }
            playJob = null
            state.update { it.copy(timelinePlaying = false) }
        }
        return true
    }

    fun stopPlaying() {
        playJob?.cancel()
        playJob = null
        if (state.value.timelinePlaying) state.update { it.copy(timelinePlaying = false) }
    }

    /** Queues history for the stations in view, nearest the centre first. */
    private fun requestVisibleHistory() {
        val area = visibleArea ?: return
        history.request(MapHistoryStore.visibleRequests(state.value.countryPollutants, area))
    }

    /** History arrived for some stations. Coalesced, so a burst of responses is one redraw. */
    private fun historyDidChange() {
        val progress = history.progress
        state.update { it.copy(historyProgress = progress.takeIf { p -> p.isLoading }) }
        if (state.value.timelineHoursAgo == 0 || historyRedrawScheduled) return
        historyRedrawScheduled = true
        viewModelScope.launch {
            delay(HISTORY_REDRAW_DELAY)
            historyRedrawScheduled = false
            state.update { it.copy(historyVersion = it.historyVersion + 1) }
        }
    }

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
            // A new publish hour moves the window; top up what's in view.
            if (result is DataResult.Fresh && state.value.timelineHoursAgo > 0) requestVisibleHistory()
        } finally {
            inFlight.remove(countryCode)
        }
    }

    override fun onCleared() {
        stopPlaying()
    }

    companion object {
        val REFRESH_INTERVAL: Duration = Duration.ofMinutes(15)

        /** One hour per step while playing (iOS 0.8 s). */
        const val PLAY_STEP = 800L

        /** History responses within this window redraw once. */
        const val HISTORY_REDRAW_DELAY = 300L

        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer {
                val app = this[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY] as TwaqiApplication
                MainViewModel(app.container.airQuality, MapPreferences(app))
            }
        }
    }
}
