package com.kfpun.twaqi.widget

import android.content.Context
import android.util.Log
import androidx.core.content.edit
import androidx.glance.GlanceId
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.work.WorkManager
import com.kfpun.twaqi.locale.AppLocale
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch

/**
 * Redraws and schedules the widgets (iOS `WidgetBridge` + `WidgetCenter`). The app calls it when
 * what the widgets show changes: favourites, Pro, the app language.
 */
object WidgetUpdater {
    private const val TAG = "TWAQIWidget"

    /** One placed widget: which kind it is and its id. */
    data class Placed(val widget: GlanceAppWidget, val id: GlanceId) {
        val showsStationDetail: Boolean get() = widget is StationDetailWidget
    }

    suspend fun placed(context: Context): List<Placed> {
        val manager = GlanceAppWidgetManager(context)
        return runCatching {
            manager.getGlanceIds(AirQualityWidget::class.java).map { Placed(AirQualityWidget(), it) } +
                manager.getGlanceIds(StationDetailWidget::class.java).map { Placed(StationDetailWidget(), it) }
        }.getOrElse {
            Log.w(TAG, "Couldn't list widgets", it)
            emptyList()
        }
    }

    suspend fun config(context: Context, placed: Placed): WidgetConfig =
        WidgetStateKeys.config(getAppWidgetState(context, PreferencesGlanceStateDefinition, placed.id))

    /** Redraws one widget from saved data, without the network. */
    suspend fun redraw(context: Context, widget: GlanceAppWidget, id: GlanceId, now: Instant = Instant.now()) {
        updateAppWidgetState(context, id) { WidgetStateKeys.bumpVersion(it, now) }
        widget.update(context, id)
    }

    /** Redraws every widget: favourites, Pro or the language changed. */
    suspend fun redrawAll(context: Context) {
        placed(context).forEach { redraw(context, it.widget, it.id) }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** [redrawAll] from code that isn't suspending (the language picker), noting the language drawn in. */
    fun requestRedrawAll(context: Context) {
        val app = context.applicationContext
        languagePrefs(app).edit { putString(KEY_DRAWN_LANGUAGE, AppLocale.locale(app).toLanguageTag()) }
        scope.launch { redrawAll(app) }
        // The picker's previews follow the language too (FOX-120).
        WidgetPreviews.publishIfNeeded(app)
    }

    /**
     * At app start: Android 13+ lets Settings change the app's language while the app isn't
     * running, so nothing told the widgets. Redraws them when the language differs from the one
     * they were last drawn in.
     */
    fun redrawIfLanguageChanged(context: Context) {
        val app = context.applicationContext
        val drawn = languagePrefs(app).getString(KEY_DRAWN_LANGUAGE, null)
        if (drawn != AppLocale.locale(app).toLanguageTag()) requestRedrawAll(app)
    }

    private const val LANGUAGE_PREFS = "widget_language"
    private const val KEY_DRAWN_LANGUAGE = "drawn"

    private fun languagePrefs(context: Context) = context.getSharedPreferences(LANGUAGE_PREFS, Context.MODE_PRIVATE)

    /**
     * Keeps the widgets in step with the favourites while the app's process runs (iOS
     * `WidgetBridge.publish(favouriteStationIds:)`), and checks the refresh schedule once.
     */
    fun observeFavourites(context: Context, favourites: Flow<List<Int>>) {
        val app = context.applicationContext
        scope.launch { syncSchedule(app) }
        // The first value is what the widgets already show.
        scope.launch { favourites.drop(1).collect { redrawAll(app) } }
    }

    /**
     * Buying Pro, or Play turning it off, redraws every widget (iOS `WidgetBridge.publish(isPro:)`).
     * Called once by [com.kfpun.twaqi.pro.ProGraph] when it creates the repository.
     */
    fun observePro(context: Context, isPro: Flow<Boolean>) {
        val app = context.applicationContext
        scope.launch { isPro.drop(1).collect { redrawAll(app) } }
    }

    /** Starts the 30-minute refresh while any widget is placed, and stops it when none is. */
    suspend fun syncSchedule(context: Context) {
        val workManager = WorkManager.getInstance(context)
        if (WidgetRefreshSchedule.shouldSchedule(placed(context).size)) {
            workManager.enqueueUniquePeriodicWork(
                WidgetRefreshSchedule.PERIODIC_WORK,
                WidgetRefreshSchedule.periodicPolicy,
                WidgetRefreshSchedule.periodicRequest()
            )
        } else {
            workManager.cancelUniqueWork(WidgetRefreshSchedule.PERIODIC_WORK)
        }
    }

    /** A widget was added or set up: fetch once now (with a network) and keep the schedule. */
    suspend fun refreshNow(context: Context) {
        WorkManager.getInstance(context).enqueueUniqueWork(
            WidgetRefreshSchedule.NOW_WORK,
            WidgetRefreshSchedule.refreshNowPolicy,
            WidgetRefreshSchedule.refreshNowRequest()
        )
        syncSchedule(context)
    }

    /** Plans the redraw when a paged widget goes back to its own station, or cancels it. */
    fun scheduleReset(context: Context, appWidgetId: Int, resetAt: Instant?, now: Instant = Instant.now()) {
        val workManager = WorkManager.getInstance(context)
        val name = WidgetRefreshSchedule.resetWorkName(appWidgetId)
        val delay = WidgetRefreshSchedule.resetDelay(resetAt, now)
        if (delay == null) {
            workManager.cancelUniqueWork(name)
        } else {
            workManager.enqueueUniqueWork(
                name,
                androidx.work.ExistingWorkPolicy.REPLACE,
                WidgetRefreshSchedule.resetRequest(delay)
            )
        }
    }
}
