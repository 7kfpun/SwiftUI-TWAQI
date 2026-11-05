package com.kfpun.twaqi.ui.station.forecast

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.kfpun.twaqi.TwaqiApplication
import com.kfpun.twaqi.data.model.AqiForecast
import com.kfpun.twaqi.data.model.AqiForecastMatcher
import com.kfpun.twaqi.data.model.AreaForecast
import com.kfpun.twaqi.data.model.TaiwanTime
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.ui.forecast.AreaForecastCard
import com.kfpun.twaqi.ui.station.StationDetailsUiState
import java.time.Instant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Where a station sits, from its reading or its record, with its zone's name in the app's language. */
data class ForecastQuery(val areaLocal: String?, val countyLocal: String?, val title: String?) {
    companion object {
        /**
         * The current (or saved) reading first, then the station record, as iOS calls
         * `findForecast` from whichever answers first; duplicates and placeless ones dropped.
         */
        fun from(state: StationDetailsUiState, chinese: Boolean): List<ForecastQuery> = listOfNotNull(
            state.pollutant?.let { ForecastQuery(it.areaLocal, it.countyLocal, it.displayArea(chinese)) },
            state.station?.let { ForecastQuery(it.areaLocal, it.countyLocal, it.displayArea(chinese)) }
        ).filter { it.areaLocal != null || it.countyLocal != null }.distinct()
    }
}

/**
 * The station's 空品區 forecast (iOS `DetailsViewModel.findForecast`), today onwards, at most three
 * days. Null until loaded, and stays null when the zone has nothing current: the page then shows
 * no forecast card. The first match wins; later queries don't replace it.
 */
class StationForecastViewModel(
    private val load: suspend () -> List<AqiForecast>,
    private val now: () -> Instant = Instant::now
) : ViewModel() {
    private val state = MutableStateFlow<AreaForecast?>(null)
    val forecast: StateFlow<AreaForecast?> = state.asStateFlow()

    fun find(queries: List<ForecastQuery>) {
        if (state.value != null || queries.isEmpty()) return
        viewModelScope.launch {
            val rows = load()
            val today = TaiwanTime.today(now())
            val match = queries.firstNotNullOfOrNull {
                AqiForecastMatcher.forecast(it.areaLocal, it.countyLocal, rows, it.title, today)
            } ?: return@launch
            if (state.value == null) state.value = match
        }
    }

    companion object {
        fun factory(app: TwaqiApplication): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                StationForecastViewModel(load = { app.container.forecasts.forecasts().valueOrNull.orEmpty() })
            }
        }
    }
}

/**
 * The station page's forecast slot (FOX-90): finds the station's zone forecast once its reading or
 * record has loaded and draws [AreaForecastCard], or nothing when there is none.
 */
@Composable
fun StationForecastSection(
    state: StationDetailsUiState,
    viewModel: StationForecastViewModel = viewModel(
        key = "forecast-${state.stationId}",
        factory = StationForecastViewModel.factory(LocalContext.current.applicationContext as TwaqiApplication)
    )
) {
    val chinese = AppLocale.isChinese(LocalContext.current)
    val queries = remember(state.pollutant, state.station, chinese) { ForecastQuery.from(state, chinese) }
    LaunchedEffect(queries) { viewModel.find(queries) }
    val forecast by viewModel.forecast.collectAsStateWithLifecycle()
    forecast?.let { AreaForecastCard(it) }
}
