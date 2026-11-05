package com.kfpun.twaqi.ui.main

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import com.kfpun.twaqi.data.model.AirIndexType

/**
 * The map's saved state: the last camera and the selected index. Keys are iOS's defaults keys.
 * The same preferences file as the app language (FOX-56), so it follows the user to a new phone.
 */
class MapPreferences(private val prefs: SharedPreferences) {
    constructor(context: Context) : this(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE))

    var indexType: AirIndexType
        get() = AirIndexType.fromKey(prefs.getString(KEY_INDEX, null)) ?: AirIndexType.AQI
        set(value) = prefs.edit { putString(KEY_INDEX, value.key) }

    val initialCamera: MapTarget
        get() = MapHome.initialCamera(
            prefs.getFloat(KEY_LAT, 0f).toDouble(),
            prefs.getFloat(KEY_LON, 0f).toDouble(),
            prefs.getFloat(KEY_ZOOM, 0f)
        )

    fun saveCamera(target: MapTarget) = prefs.edit {
        putFloat(KEY_LAT, target.lat.toFloat())
        putFloat(KEY_LON, target.lon.toFloat())
        putFloat(KEY_ZOOM, target.zoom)
    }

    /** The map asks for location once by itself; after that only its button asks. */
    var askedForLocation: Boolean
        get() = prefs.getBoolean(KEY_ASKED_LOCATION, false)
        set(value) = prefs.edit { putBoolean(KEY_ASKED_LOCATION, value) }

    companion object {
        const val PREFS = "settings"
        const val KEY_INDEX = "airIndexTypeSelected"
        const val KEY_LAT = "lastestMapLat"
        const val KEY_LON = "lastestMapLon"
        const val KEY_ZOOM = "lastestMapZoom"
        const val KEY_ASKED_LOCATION = "mapAskedForLocation"
    }
}
