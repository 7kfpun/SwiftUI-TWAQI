package com.kfpun.twaqi.widget

import android.content.Context
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.ui.main.GeoPoint
import com.kfpun.twaqi.ui.main.LocationAccess
import com.kfpun.twaqi.ui.main.MapPreferences
import com.kfpun.twaqi.ui.main.NearestStations

/**
 * Where "nearest" is measured from. A widget never asks for location: it uses the phone's last
 * known fix when the app has the permission, else where the reader last left the app's map (iOS
 * follows the station the app last showed), else 中正 in Taipei, as iOS does before the app has
 * ever run (`WatchAPI.defaultLocation`).
 */
object WidgetLocation {
    val DEFAULT = GeoPoint(25.0326, 121.5199)

    fun point(context: Context): GeoPoint {
        val prefs = context.getSharedPreferences(MapPreferences.PREFS, Context.MODE_PRIVATE)
        return choose(
            lastKnown = LocationAccess.lastKnown(context),
            mapLat = prefs.getFloat(MapPreferences.KEY_LAT, 0f).toDouble(),
            mapLon = prefs.getFloat(MapPreferences.KEY_LON, 0f).toDouble()
        )
    }

    /** 0/0 means the map never saved a camera. */
    fun choose(lastKnown: GeoPoint?, mapLat: Double, mapLon: Double): GeoPoint = lastKnown
        ?: if (mapLat == 0.0 && mapLon == 0.0) DEFAULT else GeoPoint(mapLat, mapLon)

    /** The station nearest [point] among [pollutants], as the map's closest-station card picks it. */
    fun nearest(pollutants: List<Pollutant>, point: GeoPoint): Pollutant? = NearestStations.closest(pollutants, point)
}
