package com.kfpun.twaqi.widget

import com.kfpun.twaqi.data.model.AirIndexType

/** Which station a widget leads with (iOS `StationOption`, plus a chosen station). */
sealed interface StationChoice {
    /** The station nearest the reader (iOS "Closest station"). The default. */
    data object Nearest : StationChoice

    /** The reader's first favourite; the nearest station while there is none. */
    data object FirstFavourite : StationChoice

    /** One station, picked in the configuration screen. */
    data class Station(val stationId: Int) : StationChoice

    /** How the choice is stored in the widget's state, and its analytics label. */
    val id: String get() = when (this) {
        Nearest -> NEAREST
        FirstFavourite -> FIRST_FAVOURITE
        is Station -> "$STATION_PREFIX$stationId"
    }

    companion object {
        private const val NEAREST = "nearest"
        private const val FIRST_FAVOURITE = "firstFavourite"
        private const val STATION_PREFIX = "station:"

        /** Anything unknown (or nothing stored yet) is [Nearest]. */
        fun fromId(id: String?): StationChoice = when {
            id == FIRST_FAVOURITE -> FirstFavourite

            id != null && id.startsWith(STATION_PREFIX) ->
                id.removePrefix(STATION_PREFIX).toIntOrNull()?.takeIf { it > 0 }?.let(::Station) ?: Nearest

            else -> Nearest
        }
    }
}

/** A widget's settings, chosen in [WidgetConfigureActivity] (iOS `SelectIndexIntent`). */
data class WidgetConfig(
    val station: StationChoice = StationChoice.Nearest,
    val index: AirIndexType = AirIndexType.AQI
) {
    /**
     * The station id the widget leads with, before any paging. [nearestId] is the nearest
     * station's, null when it can't be worked out yet.
     */
    fun leadingStationId(favouriteIds: List<Int>, nearestId: Int?): Int? = when (station) {
        StationChoice.Nearest -> nearestId
        StationChoice.FirstFavourite -> favouriteIds.firstOrNull() ?: nearestId
        is StationChoice.Station -> station.stationId
    }

    /** Whether working out the leading station needs the reader's position. */
    fun needsNearest(favouriteIds: List<Int>): Boolean = when (station) {
        StationChoice.Nearest -> true
        StationChoice.FirstFavourite -> favouriteIds.isEmpty()
        is StationChoice.Station -> false
    }
}
