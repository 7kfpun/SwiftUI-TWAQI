package com.kfpun.twaqi.widget

import android.content.Context
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import java.time.Instant

/**
 * Fetches the widgets' readings and redraws them ([WidgetRefreshSchedule]). Offline, or when a
 * request fails, the widgets keep their last saved readings and say how old they are. A
 * redraw-only run (the 30-minute page reset) never fetches.
 */
class WidgetRefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val context = applicationContext
        val placed = WidgetUpdater.placed(context)
        if (placed.isEmpty()) {
            WidgetUpdater.syncSchedule(context)
            return Result.success()
        }
        if (inputData.getBoolean(WidgetRefreshSchedule.KEY_REDRAW_ONLY, false)) {
            placed.forEach { WidgetUpdater.redraw(context, it.widget, it.id) }
            return Result.success()
        }

        // Read before the fetch: a tap during it is newer than the readings and stays (iOS `afterFetch`).
        val before = placed.associate {
            it.id to getAppWidgetState(context, PreferencesGlanceStateDefinition, it.id)
        }
        val configs = placed.map { WidgetStateKeys.config(before.getValue(it.id)) to it.showsStationDetail }
        val hasNewData = WidgetDataSource(context).refresh(configs)
        val now = Instant.now()

        placed.forEach { widget ->
            val readBefore = WidgetStateKeys.pageState(before.getValue(widget.id))
            updateAppWidgetState(context, widget.id) { prefs ->
                val current = WidgetStateKeys.pageState(prefs)
                WidgetStateKeys.writePageState(prefs, WidgetPaging.afterFetch(current, readBefore, hasNewData, now))
                prefs[WidgetStateKeys.OFFLINE] = !hasNewData
                WidgetStateKeys.bumpVersion(prefs, now)
            }
            widget.widget.update(context, widget.id)
        }
        return Result.success()
    }
}
