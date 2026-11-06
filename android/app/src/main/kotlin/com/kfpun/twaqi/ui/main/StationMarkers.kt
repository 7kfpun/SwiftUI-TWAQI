package com.kfpun.twaqi.ui.main

import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.clustering.ClusterItem
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.HistoricalPollutant
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.model.wind

/**
 * What a marker draws (iOS `MarkerAppearance.Shape`).
 *
 * - [Pill]: the selected index's reading on its band colour.
 * - [Arrow]: wind mode, an arrow whose length carries the speed ([Wind.strengthLevel]), rotated by
 *   [bearing] (where the wind comes *from*) to point downwind. Deliberately arrow-only: the mode
 *   exists to read pollution *movement* across the island at a glance, and the colour still carries
 *   the selected index's band.
 * - [Calm]: wind mode, no wind: a ring, so still air doesn't read as a gap.
 */
sealed interface MarkerShape {
    data object Pill : MarkerShape

    data class Arrow(val strengthLevel: Int, val bearing: Float) : MarkerShape

    data object Calm : MarkerShape
}

/**
 * Everything that decides how a station's marker is drawn (iOS `MarkerAppearance`). The renderer
 * only touches a marker whose appearance changed, so stepping through the timeline costs a handful
 * of icon swaps rather than restyling every station (iOS FOX-69).
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
    val alpha: Float,
    val shape: MarkerShape = MarkerShape.Pill
) {
    companion object {
        /** Markers outside the supported country read as "context, not tappable" rather than "broken". */
        const val MUTED_ALPHA = 0.4f

        /** Ceiling for a station with no reading at the timeline's hour: faded, so it reads as missing. */
        const val MISSING_DATA_ALPHA = 0.55f

        /** @param hasData false when the station has no reading at the timeline's hour. */
        fun of(
            pollutant: Pollutant,
            type: AirIndexType,
            isInteractive: Boolean,
            hasData: Boolean = true,
            mode: MapMode = MapMode.POLLUTANT
        ): MarkerAppearance {
            val value = pollutant.value(type)
            val status = AirStatus.of(type, value)
            var alpha = if (isInteractive) 1f else MUTED_ALPHA
            if (!hasData) alpha = minOf(alpha, MISSING_DATA_ALPHA)
            val shape = when (mode) {
                MapMode.POLLUTANT -> MarkerShape.Pill

                MapMode.WIND -> pollutant.wind.let { wind ->
                    if (wind.isCalm) {
                        MarkerShape.Calm
                    } else {
                        MarkerShape.Arrow(wind.strengthLevel, wind.arrowRotation.toFloat())
                    }
                }
            }
            return MarkerAppearance(
                text = if (value != 0.0) type.format(value) else "-",
                status = status,
                color = status.color,
                foregroundColor = status.foregroundColor,
                alpha = alpha,
                shape = shape
            )
        }
    }
}

/**
 * One station on the map. Equal by [countryCode] and station id (ids are only unique within a
 * country), so the cluster renderer keeps the marker and only restyles it when the index, the
 * readings or the timeline hour change. Because of that equality, a restyle reaches the map only
 * through [MarkerSync].
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
 * Decides when the cluster manager must be handed a new list of stations (FOX-110).
 *
 * [MapStation]s are equal by id, so the renderer finds the marker it already has and only restyles
 * it. But maps-compose's `Clustering(items = …)` re-clusters only when the item list stops being
 * *equal* to the last one, and a list that differs only in looks (another index, wind mode, an
 * earlier hour) is equal by id: the markers never changed. The map asks [needsPush] for each new
 * list and, when a marker would look different, re-adds the items itself, which runs
 * `onClusterItemUpdated` on the reused markers.
 */
object MarkerSync {
    /**
     * True when [next] would draw anything differently from [shown], the list the cluster manager
     * last got (null: none yet). Comparing ids alone, as list equality does, misses every restyle.
     */
    fun needsPush(shown: List<MapStation>?, next: List<MapStation>): Boolean =
        shown == null || shown.size != next.size || shown.indices.any { !drawsTheSame(shown[it], next[it]) }

    /** Same station, drawn the same: everything the renderer and a tap read. */
    fun drawsTheSame(a: MapStation, b: MapStation): Boolean = a == b &&
        a.appearance == b.appearance &&
        a.isInteractive == b.isInteractive &&
        a.title == b.title &&
        a.pollutant.lat == b.pollutant.lat &&
        a.pollutant.lon == b.pollutant.lon
}

/**
 * Builds the map's stations from the loaded readings.
 *
 * At [hoursAgo] 0 every station shows its live reading. Further back, each country's hour is
 * [hoursAgo] before its own latest publish time, and each station shows [readingAt]'s reading for
 * that hour, or a faded grey "-" when there is none (iOS `displayedPollutant`).
 */
object MarkerSource {
    fun stations(
        countryPollutants: Map<String, List<Pollutant>>,
        supportedCountryCode: String?,
        type: AirIndexType,
        chinese: Boolean,
        mode: MapMode = MapMode.POLLUTANT,
        hoursAgo: Int = 0,
        readingAt: (stationId: Int, hour: String) -> HistoricalPollutant? = { _, _ -> null }
    ): List<MapStation> = countryPollutants.flatMap { (countryCode, pollutants) ->
        val isInteractive = countryCode == supportedCountryCode
        // Worked out once per country rather than per station.
        val hour = timelineHour(pollutants, hoursAgo)
        pollutants.map { live ->
            val (shown, hasData) = displayed(live, hour, readingAt)
            MapStation(
                countryCode = countryCode,
                pollutant = shown,
                appearance = MarkerAppearance.of(shown, type, isInteractive, hasData, mode),
                isInteractive = isInteractive,
                label = shown.displayName(chinese)
            )
        }
    }

    /** The publish hour the timeline is on for these stations' country, or null at "now". */
    fun timelineHour(pollutants: Collection<Pollutant>, hoursAgo: Int): String? {
        if (hoursAgo <= 0) return null
        return MapTimeline.anchor(pollutants)?.let { MapTimeline.publishTime(it, hoursAgo) }
    }

    /** What a station shows at [hour] and whether there is a reading behind it; live when [hour] is null. */
    fun displayed(
        live: Pollutant,
        hour: String?,
        readingAt: (stationId: Int, hour: String) -> HistoricalPollutant?
    ): Pair<Pollutant, Boolean> {
        if (hour == null) return live to true
        val reading = readingAt(live.stationId, hour)
        return live.at(hour, reading) to (reading != null)
    }
}
