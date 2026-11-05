package com.kfpun.twaqi.widget

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import com.kfpun.twaqi.TwaqiApplication
import com.kfpun.twaqi.data.AppContainer
import com.kfpun.twaqi.data.cams.BitmapCamImageDecoder
import com.kfpun.twaqi.data.cams.CamFrame
import com.kfpun.twaqi.data.cams.StationCamMatcher
import com.kfpun.twaqi.data.model.AqiForecast
import com.kfpun.twaqi.data.model.AqiForecastMatcher
import com.kfpun.twaqi.data.model.AreaForecast
import com.kfpun.twaqi.data.model.Country
import com.kfpun.twaqi.data.model.HistoricalPollutant
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.model.TaiwanTime
import com.kfpun.twaqi.data.repository.DataResult
import com.kfpun.twaqi.pro.Entitlement
import com.kfpun.twaqi.pro.ProGraph
import java.time.Instant
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Everything a widget draws from, read from the offline caches only (FOX-53): drawing never
 * touches the network, so a tap pages at once and an offline widget keeps its last readings.
 * [WidgetRefreshWorker] is what fetches.
 *
 * @property readings the newest saved reading of the leading station and every favourite.
 * @property savedAt when each of [readings] was saved, for the offline line.
 * @property forecasts every area's forecast rows (large and station detail pick the station's area).
 * @property history the leading station's last 24 hours (station detail only), oldest first.
 * @property cam the leading station's last saved cam frame, small (station detail only, FOX-92).
 */
data class WidgetSnapshot(
    val config: WidgetConfig,
    val leadingId: Int?,
    val favouriteIds: List<Int>,
    val readings: Map<Int, Pollutant>,
    val savedAt: Map<Int, Instant>,
    val isPro: Boolean,
    val forecasts: List<AqiForecast> = emptyList(),
    val history: List<HistoricalPollutant> = emptyList(),
    val cam: CamFrame<Bitmap>? = null
) {
    val leading: Pollutant? get() = leadingId?.let(readings::get)

    /** Today's and tomorrow's forecast for [reading]'s 空品區, or null when there is none. */
    fun forecast(reading: Pollutant, chinese: Boolean, now: Instant = Instant.now()): AreaForecast? =
        AqiForecastMatcher.forecast(
            areaLocal = reading.areaLocal,
            countyLocal = reading.countyLocal,
            forecasts = forecasts,
            title = reading.displayArea(chinese),
            today = TaiwanTime.today(now),
            limit = 2
        )
}

/** Builds [WidgetSnapshot]s from the app's caches, and refreshes them for the worker. */
class WidgetDataSource(private val context: Context, private val container: AppContainer = containerOf(context)) {

    suspend fun snapshot(config: WidgetConfig, includeHistory: Boolean): WidgetSnapshot {
        val favouriteIds = container.favourites.favourites.value
        val nearestId = if (config.needsNearest(favouriteIds)) nearestStationId() else null
        val leadingId = config.leadingStationId(favouriteIds, nearestId)
        val ids = (listOfNotNull(leadingId) + favouriteIds).distinct()
        val saved = container.airQuality.savedPollutants(ids)
        val forecasts = container.forecasts.savedForecasts()
        return WidgetSnapshot(
            config = config,
            leadingId = leadingId,
            favouriteIds = favouriteIds,
            readings = saved.associate { it.value.stationId to it.value },
            savedAt = saved.associate { it.value.stationId to it.savedAt },
            isPro = isPro(),
            forecasts = forecasts,
            history = if (includeHistory &&
                leadingId != null
            ) {
                container.widgetHistory.read(leadingId).orEmpty()
            } else {
                emptyList()
            },
            cam = if (includeHistory && leadingId != null) savedCam(leadingId) else null
        )
    }

    /** The frame the station page or a refresh saved for [stationId]'s cam, decoded small for a widget. */
    private suspend fun savedCam(stationId: Int): CamFrame<Bitmap>? {
        val siteId = container.widgetHistory.readCam(stationId) ?: return null
        return container.camFrames.savedFrame(siteId) { bytes ->
            BitmapCamImageDecoder.thumbnail(bytes, CAM_PIXELS)?.asAndroidBitmap()
        }
    }

    /**
     * Fetches what [configs] need in as few requests as possible: the whole country when any widget
     * follows the nearest station (its list is what "nearest" is measured over), else only the
     * stations shown. Returns whether new readings came in.
     */
    suspend fun refresh(configs: List<Pair<WidgetConfig, Boolean>>): Boolean {
        if (configs.isEmpty()) return false
        val favouriteIds = container.favourites.favourites.value
        val needsCountry = configs.any { (config, _) -> config.needsNearest(favouriteIds) }
        val hasNewData = if (needsCountry) {
            container.airQuality.currentPollutants(Country.SUPPORTED_CODE) is DataResult.Fresh
        } else {
            val ids = (
                configs.mapNotNull { (config, _) ->
                    config.leadingStationId(favouriteIds, null)
                } + favouriteIds
                ).distinct()
            ids.isNotEmpty() &&
                container.airQuality.currentPollutants(ids).let { it is DataResult.Fresh && it.value.isNotEmpty() }
        }
        // Large and station detail show the forecast; the repository keeps it 30 minutes and falls back to its last copy.
        container.forecasts.forecasts()
        // Station detail: the last 24 hours, kept from the last good fetch.
        val details = configs.filter { it.second }.map { it.first }
        if (details.isNotEmpty()) {
            val nearestId = if (details.any { it.needsNearest(favouriteIds) }) nearestStationId() else null
            val stationIds = details.mapNotNull { it.leadingStationId(favouriteIds, nearestId) }.distinct()
            stationIds.forEach { stationId ->
                val history = container.airQuality.history(stationId)
                if (history is DataResult.Fresh) container.widgetHistory.save(stationId, history.value.readings)
            }
            refreshCams(stationIds)
        }
        return hasNewData
    }

    /**
     * Station detail's cam (FOX-92): the manifest (kept an hour) names each station's cam, and its
     * latest frame is saved over the last one, where the station page finds it too. A manifest that
     * didn't load changes nothing; a failed frame keeps the saved one (iOS `StationDetailLoader`).
     */
    private suspend fun refreshCams(stationIds: List<Int>) {
        val cams = runCatching { container.camManifest.cams() }.getOrDefault(emptyList())
        if (cams.isEmpty()) return
        container.airQuality.savedPollutants(stationIds).map { it.value }.forEach { reading ->
            val cam = StationCamMatcher.match(reading.nameLocal, reading.lat, reading.lon, cams)
            container.widgetHistory.saveCam(reading.stationId, cam?.siteId)
            if (cam != null) container.camFrames.fetch(cam)
        }
    }

    private suspend fun nearestStationId(): Int? {
        val all = container.airQuality.savedPollutants(Country.SUPPORTED_CODE)?.value ?: return null
        return WidgetLocation.nearest(all, WidgetLocation.point(context))?.stationId
    }

    /** The one Pro source (FOX-58), as saved; free until it has been read. */
    private suspend fun isPro(): Boolean {
        val repository = ProGraph.repository(context)
        val entitlement = withTimeoutOrNull(PRO_READ_TIMEOUT_MS) { repository.entitlement.filterNotNull().first() }
        return entitlement == Entitlement.PRO
    }

    companion object {
        private const val PRO_READ_TIMEOUT_MS = 2_000L

        /** Longest side of the cam frame a widget draws, in pixels: a 160dp-wide thumbnail. */
        private const val CAM_PIXELS = 480

        fun containerOf(context: Context): AppContainer = (context.applicationContext as TwaqiApplication).container
    }
}
