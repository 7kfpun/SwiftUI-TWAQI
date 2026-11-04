//
//  AnalyticsEvent.swift
//  TWAQI
//
//  Created by kf on 3/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import Foundation

/// Every event the app logs through `TrackingManager`, in one list so the
/// names stay consistent (FOX-44). The raw value is the name Firebase
/// Analytics records: renaming one splits its history in two, so add a case
/// rather than change an old one.
///
/// Parameters never carry personal data: station ids are fine, coordinates
/// and form contents are not.
enum AnalyticsEvent: String, CaseIterable {
    // MARK: Pro upsell funnel
    // pro_screen_opened → pro_plan_selected → user_premium_buy_product_done,
    // each with `source` (`ProScreenSource`), so the funnel reads per source.

    /// `source`: where the Pro screen was opened from.
    case proScreenOpened = "pro_screen_opened"
    /// `plan` (`ProPlan`), `source`.
    case proPlanSelected = "pro_plan_selected"
    /// `plan`, `source`. Fires with `pro_plan_selected`, since a tap starts
    /// the purchase; kept so its history carries on.
    case buyProductStarted = "user_premium_buy_product_started"
    /// `plan`, `source`.
    case buyProductDone = "user_premium_buy_product_done"
    /// `plan`, `source`. StoreKit sheet closed, or the purchase is pending
    /// (Ask to Buy): neither done nor failed.
    case buyProductNotCompleted = "user_premium_buy_product_not_completed"
    /// `plan`, `source`.
    case buyProductFailed = "user_premium_buy_product_failed"
    /// `source`.
    case restorePurchaseStarted = "user_premium_restore_purchase_started"
    /// `source`.
    case restorePurchaseDone = "user_premium_restore_purchase_done"
    /// `source`.
    case restorePurchaseFailed = "user_premium_restore_purchase_failed"
    /// `stationId`: the "at most three stations" note (`FavouriteAlerts.maxAlertedStations`) on a station's alerts.
    case alertLimitShown = "alert_limit_shown"
    /// `placement` (`AdPlacement`): AdMob recorded a click on a banner.
    case adBannerTapped = "ad_banner_tapped"

    // MARK: Feedback and review

    /// `source` (`FeedbackSource`): where the form was opened from.
    case openFeedbackForm = "open_feedback_form"
    /// `platform`, `rating`, `interview_interest`.
    case submitFeedback = "submit_feedback"
    /// `reason`.
    case submitFeedbackFailed = "submit_feedback_failed"
    case openCooperateForm = "open_cooperate_form"
    /// `cooperation_type`.
    case submitCooperate = "submit_cooperate"
    /// `reason`.
    case submitCooperateFailed = "submit_cooperate_failed"
    /// `app_open_count`: the app opens that triggered it. iOS decides
    /// whether the prompt actually shows.
    case reviewRequested = "review_requested"

    // MARK: Onboarding

    /// `label`: launch. The flow opened by itself at launch.
    case onboardingShown = "onboarding_shown"
    /// `step` (`Onboarding.Step.analyticsName`), `index` (1-based).
    case onboardingStepViewed = "onboarding_step_viewed"
    /// `label`: on / off, the answer to the location prompt.
    case onboardingLocation = "onboarding_location"
    /// `label`: on / off, the answer to the notification prompt.
    case onboardingNotifications = "onboarding_notifications"
    /// `stationId`.
    case onboardingAddFavourite = "onboarding_add_favourite"
    case onboardingOpenPro = "onboarding_open_pro"
    /// `label`: step_<index>, the step "Skip" was tapped on.
    case onboardingSkipped = "onboarding_skipped"
    case onboardingCompleted = "onboarding_completed"
    case onboardingOpenFromHelp = "onboarding_open_from_help"

    // MARK: Favourites and alerts

    /// `label`: on / off, `stationId`, `source` (alert, when an alert added it).
    case favouriteStationSaved = "favourite_station_saved"
    case favouriteStationReordered = "favourite_station_reordered"
    case favouriteStationAllRemoved = "favourite_station_all_removed"
    /// `stationId`.
    case stationAlertsClearedByUnfavourite = "station_alerts_cleared_by_unfavourite"
    /// `outcome`, `stationId`.
    case stationAlertsOnFavourite = "station_alerts_on_favourite"

    // MARK: Map and station

    /// `label`: the index.
    case selectIndex = "select_index"
    /// `label`: on / off.
    case setWindMode = "set_wind_mode"
    case moveToCurrentLocation = "move_to_current_location"
    case moveToDefaultLocation = "move_to_default_location"
    case mapTimelinePlay = "map_timeline_play"
    /// `label`: landscape / portrait.
    case changeDeviceOrientation = "change_device_orientation"
    /// `name`, `nameLocal`, `stationId`.
    case checkMainDetails = "check_main_details"
    /// The share preview opened (FOX-73): `stationId`, `aqi`, `shape`
    /// (`4x5`, `9x16`, `1x1`). Against `shareCard`, how many back out.
    case shareCardPreviewOpened = "share_card_preview_opened"
    /// `stationId`, `aqi`, `shape`, `action`: `share` (the system sheet
    /// opened), `save` (saved to Photos) or `cancel` (closed the preview
    /// without either).
    case shareCard = "share_card"

    // MARK: Help and settings

    /// `label`: the language.
    case selectLanguage = "select_language"
    /// `label`: on / off, `dndStartTime`, `dndEndTime`.
    case setDndNotification = "set_dnd_notification"
    case setDndNotificationStartTime = "set_dnd_notification_start_time"
    case setDndNotificationEndTime = "set_dnd_notification_end_time"
    /// `label`: the page.
    case openDefinitionPage = "open_definition_page"
    case openWidgetGuide = "open_widget_guide"
    case openWatchGuide = "open_watch_guide"
}
