package com.kfpun.twaqi.ui.debug

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.kfpun.twaqi.TwaqiApplication
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.repository.AirQualityRepository
import com.kfpun.twaqi.data.repository.DataResult
import com.kfpun.twaqi.data.repository.ForecastRepository
import java.time.Instant
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * What the data-layer check screen shows.
 *
 * @property updatedAt newest reading's publish time; when [stale], when the saved copy was written
 *   if no reading has a time.
 * @property stale the refresh failed and these are the last saved readings.
 * @property failed the refresh failed and nothing was saved.
 */
data class DataDebugUiState(
    val loading: Boolean = true,
    val stationCount: Int = 0,
    val pollutants: List<Pollutant> = emptyList(),
    val forecastRowCount: Int = 0,
    val updatedAt: Instant? = null,
    val stale: Boolean = false,
    val failed: Boolean = false
)

/** Loads stations, current readings and the forecast through the repositories (FOX-53 check screen). */
class DataDebugViewModel(private val airQuality: AirQualityRepository, private val forecasts: ForecastRepository) :
    ViewModel() {
    private val state = MutableStateFlow(DataDebugUiState())
    val uiState: StateFlow<DataDebugUiState> = state.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            // The last saved copy shows at once; the requests only refresh it.
            if (state.value.pollutants.isEmpty()) {
                val stations = airQuality.savedStations()
                val pollutants = airQuality.savedPollutants()
                state.update {
                    it.copy(
                        stationCount = stations?.value?.size ?: 0,
                        pollutants = pollutants?.value.orEmpty(),
                        updatedAt = newest(pollutants?.value.orEmpty()) ?: pollutants?.savedAt
                    )
                }
            }
            state.update { it.copy(loading = true, failed = false) }

            val stations = async { airQuality.stations() }
            val pollutants = async { airQuality.currentPollutants() }
            val forecast = async { forecasts.forecasts() }

            val readings = pollutants.await()
            val list = readings.valueOrNull.orEmpty()
            state.update {
                it.copy(
                    loading = false,
                    stationCount = stations.await().valueOrNull?.size ?: it.stationCount,
                    pollutants = list,
                    forecastRowCount = forecast.await().valueOrNull?.size ?: 0,
                    updatedAt = newest(list) ?: (readings as? DataResult.Stale)?.savedAt,
                    stale = readings is DataResult.Stale,
                    failed = readings is DataResult.Failed
                )
            }
        }
    }

    private fun newest(list: List<Pollutant>): Instant? = list.mapNotNull { it.publishedAt }.maxOrNull()

    companion object {
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer {
                val app = this[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY] as TwaqiApplication
                DataDebugViewModel(app.container.airQuality, app.container.forecasts)
            }
        }
    }
}
