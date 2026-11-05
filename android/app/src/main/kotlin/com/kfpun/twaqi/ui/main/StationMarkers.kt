package com.kfpun.twaqi.ui.main

import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.clustering.ClusterItem
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.Pollutant

/**
 * Everything that decides how a station's marker is drawn (iOS `MarkerAppearance`).
 *
 * @property text the reading in the selected index's decimals, or "-" when the station reports 0
 *   (many don't measure every pollutant).
 * @property color the band's colour, `0xRRGGBB`.
 * @property alpha 1 for the supported country; muted for other countries, which are context only,
 *   and lower still when there is no reading at the timeline's hour.
 */
data class MarkerAppearance(
    val text: String,
    val status: AirStatus,
    val color: Int,
    val foregroundColor: Int,
    val alpha: Float
) {
    companion object {
        /** Markers outside the supported country read as "context, not tappable" rather than "broken". */
        const val MUTED_ALPHA = 0.4f

        /** Ceiling for a station with no reading at the timeline's hour: faded, so it reads as missing. */
        const val MISSING_DATA_ALPHA = 0.55f

        /**
         * @param hasData false when the station has no reading at the timeline's hour (FOX-91).
         * @param mode [MapMode.WIND] is drawn by FOX-91; until then it draws as [MapMode.POLLUTANT].
         */
        fun of(
            pollutant: Pollutant,
            type: AirIndexType,
            isInteractive: Boolean,
            hasData: Boolean = true,
            @Suppress("UNUSED_PARAMETER") mode: MapMode = MapMode.POLLUTANT
        ): MarkerAppearance {
            val value = pollutant.value(type)
            val status = AirStatus.of(type, value)
            var alpha = if (isInteractive) 1f else MUTED_ALPHA
            if (!hasData) alpha = minOf(alpha, MISSING_DATA_ALPHA)
            return MarkerAppearance(
                text = if (value != 0.0) type.format(value) else "-",
                status = status,
                color = status.color,
                foregroundColor = status.foregroundColor,
                alpha = alpha
            )
        }
    }
}

/**
 * One station on the map. Equal by [countryCode] and station id (ids are only unique within a
 * country), so the cluster renderer keeps the marker and only restyles it when the index, the
 * readings or the timeline hour change.
 */
class MapStation(
    val countryCode: String,
    val pollutant: Pollutant,
    val appearance: MarkerAppearance,
    /** Only the supported country's stations open; the rest are drawn for context. */
    val isInteractive: Boolean,
    private val label: String
) : ClusterItem {
    val stationId: Int get() = pollutant.stationId

    override fun getPosition(): LatLng = LatLng(pollutant.lat, pollutant.lon)

    /** Read by TalkBack. No info window opens: the map handles every tap itself. */
    override fun getTitle(): String = label

    override fun getSnippet(): String? = null

    override fun getZIndex(): Float = if (isInteractive) 1f else 0f

    override fun equals(other: Any?): Boolean =
        other is MapStation && other.countryCode == countryCode && other.stationId == stationId

    override fun hashCode(): Int = 31 * countryCode.hashCode() + stationId
}

/**
 * Builds the map's stations from the loaded readings.
 *
 * The timeline (FOX-91) plugs in through [hour] and [readingAt]: with an [hour] (a publish time,
 * `"2026-11-06 14:00:00"`), each station shows [readingAt]'s reading for it, or its live reading
 * faded when there is none. A null [hour] is live, and is all this ticket draws.
 */
object MarkerSource {
    fun stations(
        countryPollutants: Map<String, List<Pollutant>>,
        supportedCountryCode: String?,
        type: AirIndexType,
        chinese: Boolean,
        mode: MapMode = MapMode.POLLUTANT,
        hour: String? = null,
        readingAt: (Pollutant, String) -> Pollutant? = { _, _ -> null }
    ): List<MapStation> = countryPollutants.flatMap { (countryCode, pollutants) ->
        val isInteractive = countryCode == supportedCountryCode
        pollutants.map { live ->
            val reading = hour?.let { readingAt(live, it) }
            val shown = reading ?: live
            val hasData = hour == null || reading != null
            MapStation(
                countryCode = countryCode,
                pollutant = shown,
                appearance = MarkerAppearance.of(shown, type, isInteractive, hasData, mode),
                isInteractive = isInteractive,
                label = shown.displayName(chinese)
            )
        }
    }
}
