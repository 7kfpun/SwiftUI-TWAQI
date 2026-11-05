package com.kfpun.twaqi.pro

import android.app.Activity
import android.content.Context
import android.content.Intent

/**
 * The one way into the Pro screen. Entry points:
 * - the Pro row in Help / settings ([ProScreenSource.HELP_ROW], [ProSettingsRow]),
 * - "Remove ads" beside a banner ([ProScreenSource.AD_BANNER], `AdBanner`),
 * - the alert limit on a station's alerts ([ProScreenSource.ALERT_LIMIT]), when that screen lands,
 * - the locked widget ([ProScreenSource.WIDGET_LOCKED]): a `PendingIntent` over [intent],
 * - onboarding ([ProScreenSource.ONBOARDING]),
 * - `twaqi://pro?source=…` links ([ProDeepLink]).
 */
object ProNavigation {
    const val EXTRA_SOURCE = "com.kfpun.twaqi.extra.PRO_SOURCE"

    fun intent(context: Context, source: ProScreenSource): Intent =
        Intent(context, ProActivity::class.java).putExtra(EXTRA_SOURCE, source.analyticsName)

    fun open(context: Context, source: ProScreenSource) {
        val intent = intent(context, source)
        if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }
}

/** `twaqi://pro?source=…`, as on iOS (`DeepLink.pro`). */
object ProDeepLink {
    const val SCHEME = "twaqi"
    const val HOST = "pro"
    const val SOURCE_PARAMETER = "source"

    /** The source for a Pro link, or null for any other URL. Unknown sources count as [ProScreenSource.DEEP_LINK]. */
    fun source(scheme: String?, host: String?, path: String?, sourceParameter: String?): ProScreenSource? {
        if (!scheme.equals(SCHEME, ignoreCase = true) || !host.equals(HOST, ignoreCase = true)) return null
        if (!path.isNullOrEmpty() && path.trim('/').isNotEmpty()) return null
        return ProScreenSource.fromAnalyticsName(sourceParameter)
    }
}
