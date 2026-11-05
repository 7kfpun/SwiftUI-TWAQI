package com.kfpun.twaqi.widget

import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequest
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.workDataOf
import java.time.Duration
import java.time.Instant

/**
 * When the widgets refresh (iOS `ReadingProvider.refreshInterval`). Pure apart from building the
 * requests, so the schedule is unit tested; [WidgetUpdater] hands them to WorkManager.
 *
 * - Every 30 minutes while any widget is placed: readings are published hourly, and half that
 *   keeps a widget at most one publish behind. WorkManager batches the run into its flex window,
 *   and only runs it with a network and the battery not low, so a phone saving battery keeps the
 *   last readings (with their time) instead of waking for new ones.
 * - Once right away when a widget is added or set up, also only with a network.
 * - A paged widget redraws without the network when its 30 minutes run out
 *   ([WidgetPaging.resetInterval]), so it goes back to its own station on time.
 */
object WidgetRefreshSchedule {
    const val PERIODIC_WORK = "widget-refresh"
    const val NOW_WORK = "widget-refresh-now"
    const val RESET_WORK_PREFIX = "widget-page-reset-"

    /** Input of a redraw-only run: no fetch. */
    const val KEY_REDRAW_ONLY = "redrawOnly"

    val interval: Duration = Duration.ofMinutes(30)
    val flex: Duration = Duration.ofMinutes(10)

    /** Keep the running schedule when it is asked for again, as every widget update does. */
    val periodicPolicy = ExistingPeriodicWorkPolicy.KEEP

    val constraints: Constraints = Constraints.Builder()
        .setRequiredNetworkType(NetworkType.CONNECTED)
        .setRequiresBatteryNotLow(true)
        .build()

    /** Refresh only while at least one widget is on a home screen. */
    fun shouldSchedule(placedWidgets: Int): Boolean = placedWidgets > 0

    fun periodicRequest(): PeriodicWorkRequest = PeriodicWorkRequestBuilder<WidgetRefreshWorker>(interval, flex)
        .setConstraints(constraints)
        .build()

    /** A widget was added or set up: fetch now, once a network is there. Battery isn't a constraint for one run. */
    fun refreshNowRequest(): OneTimeWorkRequest = OneTimeWorkRequestBuilder<WidgetRefreshWorker>()
        .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
        .build()

    val refreshNowPolicy = ExistingWorkPolicy.REPLACE

    /**
     * The redraw at [resetAt], when a paged widget goes back to its own station; null when the
     * widget is on its own station. Never sooner than now.
     */
    fun resetDelay(resetAt: Instant?, now: Instant): Duration? {
        resetAt ?: return null
        val delay = Duration.between(now, resetAt)
        return if (delay.isNegative) Duration.ZERO else delay
    }

    fun resetRequest(delay: Duration): OneTimeWorkRequest = OneTimeWorkRequestBuilder<WidgetRefreshWorker>()
        .setInitialDelay(delay)
        .setInputData(workDataOf(KEY_REDRAW_ONLY to true))
        .build()

    fun resetWorkName(appWidgetId: Int): String = "$RESET_WORK_PREFIX$appWidgetId"
}
