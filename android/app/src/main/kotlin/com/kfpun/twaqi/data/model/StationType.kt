package com.kfpun.twaqi.data.model

import androidx.annotation.StringRes
import com.kfpun.twaqi.R

/**
 * `station_type` from the API (iOS `StationTypes`). Micro-sensor stations send `""`, so
 * [UNKNOWN] is a normal case, not an error.
 */
enum class StationType(val apiValue: String, @param:StringRes val label: Int?) {
    GENERAL("GENERAL", R.string.station_type_general),
    TRAFFIC("TRAFFIC", R.string.station_type_traffic),
    INDUSTRIAL("INDUSTRIAL", R.string.station_type_industrial),
    BACKGROUND("BACKGROUND", R.string.station_type_background),
    NATIONAL_PARK("NATIONAL-park", R.string.station_type_national_park),
    OTHER("OTHER", R.string.station_type_other),
    UNKNOWN("", null)
    ;

    /** [UNKNOWN] carries nothing worth showing. */
    val isDisplayable: Boolean get() = this != UNKNOWN

    companion object {
        fun fromApi(value: String?): StationType = entries.firstOrNull { it.apiValue == (value ?: "") } ?: UNKNOWN
    }
}
