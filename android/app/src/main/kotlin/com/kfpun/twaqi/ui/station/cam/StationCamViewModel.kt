package com.kfpun.twaqi.ui.station.cam

import androidx.compose.ui.graphics.ImageBitmap
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.kfpun.twaqi.TwaqiApplication
import com.kfpun.twaqi.data.cams.CamFrameSource
import com.kfpun.twaqi.data.cams.CamHistorySource
import com.kfpun.twaqi.data.cams.StationCam
import com.kfpun.twaqi.data.cams.StationCamMatcher
import com.kfpun.twaqi.data.cams.StationCamState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * The station page's cam (iOS `DetailsViewModel.cam` with `StationCamView`'s loaders): which cam
 * the station has, its live frame, and the 24-hour scrubber.
 */
class StationCamViewModel<T>(
    private val cams: suspend () -> List<StationCam>,
    frameSource: CamFrameSource<T>,
    historySource: CamHistorySource<T>
) : ViewModel() {
    private val mutableCam = MutableStateFlow<StationCamState>(StationCamState.Loading)
    val cam: StateFlow<StationCamState> = mutableCam.asStateFlow()

    val frames = StationCamFrameLoader(frameSource, viewModelScope)
    val history = StationCamHistoryLoader(historySource, viewModelScope)

    /**
     * Called with each copy of the station the page gets (the reading and the station record each
     * carry the Chinese name and coordinates the join needs). The first to find a cam wins; a miss
     * leaves the other free to try with its copy of the name.
     *
     * The AQI station id is never used here: it is a different numbering from MOENV's SiteId,
     * which is what the cam URLs are keyed by.
     */
    fun findCam(name: String, lat: Double, lon: Double) {
        if (mutableCam.value is StationCamState.Available) return
        viewModelScope.launch {
            val all = cams()
            if (mutableCam.value is StationCamState.Available) return@launch
            val match = StationCamMatcher.match(name, lat, lon, all)
            if (match != null) {
                mutableCam.value = StationCamState.Available(match)
            } else if (mutableCam.value == StationCamState.Loading) {
                mutableCam.value = StationCamState.Missing
            }
        }
    }

    companion object {
        fun factory(app: TwaqiApplication): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                val container = app.container
                StationCamViewModel<ImageBitmap>(container.camManifest::cams, container.camFrames, container.camHistory)
            }
        }
    }
}
