package com.kfpun.twaqi.ads

import com.google.android.gms.ads.AdSize
import com.kfpun.twaqi.pro.Entitlement

object AdsPolicy {
    /** Every banner is the standard 320x50, as on iOS (`AdSizeBanner`, FOX-61). */
    val bannerSize: AdSize = AdSize.BANNER

    /**
     * Banners are for free users, once consent allows ads. Pro hides them; so does
     * an entitlement not read yet, so a Pro user never sees one flash in on launch.
     * A pending payment isn't Pro yet, so it still gets ads.
     */
    fun showBanner(entitlement: Entitlement?, canRequestAds: Boolean): Boolean =
        canRequestAds && (entitlement == Entitlement.FREE || entitlement == Entitlement.PENDING)
}
