package com.kfpun.twaqi.ui.main

import com.kfpun.twaqi.data.model.Country
import com.kfpun.twaqi.data.model.Pollutant
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/** A point on the map, in degrees. */
data class GeoPoint(val lat: Double, val lon: Double)

/** Nearest-station and nearest-country lookups for the map card and the station list. */
object NearestStations {
    /**
     * The station nearest [center], for the closest-station card (iOS `checkClosestStation`).
     * Measured in plain degrees, as on iOS, so both apps pick the same station.
     */
    fun closest(pollutants: Iterable<Pollutant>, center: GeoPoint): Pollutant? =
        pollutants.minByOrNull { squaredDegrees(it.lat, it.lon, center) }

    /**
     * The country nearest [center], whose readings the map loads as context (iOS
     * `checkClosestCountry`). Placeholder rows with 0/0 coordinates never win.
     */
    fun closestCountry(countries: List<Country>, center: GeoPoint): Country? =
        countries.filter { it.hasValidLocation }.minByOrNull { squaredDegrees(it.lat, it.lon, center) }

    /**
     * [pollutants] nearest [from] first, with their distance in km. Without a point the API's order
     * is kept and no distance is given. Ties keep the API's order.
     */
    fun sortedByNearest(pollutants: List<Pollutant>, from: GeoPoint?): List<Pair<Pollutant, Double?>> {
        if (from == null) return pollutants.map { it to null }
        return pollutants.map { it to distanceKm(from, GeoPoint(it.lat, it.lon)) }.sortedBy { it.second }
    }

    /** Great-circle distance. */
    fun distanceKm(a: GeoPoint, b: GeoPoint): Double {
        val dLat = Math.toRadians(b.lat - a.lat)
        val dLon = Math.toRadians(b.lon - a.lon)
        val h = sin(dLat / 2).pow(2) + cos(Math.toRadians(a.lat)) * cos(Math.toRadians(b.lat)) * sin(dLon / 2).pow(2)
        return 2 * EARTH_RADIUS_KM * asin(sqrt(h.coerceIn(0.0, 1.0)))
    }

    private fun squaredDegrees(lat: Double, lon: Double, center: GeoPoint): Double =
        (lat - center.lat).pow(2) + (lon - center.lon).pow(2)

    private const val EARTH_RADIUS_KM = 6371.0
}
