package com.kfpun.twaqi.shortcuts

import android.content.Context
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.repository.AirQualityRepository
import com.kfpun.twaqi.data.repository.DataResult
import com.kfpun.twaqi.ui.main.GeoPoint
import com.kfpun.twaqi.ui.main.LocationAccess
import com.kfpun.twaqi.ui.main.NearestStations
import com.kfpun.twaqi.widget.WidgetDataSource
import com.kfpun.twaqi.widget.WidgetLocation

/**
 * Finds the reading a "What's the air?" question is about (FOX-95, iOS `AirQualityLookup`):
 * fetched through the data layer (FOX-53), which falls back to the last saved reading offline.
 * Never asks for location: without the permission it answers for the first favourite and says so.
 */
class AirQualityLookup(
    private val airQuality: AirQualityRepository,
    private val favouriteIds: () -> List<Int>,
    private val locationAllowed: () -> Boolean,
    /** Where "nearest" is measured from, once location is allowed. */
    private val readerPoint: () -> GeoPoint
) {
    data class Result(
        val reading: Pollutant?,
        val freshness: AnswerFreshness,
        val note: StationFallbackNote?,
        /** For analytics: nearest, favourite, station, default (iOS). */
        val kind: String
    )

    /** [requestedStationId] null means "nearest". */
    suspend fun lookup(requestedStationId: Int?): Result {
        val resolution = StationResolution.resolve(requestedStationId, favouriteIds(), locationAllowed())
        return when (val plan = resolution.plan) {
            is StationPlan.Station -> {
                val kind = if (requestedStationId == null) KIND_FAVOURITE else KIND_STATION
                answer(airQuality.currentPollutant(plan.stationId), resolution.note, kind)
            }

            StationPlan.Nearest -> closest(readerPoint(), resolution.note, KIND_NEAREST)

            StationPlan.DefaultLocation -> closest(WidgetLocation.DEFAULT, resolution.note, KIND_DEFAULT)
        }
    }

    private suspend fun closest(point: GeoPoint, note: StationFallbackNote?, kind: String): Result {
        val all = airQuality.currentPollutants()
        val reading = all.valueOrNull?.let { NearestStations.closest(it, point) }
        return Result(reading, freshness(all), note, kind)
    }

    private fun answer(result: DataResult<Pollutant>, note: StationFallbackNote?, kind: String) =
        Result(result.valueOrNull, freshness(result), note, kind)

    private fun freshness(result: DataResult<*>) =
        if (result is DataResult.Fresh) AnswerFreshness.LIVE else AnswerFreshness.CACHED

    companion object {
        const val KIND_NEAREST = "nearest"
        const val KIND_FAVOURITE = "favourite"
        const val KIND_STATION = "station"
        const val KIND_DEFAULT = "default"

        /** The widgets' idea of "nearest" (FOX-59): the last fix, else where the reader left the map. */
        fun create(context: Context): AirQualityLookup {
            val app = context.applicationContext
            val container = WidgetDataSource.containerOf(app)
            return AirQualityLookup(
                airQuality = container.airQuality,
                favouriteIds = { container.favourites.favourites.value },
                locationAllowed = { LocationAccess.isGranted(app) },
                readerPoint = { WidgetLocation.point(app) }
            )
        }
    }
}
