package com.kfpun.twaqi.ui.station.weather

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.kfpun.twaqi.TwaqiApplication
import com.kfpun.twaqi.data.weather.StationWeather
import com.kfpun.twaqi.data.weather.StationWeatherMatcher
import com.kfpun.twaqi.data.weather.WeatherFile
import com.kfpun.twaqi.ui.station.StationDetailsUiState
import java.time.Instant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Where and in which county an AQI station is, from its reading or its record. */
data class WeatherQuery(val lat: Double, val lon: Double, val county: String?, val countyLocal: String?) {
    companion object {
        /**
         * The current (or saved) reading first, then the station record, as iOS calls
         * `findWeather` from whichever request answers; duplicates dropped.
         */
        fun from(state: StationDetailsUiState): List<WeatherQuery> = listOfNotNull(
            state.pollutant?.let { WeatherQuery(it.lat, it.lon, it.county, it.countyLocal) },
            state.station?.let { WeatherQuery(it.lat, it.lon, it.county, it.countyLocal) }
        ).distinct()
    }
}

/**
 * The card's content: the matched weather, and the station's county in both languages for its
 * heading (iOS `weatherCountyTitle`), picked in the app's language when drawn.
 */
data class StationWeatherCardState(val weather: StationWeather, val county: String?, val countyLocal: String?) {
    fun countyTitle(chinese: Boolean): String? = if (chinese) countyLocal else county
}

/**
 * CWA weather near the station (iOS `DetailsViewModel.findWeather`, FOX-11). Null until loaded, and
 * stays null when there is nothing in range: the page then shows no weather card. The first query
 * that matches wins; later ones don't replace it.
 */
class StationWeatherViewModel(
    private val load: suspend () -> WeatherFile?,
    private val now: () -> Instant = Instant::now
) : ViewModel() {
    private val state = MutableStateFlow<StationWeatherCardState?>(null)
    val card: StateFlow<StationWeatherCardState?> = state.asStateFlow()

    fun find(queries: List<WeatherQuery>) {
        if (state.value != null || queries.isEmpty()) return
        viewModelScope.launch {
            val file = load() ?: return@launch
            val match = queries.firstNotNullOfOrNull { query ->
                StationWeatherMatcher.weather(query.lat, query.lon, query.countyLocal, file, now())
                    ?.let { StationWeatherCardState(it, query.county, query.countyLocal) }
            } ?: return@launch
            if (state.value == null) state.value = match
        }
    }

    companion object {
        fun factory(app: TwaqiApplication): ViewModelProvider.Factory = viewModelFactory {
            initializer { StationWeatherViewModel(load = { app.container.weather.weather() }) }
        }
    }
}
