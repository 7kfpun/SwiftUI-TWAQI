package com.kfpun.twaqi.ads

import com.kfpun.twaqi.pro.Entitlement

object AdsPolicy {
    /**
     * Banners are for free users, once consent allows ads. Pro hides them; so does
     * an entitlement not read yet, so a Pro user never sees one flash in on launch.
     * A pending payment isn't Pro yet, so it still gets ads.
     */
    fun showBanner(entitlement: Entitlement?, canRequestAds: Boolean): Boolean =
        canRequestAds && (entitlement == Entitlement.FREE || entitlement == Entitlement.PENDING)
}
