package com.kfpun.twaqi.analytics

import android.content.Context
import android.os.Bundle
import com.google.firebase.FirebaseApp
import com.google.firebase.analytics.FirebaseAnalytics

/** Firebase Analytics events, named as on iOS (`AnalyticsEvent.swift`). */
object Analytics {
    /** `label`: the language id (`system`, `zh-Hant`, `en`). */
    const val SELECT_LANGUAGE = "select_language"

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
