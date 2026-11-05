package com.kfpun.twaqi.analytics

import android.content.Context
import android.os.Bundle
import com.google.firebase.FirebaseApp
import com.google.firebase.analytics.FirebaseAnalytics

/** Firebase Analytics events, named as on iOS (`AnalyticsEvent.swift`). */
object Analytics {
    /** `label`: the language id (`system`, `zh-Hant`, `en`). */
    const val SELECT_LANGUAGE = "select_language"

    // Station page and Favourites (FOX-55).

    /** `name`, `nameLocal`, `stationId`: a station page opened. */
    const val CHECK_MAIN_DETAILS = "check_main_details"

    /** `label`: on / off, `stationId`. One per station, also when several leave at once. */
    const val FAVOURITE_STATION_SAVED = "favourite_station_saved"
    const val FAVOURITE_STATION_REORDERED = "favourite_station_reordered"

    /** `label`: the index (`aqi`, `pm25`, …). */
    const val OPEN_DEFINITION_PAGE = "open_definition_page"

    /** `source`: where the feedback form was opened from (`station_page`). */
    const val OPEN_FEEDBACK_FORM = "open_feedback_form"

    /** Does nothing when Firebase is not set up (no `google-services.json`). */
    fun logEvent(context: Context, name: String, parameters: Map<String, String> = emptyMap()) {
        if (FirebaseApp.getApps(context).isEmpty()) return
        val bundle = Bundle().apply { parameters.forEach { (key, value) -> putString(key, value) } }
        FirebaseAnalytics.getInstance(context).logEvent(name, bundle)
    }
}
