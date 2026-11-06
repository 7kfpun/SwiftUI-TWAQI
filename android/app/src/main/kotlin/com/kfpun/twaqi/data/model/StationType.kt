package com.kfpun.twaqi.data.model

import androidx.annotation.StringRes
import com.kfpun.twaqi.R

/**
 * `station_type` from the API (iOS `StationTypes`). Micro-sensor stations send `""`, so
 * [UNKNOWN] is a normal case, not an error.
 */
enum class StationType(val apiValue: String, @param:StringRes val label: Int?) {
    GENERAL("GENERAL", R.string.stationtype_general),
    TRAFFIC("TRAFFIC", R.string.stationtype_traffic),
    INDUSTRIAL("INDUSTRIAL", R.string.stationtype_industrial),
    BACKGROUND("BACKGROUND", R.string.stationtype_background),
    NATIONAL_PARK("NATIONAL-park", R.string.stationtype_national_park),
    OTHER("OTHER", R.string.stationtype_other),
    UNKNOWN("", null)
    ;

    /** [UNKNOWN] carries nothing worth showing. */
    val isDisplayable: Boolean get() = this != UNKNOWN

    companion object {
        fun fromApi(value: String?): StationType = entries.firstOrNull { it.apiValue == (value ?: "") } ?: UNKNOWN
    }
}
