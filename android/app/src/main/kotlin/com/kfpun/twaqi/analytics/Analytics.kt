package com.kfpun.twaqi.analytics

import android.content.Context
import android.os.Bundle
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.analytics.FirebaseAnalytics
import com.kfpun.twaqi.BuildConfig

/**
 * Firebase Analytics events, named as on iOS (`AnalyticsEvent.swift`, `docs/analytics.md`). Every
 * event goes through [logEvent]. Never rename one: Firebase would count the new name separately.
 * Whether anything is sent is [TrackingManager]'s call (debug builds and opted-out installs don't).
 */
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

    // Pro upsell funnel (FOX-58): pro_screen_opened → pro_plan_selected →
    // user_premium_buy_product_done, each with `source`.

    /** `source`: where the Pro screen was opened from. */
    const val PRO_SCREEN_OPENED = "pro_screen_opened"

    /** `plan` (1m / 6m / 12m), `source`. */
    const val PRO_PLAN_SELECTED = "pro_plan_selected"

    /** `plan`, `source`. Fires with `pro_plan_selected`, as on iOS. */
    const val BUY_PRODUCT_STARTED = "user_premium_buy_product_started"

    /** `plan`, `source`. */
    const val BUY_PRODUCT_DONE = "user_premium_buy_product_done"

    /** `plan`, `source`. Sheet closed, or the payment is pending. */
    const val BUY_PRODUCT_NOT_COMPLETED = "user_premium_buy_product_not_completed"

    /** `plan`, `source`. */
    const val BUY_PRODUCT_FAILED = "user_premium_buy_product_failed"

    /** `source`. */
    const val RESTORE_PURCHASE_STARTED = "user_premium_restore_purchase_started"

    /** `source`. */
    const val RESTORE_PURCHASE_DONE = "user_premium_restore_purchase_done"

    /** `source`. */
    const val RESTORE_PURCHASE_FAILED = "user_premium_restore_purchase_failed"

    /** `placement`: AdMob recorded a click on a banner. */
    const val AD_BANNER_TAPPED = "ad_banner_tapped"

    // Map (FOX-54), as on iOS.

    /** `label`: the index (`aqi`, `pm25`, …). */
    const val SELECT_INDEX = "select_index"
    const val MOVE_TO_CURRENT_LOCATION = "move_to_current_location"
    const val MOVE_TO_DEFAULT_LOCATION = "move_to_default_location"

    /** `label`: landscape / portrait. */
    const val CHANGE_DEVICE_ORIENTATION = "change_device_orientation"

    /** A map marker opened its station: `name`, `nameLocal`, `stationId`. */
    const val CHECK_MAIN_DETAILS = "check_main_details"

    // Station page and Favourites (FOX-55).

    /** `label`: on / off, `stationId`. One per station, also when several leave at once. */
    const val FAVOURITE_STATION_SAVED = "favourite_station_saved"
    const val FAVOURITE_STATION_REORDERED = "favourite_station_reordered"

    // Feedback and review (FOX-60), as on iOS.

    /** `source` ([com.kfpun.twaqi.feedback.FeedbackSource]): where the form was opened from. */
    const val OPEN_FEEDBACK_FORM = "open_feedback_form"

    /** `platform`, `rating` (1–5), `interview_interest` (1 / 0). */
    const val SUBMIT_FEEDBACK = "submit_feedback"

    /** `reason`, as for [SUBMIT_COOPERATE_FAILED]. */
    const val SUBMIT_FEEDBACK_FAILED = "submit_feedback_failed"

    /**
     * `source` (`app_opens` / `feedback`), plus `app_open_count` or `rating`. The app asked Play
     * for the review prompt; Play decides whether it shows.
     */
    const val REVIEW_REQUESTED = "review_requested"

    /** `source`: feedback. "Rate on Google Play" tapped in the thank-you after a 4- or 5-star feedback. */
    const val WRITE_REVIEW_TAPPED = "write_review_tapped"

    // Widgets (FOX-59), as on iOS.

    /** `source` (widget, tile, deep_link), `stationId`: a `twaqi://station` link opened its station. */
    const val STATION_LINK_OPENED = "station_link_opened"

    /**
     * Logs [name] with [parameters]: text as strings, whole numbers as longs, other numbers as
     * doubles, and booleans as 1 / 0 (how Firebase records the iOS app's booleans). Does nothing
     * when Firebase is not set up (no `google-services.json`) or this launch doesn't report.
     */
    fun logEvent(context: Context, name: String, parameters: Map<String, Any> = emptyMap()) {
        if (BuildConfig.DEBUG) Log.d("Analytics", "LogEvent $name $parameters")
        if (FirebaseApp.getApps(context).isEmpty()) return
        if (!TrackingManager.get(context).isReporting) return
        FirebaseAnalytics.getInstance(context).logEvent(name, bundle(parameters))
    }

    private fun bundle(parameters: Map<String, Any>) = Bundle().apply {
        parameters.forEach { (key, value) ->
            when (value) {
                is Boolean -> putLong(key, if (value) 1L else 0L)
                is Int -> putLong(key, value.toLong())
                is Long -> putLong(key, value)
                is Number -> putDouble(key, value.toDouble())
                else -> putString(key, value.toString())
            }
        }
    }
}
