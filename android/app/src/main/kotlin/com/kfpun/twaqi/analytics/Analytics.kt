package com.kfpun.twaqi.analytics

import android.content.Context
import android.os.Bundle
import com.google.firebase.FirebaseApp
import com.google.firebase.analytics.FirebaseAnalytics

/** Firebase Analytics events, named as on iOS (`AnalyticsEvent.swift`). */
object Analytics {
    /** `label`: the language id (`system`, `zh-Hant`, `en`). */
    const val SELECT_LANGUAGE = "select_language"

    /** `label`: the appearance id (`system`, `light`, `dark`). */
    const val SELECT_APPEARANCE = "select_appearance"

    /** `label`: the index page (`aqi`, `pm25`, …). */
    const val OPEN_DEFINITION_PAGE = "open_definition_page"

    const val OPEN_WIDGET_GUIDE = "open_widget_guide"

    /** The Wear OS guide; same name as the iOS watch guide. */
    const val OPEN_WATCH_GUIDE = "open_watch_guide"

    const val OPEN_COOPERATE_FORM = "open_cooperate_form"

    /** `cooperation_type`. */
    const val SUBMIT_COOPERATE = "submit_cooperate"

    /** `reason`: `offline`, `network`, `notConfigured` or `server(statusCode: …)`. */
    const val SUBMIT_COOPERATE_FAILED = "submit_cooperate_failed"

    /** Does nothing when Firebase is not set up (no `google-services.json`). */
    fun logEvent(context: Context, name: String, parameters: Map<String, String> = emptyMap()) {
        if (FirebaseApp.getApps(context).isEmpty()) return
        val bundle = Bundle().apply { parameters.forEach { (key, value) -> putString(key, value) } }
        FirebaseAnalytics.getInstance(context).logEvent(name, bundle)
    }
}
