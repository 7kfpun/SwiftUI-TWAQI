package com.kfpun.twaqi.shortcuts

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.DrawableRes
import com.kfpun.twaqi.MainActivity
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.Country
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.ui.main.LocationAccess
import com.kfpun.twaqi.ui.navigation.DeepLink
import com.kfpun.twaqi.ui.navigation.StationLinkSource
import com.kfpun.twaqi.widget.WidgetDataSource
import com.kfpun.twaqi.widget.WidgetLocation
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * What the Quick Settings tile draws (FOX-95, iOS `AirQualityControlValue`): "AQI 42" over
 * "Songshan · Good", or "AQI –" when there is no reading. Pure, for tests.
 */
data class AirQualityTileContent(val stationId: Int?, val title: String, val subtitle: String, val status: AirStatus) {
    /** Tiles draw one-colour icons only, so the level shows as how dense the dots are (iOS `aqi.low/medium/high`). */
    @get:DrawableRes
    val icon: Int get() = when (status) {
        AirStatus.GOOD, AirStatus.MODERATE, AirStatus.UNKNOWN -> R.drawable.ic_tile_aqi_low
        AirStatus.UNHEALTHY_FOR_SENSITIVE_GROUP, AirStatus.UNHEALTHY -> R.drawable.ic_tile_aqi_medium
        AirStatus.VERY_UNHEALTHY, AirStatus.HAZARDOUS -> R.drawable.ic_tile_aqi_high
    }

    companion object {
        fun of(
            stationId: Int?,
            reading: Pollutant?,
            chinese: Boolean,
            statusLabel: (AirStatus) -> String,
            noStation: String
        ): AirQualityTileContent {
            val status = reading?.status(AirIndexType.AQI) ?: AirStatus.UNKNOWN
            if (reading == null || status == AirStatus.UNKNOWN) {
                return AirQualityTileContent(
                    stationId = reading?.stationId ?: stationId,
                    title = "AQI –",
                    subtitle = reading?.displayName(chinese) ?: noStation,
                    status = AirStatus.UNKNOWN
                )
            }
            return AirQualityTileContent(
                stationId = reading.stationId,
                title = "AQI ${AirIndexType.AQI.format(reading.aqi)}",
                subtitle = "${reading.displayName(chinese)} · ${statusLabel(status)}",
                status = status
            )
        }
    }
}

/**
 * The Quick Settings tile (FOX-95), Android's Control Center control: the AQI of the station
 * nearest the reader when the app may use location, otherwise of the first favourite
 * ([StationResolution.controlStationId]). Tapping opens the app on that station through
 * [DeepLink]. Free, as on iOS.
 *
 * Drawn from the offline caches (FOX-53) as the panel opens, off the main thread. Only when the
 * saved reading is older than [REFRESH_AFTER] does it fetch that one station (or, before the app
 * ever loaded readings, the country list) and draw again.
 */
class AirQualityTileService : TileService() {
    private var scope: CoroutineScope? = null
    private var shownStationId: Int? = null

    override fun onStartListening() {
        super.onStartListening()
        scope?.cancel()
        val listening = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        scope = listening
        listening.launch {
            val app = applicationContext
            val saved = withContext(Dispatchers.IO) { load(app) }
            draw(saved.content)
            if (!saved.needsRefresh) return@launch
            val refreshed = withContext(Dispatchers.IO) {
                withTimeoutOrNull(REFRESH_TIMEOUT_MS) {
                    val airQuality = WidgetDataSource.containerOf(app).airQuality
                    saved.content.stationId?.let { airQuality.currentPollutant(it) } ?: airQuality.currentPollutants()
                }
                load(app)
            }
            draw(refreshed.content)
        }
    }

    override fun onStopListening() {
        scope?.cancel()
        scope = null
        super.onStopListening()
    }

    override fun onDestroy() {
        scope?.cancel()
        scope = null
        super.onDestroy()
    }

    override fun onClick() {
        super.onClick()
        val intent = shownStationId?.let { DeepLink.stationIntent(this, it, StationLinkSource.TILE) }
            ?: Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (isLocked) unlockAndRun { open(intent) } else open(intent)
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun open(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(
                PendingIntent.getActivity(
                    this,
                    0,
                    intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
            )
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun draw(content: AirQualityTileContent) {
        shownStationId = content.stationId
        val tile = qsTile ?: return
        tile.label = content.title
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) tile.subtitle = content.subtitle
        tile.contentDescription = "${content.title}, ${content.subtitle}"
        tile.icon = Icon.createWithResource(this, content.icon)
        tile.state = if (content.status == AirStatus.UNKNOWN) Tile.STATE_INACTIVE else Tile.STATE_ACTIVE
        tile.updateTile()
    }

    private class Loaded(val content: AirQualityTileContent, val needsRefresh: Boolean)

    /** Reads the caches only. Blocking: call off the main thread. */
    private suspend fun load(context: Context, now: Instant = Instant.now()): Loaded {
        val container = WidgetDataSource.containerOf(context)
        val all = container.airQuality.savedPollutants(Country.SUPPORTED_CODE)?.value.orEmpty()
        val closestId = WidgetLocation.nearest(all, WidgetLocation.point(context))?.stationId
        val stationId = StationResolution.controlStationId(
            requestedStationId = null,
            appClosestId = closestId,
            favouriteIds = container.favourites.favourites.value,
            locationAllowed = LocationAccess.isGranted(context)
        )
        val saved = stationId?.let { container.airQuality.savedPollutants(listOf(it)).firstOrNull() }
        val localized = AppLocale.localizedContext(context)
        val content = AirQualityTileContent.of(
            stationId = stationId,
            reading = saved?.value,
            chinese = AppLocale.isChinese(context),
            statusLabel = { localized.getString(it.label) },
            noStation = localized.getString(R.string.watch_no_station)
        )
        val needsRefresh = saved == null || Duration.between(saved.savedAt, now) > REFRESH_AFTER
        return Loaded(content, needsRefresh)
    }

    companion object {
        /** Readings are hourly; a saved one younger than this is shown as it is. */
        val REFRESH_AFTER: Duration = Duration.ofMinutes(30)

        private const val REFRESH_TIMEOUT_MS = 10_000L
    }
}
