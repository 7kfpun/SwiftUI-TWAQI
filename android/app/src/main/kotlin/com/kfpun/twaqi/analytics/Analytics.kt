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

    /** Does nothing when Firebase is not set up (no `google-services.json`). */
    fun logEvent(context: Context, name: String, parameters: Map<String, String> = emptyMap()) {
        if (FirebaseApp.getApps(context).isEmpty()) return
        val bundle = Bundle().apply { parameters.forEach { (key, value) -> putString(key, value) } }
        FirebaseAnalytics.getInstance(context).logEvent(name, bundle)
    }
}
