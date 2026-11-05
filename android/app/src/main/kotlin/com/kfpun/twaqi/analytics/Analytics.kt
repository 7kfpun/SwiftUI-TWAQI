package com.kfpun.twaqi.analytics

import android.content.Context
import android.os.Bundle
import com.google.firebase.FirebaseApp
import com.google.firebase.analytics.FirebaseAnalytics

/** Firebase Analytics events, named as on iOS (`AnalyticsEvent.swift`). */
object Analytics {
    /** `label`: the language id (`system`, `zh-Hant`, `en`). */
    const val SELECT_LANGUAGE = "select_language"

    /** Does nothing when Firebase is not set up (no `google-services.json`). */
    fun logEvent(context: Context, name: String, parameters: Map<String, String> = emptyMap()) {
        if (FirebaseApp.getApps(context).isEmpty()) return
        val bundle = Bundle().apply { parameters.forEach { (key, value) -> putString(key, value) } }
        FirebaseAnalytics.getInstance(context).logEvent(name, bundle)
    }
}
