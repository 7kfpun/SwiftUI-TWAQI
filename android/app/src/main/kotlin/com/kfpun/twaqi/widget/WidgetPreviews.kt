package com.kfpun.twaqi.widget

import android.content.Context
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.core.content.edit
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import com.kfpun.twaqi.locale.AppLocale
import kotlin.reflect.KClass
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * The widget picker's previews (FOX-120). API 35+ shows a generated preview: each widget's
 * `providePreview` drawn from [WidgetPreviewData], published here with
 * [GlanceAppWidgetManager.setWidgetPreviews]. Older versions show the static `previewLayout`
 * (API 31+) or `previewImage` in `res/xml/widget_*_info.xml`, captures of the same preview.
 *
 * A published preview is a fixed drawing, so it is published again only when it could differ:
 * after an install or update (new layout) and in another app language. The system rate-limits
 * the call; a refused one is tried again at the next start.
 */
object WidgetPreviews {
    private const val TAG = "TWAQIWidget"
    private const val PREFS = "widget_previews"

    /** Small, medium and large, at the sizes [WidgetFamily.forSize] switches at. */
    val airQualitySizes: Set<DpSize> = setOf(
        DpSize(110.dp, 110.dp),
        DpSize(WidgetFamily.MEDIUM_MIN_WIDTH_DP.dp, 110.dp),
        DpSize(WidgetFamily.MEDIUM_MIN_WIDTH_DP.dp, WidgetFamily.LARGE_MIN_HEIGHT_DP.dp),
        DpSize(320.dp, 380.dp)
    )

    /** Station detail's narrow layout and its wide one (300dp and up), at heights that keep the forecast. */
    val stationDetailSizes: Set<DpSize> = setOf(
        DpSize(250.dp, 360.dp),
        DpSize(300.dp, 300.dp),
        DpSize(340.dp, 400.dp)
    )

    private val receivers: List<KClass<out GlanceAppWidgetReceiver>> = listOf(
        AirQualityWidgetReceiver::class,
        StationDetailWidgetReceiver::class
    )

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /**
     * What a published preview was drawn with: the install (its last update time) and the app
     * language. Different from the stored one means publish again.
     */
    fun drawnWith(lastUpdateTime: Long, languageTag: String): String = "$lastUpdateTime|$languageTag"

    /** At app start and when the app language changes: publishes any preview that is out of date. */
    fun publishIfNeeded(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) return
        val app = context.applicationContext
        // One at a time, so a second call at start (the language check) finds the first one's work done.
        scope.launch {
            publishing.withLock { publishStale(app) }
        }
    }

    private val publishing = Mutex()

    @RequiresApi(Build.VERSION_CODES.VANILLA_ICE_CREAM)
    private suspend fun publishStale(app: Context) {
        val key = drawnWith(
            lastUpdateTime = runCatching {
                app.packageManager.getPackageInfo(app.packageName, 0).lastUpdateTime
            }.getOrDefault(0L),
            languageTag = AppLocale.locale(app).toLanguageTag()
        )
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val stale = receivers.filter { prefs.getString(it.qualifiedName, null) != key }
        if (stale.isNotEmpty()) {
            val manager = GlanceAppWidgetManager(app)
            stale.forEach { receiver ->
                val result = runCatching { manager.setWidgetPreviews(receiver) }
                    .onFailure { Log.w(TAG, "Couldn't publish the ${receiver.simpleName} preview", it) }
                    .getOrNull()
                if (result == GlanceAppWidgetManager.SET_WIDGET_PREVIEWS_RESULT_SUCCESS) {
                    prefs.edit { putString(receiver.qualifiedName, key) }
                } else if (result != null) {
                    Log.i(TAG, "${receiver.simpleName} preview not published ($result), retried at the next start")
                }
            }
        }
    }
}
