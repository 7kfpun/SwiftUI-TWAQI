package com.kfpun.twaqi.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import androidx.core.content.edit
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.ui.main.GeoPoint
import com.kfpun.twaqi.ui.main.LocationAccess
import com.kfpun.twaqi.ui.main.MapPreferences
import com.kfpun.twaqi.ui.main.NearestStations

/**
 * Where "nearest" is measured from. A widget never asks for location: it uses the phone's last
 * known fix when the app has the permission, else the fix the app last saw in the foreground
 * ([remember]: a background refresh can't read the last fix without background location, which
 * the app doesn't ask for), else where the reader last left the app's map (iOS follows the station
 * the app last showed), else 中正 in Taipei, as iOS does before the app has ever run
 * (`WatchAPI.defaultLocation`). The saved fix stays on the phone (left out of backups).
 */
object WidgetLocation {
    val DEFAULT = GeoPoint(25.0326, 121.5199)

    const val PREFS = "widget_location"
    private const val KEY_LAT = "lat"
    private const val KEY_LON = "lon"

    fun point(context: Context): GeoPoint {
        val map = context.getSharedPreferences(MapPreferences.PREFS, Context.MODE_PRIVATE)
        return choose(
            lastKnown = LocationAccess.lastKnown(context),
            saved = saved(context),
            mapLat = map.getFloat(MapPreferences.KEY_LAT, 0f).toDouble(),
            mapLon = map.getFloat(MapPreferences.KEY_LON, 0f).toDouble()
        )
    }

    /** 0/0 means the map never saved a camera. */
    fun choose(lastKnown: GeoPoint?, saved: GeoPoint?, mapLat: Double, mapLon: Double): GeoPoint = lastKnown
        ?: saved
        ?: if (mapLat == 0.0 && mapLon == 0.0) DEFAULT else GeoPoint(mapLat, mapLon)

    /** With the app in the foreground and a widget placed: keep the last fix for the next refresh. */
    fun remember(context: Context) {
        if (!hasWidgets(context)) return
        val fix = LocationAccess.lastKnown(context) ?: return
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit {
            putLong(KEY_LAT, fix.lat.toRawBits())
            putLong(KEY_LON, fix.lon.toRawBits())
        }
    }

    private fun saved(context: Context): GeoPoint? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.contains(KEY_LAT) || !prefs.contains(KEY_LON)) return null
        return GeoPoint(Double.fromBits(prefs.getLong(KEY_LAT, 0)), Double.fromBits(prefs.getLong(KEY_LON, 0)))
    }

    private fun hasWidgets(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context) ?: return false
        return listOf(AirQualityWidgetReceiver::class.java, StationDetailWidgetReceiver::class.java).any {
            manager.getAppWidgetIds(ComponentName(context, it)).isNotEmpty()
        }
    }

    /** The station nearest [point] among [pollutants], as the map's closest-station card picks it. */
    fun nearest(pollutants: List<Pollutant>, point: GeoPoint): Pollutant? = NearestStations.closest(pollutants, point)
}
