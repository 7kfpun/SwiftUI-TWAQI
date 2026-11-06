package com.kfpun.twaqi.ads

import com.kfpun.twaqi.BuildConfig

/** Which screen a banner sits on, logged with `ad_banner_tapped` (iOS `AdPlacement`), and its ad unit. */
enum class AdPlacement(val analyticsName: String, val adUnitId: String) {
    MAIN("main", BuildConfig.AD_UNIT_ID_MAIN_FOOTER),
    DETAILS("details", BuildConfig.AD_UNIT_ID_DETAILS_FOOTER),
    DETAILS_LIST("details_list", BuildConfig.AD_UNIT_ID_DETAILS_LIST_FOOTER),
    FAVOURITES("favourites", BuildConfig.AD_UNIT_ID_FAVOURITES_FOOTER),
    HELP("help", BuildConfig.AD_UNIT_ID_HELP_FOOTER)
}
