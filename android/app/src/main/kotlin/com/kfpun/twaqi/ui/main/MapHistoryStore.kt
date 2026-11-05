package com.kfpun.twaqi.ui.main

import com.kfpun.twaqi.data.model.HistoricalPollutant
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.model.StationHistory
import com.kfpun.twaqi.data.repository.DataResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** One station's history to fetch, against the latest publish time of its country. */
data class HistoryRequest(val stationId: Int, val anchor: String)

/** Stations loaded out of how many the last request asked for. */
data class HistoryProgress(val done: Int, val total: Int) {
    val isLoading: Boolean get() = done < total
}

/** The map's visible area and centre, for fetching the stations in view first. */
data class MapArea(val south: Double, val west: Double, val north: Double, val east: Double, val center: GeoPoint) {
    fun contains(lat: Double, lon: Double): Boolean {
        if (lat !in south..north) return false
        // A view across the antimeridian has east < west.
        return if (west <= east) lon in west..east else lon >= west || lon <= east
    }
}

/**
 * The past 24 hours of readings for the map's stations, for the timeline (iOS `MapHistoryStore`).
 *
 * `/v1/historical-pollutants` takes one station at a time, so a map of ~80 stations is ~80
 * requests. They only go out once the timeline is touched, for the stations in view (nearest the
 * centre first), at most [MAX_CONCURRENT] at a time, and each station once per publish hour.
 *
 * Readings are kept by their own publish hour rather than by "hours ago", so a station fetched an
 * hour back still answers correctly for every hour it covers; an hour it doesn't have is null.
 *
 * Not thread-safe: call it and run [scope] on the main thread (the view model's scope); the
 * repository does its network work on IO.
 */
class MapHistoryStore(
    private val scope: CoroutineScope,
    private val fetch: suspend (stationId: Int, limit: Int) -> DataResult<StationHistory>
) {
    private val readings = HashMap<Int, HashMap<String, HistoricalPollutant>>()

    /** The anchor each station was fetched against. Failures count too: not retried until the next hour. */
    private val fetchedAnchor = HashMap<Int, String>()
    private var pending: List<HistoryRequest> = emptyList()
    private val inFlight = HashSet<Int>()

    /** What the last [request] asked for, for the progress readout. */
    private var requested: Map<Int, String> = emptyMap()

    private val version = MutableStateFlow(0)

    /** Bumped after each request and each station's history (or failure). */
    val changes: StateFlow<Int> = version.asStateFlow()

    /** That hour's reading, for an hour already snapped by [MapTimeline.hourKey]. */
    fun reading(stationId: Int, hour: String): HistoricalPollutant? = readings[stationId]?.get(hour)

    /**
     * Queues history for these stations, in priority order, ahead of anything still waiting from an
     * earlier request. Stations already fetched against their anchor are skipped.
     */
    fun request(stations: List<HistoryRequest>) {
        requested = stations.reversed().associate { it.stationId to it.anchor }
        val wanted = stations.filter { fetchedAnchor[it.stationId] != it.anchor && it.stationId !in inFlight }
        val wantedIds = wanted.map { it.stationId }.toSet()
        pending = wanted + pending.filter { it.stationId !in wantedIds }
        pump()
        version.update { it + 1 }
    }

    val progress: HistoryProgress
        get() = HistoryProgress(requested.count { (id, anchor) -> fetchedAnchor[id] == anchor }, requested.size)

    private fun pump() {
        while (inFlight.size < MAX_CONCURRENT && pending.isNotEmpty()) {
            val next = pending.first()
            pending = pending.drop(1)
            if (!inFlight.add(next.stationId)) continue
            scope.launch {
                val result = try {
                    fetch(next.stationId, MapTimeline.HOURS + 1)
                } finally {
                    inFlight.remove(next.stationId)
                    fetchedAnchor[next.stationId] = next.anchor
                }
                result.valueOrNull?.let { history ->
                    val byHour = readings.getOrPut(next.stationId) { HashMap() }
                    history.readings.forEach { reading ->
                        MapTimeline.hourKey(reading.publishTime)?.let { byHour[it] = reading }
                    }
                }
                pump()
                version.update { it + 1 }
            }
        }
    }

    companion object {
        /** Keeps the whole island to a few seconds without 80 requests at once. */
        const val MAX_CONCURRENT = 6

        /**
         * The stations in [area], nearest its centre first, each against its own country's latest
         * publish time. Stations off screen wait until the map is panned to them.
         */
        fun visibleRequests(countryPollutants: Map<String, List<Pollutant>>, area: MapArea): List<HistoryRequest> =
            countryPollutants.values.flatMap { pollutants ->
                val anchor = MapTimeline.anchor(pollutants) ?: return@flatMap emptyList()
                pollutants.filter { area.contains(it.lat, it.lon) }.map { p ->
                    val dLat = p.lat - area.center.lat
                    val dLon = p.lon - area.center.lon
                    (dLat * dLat + dLon * dLon) to HistoryRequest(p.stationId, anchor)
                }
            }.sortedBy { it.first }.map { it.second }
    }
}
