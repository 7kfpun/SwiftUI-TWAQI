package com.kfpun.twaqi.feedback

import android.app.Activity
import android.content.Context
import android.content.Intent

/**
 * Opens the feedback form on its own screen, for entry points outside Help: the station page's
 * "Send feedback" link (FOX-55) passes [FeedbackSource.STATION_PAGE]. Help opens the same form
 * inside its own page stack.
 */
object FeedbackNavigation {
    const val EXTRA_SOURCE = "com.kfpun.twaqi.extra.FEEDBACK_SOURCE"

    fun intent(context: Context, source: FeedbackSource): Intent =
        Intent(context, FeedbackActivity::class.java).putExtra(EXTRA_SOURCE, source.analyticsName)

    fun open(context: Context, source: FeedbackSource) {
        val intent = intent(context, source)
        if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }
}
