package com.kfpun.twaqi.ui.main

import com.kfpun.twaqi.data.model.Country

/** A camera target: centre and zoom. */
data class MapTarget(val lat: Double, val lon: Double, val zoom: Float)

/**
 * Where the map opens before the user has ever moved it, and where the "default location"
 * button returns to (iOS `MapHome`).
 *
 * Mirrors the supported country (`Country.SUPPORTED_ID`) from the countries endpoint. The button
 * prefers the API's values once loaded; these are the fallback for first launch, before any
 * network call has returned.
 */
object MapHome {
    const val LATITUDE = 23.49
    const val LONGITUDE = 120.96
    const val ZOOM = 7.9f

    /** Zoom of the "my location" button (iOS `goToMyLocation`). */
    const val MY_LOCATION_ZOOM = 13f

    val target = MapTarget(LATITUDE, LONGITUDE, ZOOM)

    /** Always the supported country, not whichever happens to be nearest (iOS `goToDefaultLocation`). */
    fun defaultLocation(countries: List<Country>): MapTarget {
        val supported = countries.firstOrNull { it.isSupported && it.hasValidLocation } ?: return target
        return MapTarget(supported.lat, supported.lon, if (supported.zoom > 0) supported.zoom else ZOOM)
    }

    /**
     * The camera the user last left the map at, or [target] on first launch. 0/0 means nothing
     * was saved (iOS `initialCamera`).
     */
    fun initialCamera(savedLat: Double, savedLon: Double, savedZoom: Float): MapTarget {
        val hasSavedPosition = !(savedLat == 0.0 && savedLon == 0.0)
        return MapTarget(
            if (hasSavedPosition) savedLat else LATITUDE,
            if (hasSavedPosition) savedLon else LONGITUDE,
            if (savedZoom > 0) savedZoom else ZOOM
        )
    }
}
