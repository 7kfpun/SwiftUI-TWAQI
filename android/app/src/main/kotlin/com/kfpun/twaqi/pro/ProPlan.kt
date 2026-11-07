package com.kfpun.twaqi.pro

/**
 * The Play products behind Pro (FOX-58).
 *
 * iOS sells three auto-renewing subscriptions in one subscription group
 * (`com.kfpun.twaqi.subscription.adfree.1m`, `.6m`, `.12m`). Play's version of a
 * group is one subscription with a base plan per period: a buyer holds one plan
 * at a time, and changing plan is an upgrade or downgrade of the same
 * subscription rather than a second one.
 */
object ProProducts {
    /** The Play subscription; its base plans are [ProPlan.basePlanId]. */
    const val SUBSCRIPTION_ID = "com.kfpun.twaqi.subscription.adfree"

    /**
     * Lifetime Pro (FOX-123): a one-time (INAPP) product with the id of iOS's
     * original non-consumable ad-free purchase, still sold there as the lifetime option.
     */
    const val LIFETIME_ID = "com.kfpun.twaqi.adfree"

    /** Every product that counts as Pro. */
    val productIds: Set<String> = setOf(SUBSCRIPTION_ID, LIFETIME_ID)
}

/**
 * A Pro plan, named for the funnel events (`plan`) as on iOS (`ProPlan`), so the
 * reports read "6m" or "lifetime" on both platforms. The entries are in the iOS
 * display order (`IAPManager.products()`): subscriptions shortest first, then lifetime.
 */
enum class ProPlan(val analyticsName: String, val productId: String, val basePlanId: String?, val months: Int?) {
    ONE_MONTH("1m", ProProducts.SUBSCRIPTION_ID, "adfree-1m", 1),
    SIX_MONTHS("6m", ProProducts.SUBSCRIPTION_ID, "adfree-6m", 6),
    TWELVE_MONTHS("12m", ProProducts.SUBSCRIPTION_ID, "adfree-12m", 12),

    /** Paid once, never renews: no base plan and no period. */
    LIFETIME("lifetime", ProProducts.LIFETIME_ID, null, null)
    ;

    /** The plan marked "Best value", the longest subscription, as on iOS. */
    val isBestValue: Boolean get() = this == TWELVE_MONTHS

    val isLifetime: Boolean get() = this == LIFETIME

    companion object {
        fun forBasePlan(basePlanId: String?): ProPlan? =
            basePlanId?.let { id -> entries.firstOrNull { it.basePlanId == id } }
    }
}

/** Offers in the order the Pro screen and onboarding list them: [ProPlan]'s, as on iOS. */
fun List<PlanOffer>.inDisplayOrder(): List<PlanOffer> = sortedBy { it.plan.ordinal }

/** Where the Pro screen was opened from, logged as `source` with every step of the funnel. */
enum class ProScreenSource(val analyticsName: String) {
    /** The Pro row in Help / settings (iOS: the "Ad-free" row in Help). */
    HELP_ROW("help_row"),

    /** "See Pro plans" in onboarding. */
    ONBOARDING("onboarding"),

    /** The locked placeholder on a medium or large widget. */
    WIDGET_LOCKED("widget_locked"),

    /** A station's alerts, when the alert limit is reached. */
    ALERT_LIMIT("alert_limit"),

    /** "Remove ads" beside a banner. */
    AD_BANNER("ad_banner"),

    /** The Wear OS app's Pro screen, opened on the phone (FOX-62). */
    WATCH("watch"),

    /** `twaqi://pro` with no `source`, or one this build doesn't know. */
    DEEP_LINK("deep_link")
    ;

    companion object {
        fun fromAnalyticsName(name: String?): ProScreenSource =
            entries.firstOrNull { it.analyticsName == name } ?: DEEP_LINK
    }
}
