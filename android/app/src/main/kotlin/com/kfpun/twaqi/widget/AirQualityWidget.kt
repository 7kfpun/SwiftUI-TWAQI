package com.kfpun.twaqi.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.Preferences
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.PreviewSizeMode
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.state.GlanceStateDefinition
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.glance.text.FontWeight
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.Pollutant
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * The air-quality widget (iOS `TWAQIWidget`): one station's level, colour and update time, with
 * the reader's other favourites. Resizable: drawn as small (free), medium or large (Pro) by its
 * size ([WidgetFamily.forSize]). Medium and large page through the favourites with ‹ ›, and every
 * size cycles its index when the label is tapped (FOX-76). Draws from saved readings only;
 * [WidgetRefreshWorker] fetches.
 */
class AirQualityWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Exact

    override val stateDefinition: GlanceStateDefinition<*> = PreferencesGlanceStateDefinition

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val source = WidgetDataSource(context)
        // Loaded before the first frame, so the widget never draws empty while it reads the caches.
        val initial = source.snapshot(
            WidgetStateKeys.config(getAppWidgetState<Preferences>(context, id)),
            includeHistory = false
        )
        provideContent {
            val prefs = currentState<Preferences>()
            val config = WidgetStateKeys.config(prefs)
            val version = prefs[WidgetStateKeys.VERSION] ?: 0L
            var snapshot by remember { mutableStateOf(initial) }
            LaunchedEffect(config, version) { snapshot = source.snapshot(config, includeHistory = false) }
            val text = remember(version) { WidgetText.of(context) }
            val size = LocalSize.current
            val family = WidgetFamily.forSize(size.width.value, size.height.value)
            GlanceTheme {
                snapshot.let { loaded ->
                    val entry = WidgetEntry.make(
                        family = family,
                        leading = loaded.leading,
                        config = config,
                        favouriteIds = loaded.favouriteIds,
                        readings = loaded.readings,
                        isPro = loaded.isPro,
                        state = WidgetStateKeys.pageState(prefs),
                        now = Instant.now()
                    )
                    AirQualityContent(
                        context = context,
                        entry = entry,
                        snapshot = loaded,
                        offline = prefs[WidgetStateKeys.OFFLINE] == true,
                        text = text,
                        heightDp = size.height.value
                    )
                }
            }
        }
    }

    /** The picker's preview draws each size it is shown at: small, medium, large. */
    override val previewSizeMode: PreviewSizeMode = SizeMode.Responsive(WidgetPreviews.airQualitySizes)

    /**
     * The widget picker's preview (API 35+, published by [WidgetPreviews]): the sample stations
     * ([WidgetPreviewData]) at each size, the Pro sizes unlocked, as iOS's gallery (`isPreview`).
     */
    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        val now = Instant.now()
        val snapshot = WidgetPreviewData.snapshot(now)
        val text = WidgetText.of(context)
        provideContent {
            val size = LocalSize.current
            val family = WidgetFamily.forSize(size.width.value, size.height.value)
            GlanceTheme {
                AirQualityContent(
                    context = context,
                    entry = WidgetPreviewData.entry(family, snapshot, now),
                    snapshot = snapshot,
                    offline = false,
                    text = text,
                    heightDp = size.height.value
                )
            }
        }
    }
}

@Composable
private fun AirQualityContent(
    context: Context,
    entry: WidgetEntry,
    snapshot: WidgetSnapshot,
    offline: Boolean,
    text: WidgetText,
    heightDp: Float
) {
    val reading = entry.reading
    when {
        entry.isLocked -> LockedPlaceholder(context, reading, text)

        reading == null -> EmptyWidget(context, text)

        else -> {
            val updated = text.updatedLine(reading, offline, snapshot.savedAt[reading.stationId])
            when (entry.family) {
                WidgetFamily.SMALL -> Small(context, entry, reading, updated, text)
                WidgetFamily.MEDIUM -> Medium(context, entry, reading, updated, text)
                else -> Large(context, entry, reading, updated, text, snapshot, heightDp)
            }
        }
    }
}

/** Small: the station on its band colour, big, and up to two favourites under it when there are any. */
@Composable
private fun Small(context: Context, entry: WidgetEntry, reading: Pollutant, updated: String?, text: WidgetText) {
    val type = entry.type
    val status = reading.status(type)
    val foreground = rgb(status.foregroundColor)
    val value = WidgetFormat.value(reading, type)
    if (entry.listedFavourites.isEmpty()) {
        WidgetContainer(onClick = WidgetTaps.app(context), background = rgb(status.color)) {
            Column(modifier = GlanceModifier.fillMaxSize()) {
                IndexLabel(type, entry.cyclesIndex, text, color = foreground)
                WidgetLabel(value, size = 40.sp, weight = FontWeight.Bold, color = foreground)
                WidgetLabel(text.status(status), size = 12.sp, weight = FontWeight.Medium, color = foreground)
                Spacer(GlanceModifier.defaultWeight())
                WidgetLabel(text.name(reading), size = 12.sp, color = foreground)
                updated?.let { WidgetLabel(it, size = 10.sp, color = foreground) }
            }
        }
        return
    }
    WidgetContainer(onClick = WidgetTaps.app(context), padding = 8.dp) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Row(
                modifier = GlanceModifier.fillMaxWidth().cornerRadius(
                    10.dp
                ).background(rgb(status.color)).padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = GlanceModifier.defaultWeight()) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        IndexLabel(type, entry.cyclesIndex, text, color = foreground)
                        Spacer(GlanceModifier.width(4.dp))
                        WidgetLabel(text.name(reading), size = 11.sp, weight = FontWeight.Bold, color = foreground)
                    }
                    WidgetLabel(value, size = 24.sp, weight = FontWeight.Bold, color = foreground)
                }
                Face(status, value, 26.dp)
            }
            Spacer(GlanceModifier.height(2.dp))
            entry.listedFavourites.forEach { FavouriteRow(it, type, text, showsStatus = false) }
            Spacer(GlanceModifier.defaultWeight())
            updated?.let { WidgetLabel(it, size = 9.sp, color = GlanceTheme.colors.onSurfaceVariant) }
        }
    }
}

/** Medium: the station on the left, favourites and the ‹ › pager on the right. */
@Composable
private fun Medium(context: Context, entry: WidgetEntry, reading: Pollutant, updated: String?, text: WidgetText) {
    val type = entry.type
    val status = reading.status(type)
    val value = WidgetFormat.value(reading, type)
    WidgetContainer(
        onClick = WidgetTaps.station(context, reading.stationId),
        background = GlanceTheme.colors.widgetBackground
    ) {
        Row(modifier = GlanceModifier.fillMaxSize()) {
            Column(modifier = GlanceModifier.defaultWeight().fillMaxHeight()) {
                WidgetLabel(text.name(reading), size = 15.sp, weight = FontWeight.Bold)
                Spacer(GlanceModifier.height(2.dp))
                StatusPill(status, text, size = 11.sp)
                updated?.let { SecondaryLabel(it, size = 10.sp) }
                Spacer(GlanceModifier.defaultWeight())
                Row(verticalAlignment = Alignment.CenterVertically, modifier = GlanceModifier.fillMaxWidth()) {
                    IndexLabel(type, entry.cyclesIndex, text)
                    Spacer(GlanceModifier.width(4.dp))
                    WidgetLabel(
                        value,
                        size = 22.sp,
                        weight = FontWeight.Bold,
                        modifier = GlanceModifier.defaultWeight()
                    )
                    Face(status, value, 36.dp)
                }
            }
            Spacer(GlanceModifier.width(10.dp))
            Column(modifier = GlanceModifier.defaultWeight().fillMaxHeight()) {
                if (entry.listedFavourites.isEmpty() && !entry.showsPager) {
                    SecondaryLabel(text.string(R.string.widget_no_favourites), maxLines = 4)
                }
                entry.listedFavourites.forEach { FavouriteRow(it, type, text, showsStatus = false) }
                Spacer(GlanceModifier.defaultWeight())
                if (entry.showsPager) {
                    Box(modifier = GlanceModifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
                        Pager(entry, text)
                    }
                }
            }
        }
    }
}

/** Large: the station with its other indices, the favourites with the pager, and the 空品區 forecast. */
@Composable
private fun Large(
    context: Context,
    entry: WidgetEntry,
    reading: Pollutant,
    updated: String?,
    text: WidgetText,
    snapshot: WidgetSnapshot,
    heightDp: Float
) {
    val type = entry.type
    val status = reading.status(type)
    val value = WidgetFormat.value(reading, type)
    val forecast = snapshot.forecast(reading, text.chinese)
    // The other indices and favourites only as far as they fit above the forecast.
    val fit = WidgetFamilyRules.largeFit(heightDp, forecast != null, entry.listedFavourites.size)
    WidgetContainer(onClick = WidgetTaps.station(context, reading.stationId)) {
        // Glance allows ten children in a Column, so the parts are grouped.
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Column(modifier = GlanceModifier.fillMaxWidth()) {
                Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = GlanceModifier.defaultWeight()) {
                        WidgetLabel(text.name(reading), size = 16.sp, weight = FontWeight.Bold)
                        Spacer(GlanceModifier.height(2.dp))
                        StatusPill(status, text, size = 12.sp)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            IndexLabel(type, entry.cyclesIndex, text)
                            Spacer(GlanceModifier.width(4.dp))
                            WidgetLabel("$value ${type.unit}".trim(), size = 20.sp, weight = FontWeight.Bold)
                        }
                    }
                    Face(status, value, 56.dp)
                }
                updated?.let { SecondaryLabel(it, size = 10.sp) }
                if (fit.showsOtherIndices) {
                    Spacer(GlanceModifier.height(4.dp))
                    OtherIndices(reading, type)
                }
            }
            Spacer(GlanceModifier.height(6.dp))
            Column(modifier = GlanceModifier.fillMaxWidth()) {
                Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Box(modifier = GlanceModifier.defaultWeight()) {
                        SecondaryLabel(text.string(R.string.widget_favourites))
                    }
                    if (entry.showsPager) Pager(entry, text)
                }
                if (entry.listedFavourites.isEmpty()) {
                    SecondaryLabel(text.string(R.string.widget_no_favourites), maxLines = 2)
                } else {
                    entry.listedFavourites.take(fit.favouriteRows).forEach {
                        FavouriteRow(it, type, text, showsStatus = true)
                    }
                }
            }
            Spacer(GlanceModifier.defaultWeight())
            forecast?.let { ForecastSection(it, text, compact = false) }
        }
    }
}

/** The indices other than the one shown, each on its level's tint. */
@Composable
private fun OtherIndices(reading: Pollutant, type: AirIndexType) {
    // Glance allows ten children in a Row: the gaps are each cell's padding, not spacers.
    Row(modifier = GlanceModifier.fillMaxWidth()) {
        WidgetPaging.indexCycle.filter { it != type }.forEach { other ->
            val status = reading.status(other)
            Box(modifier = GlanceModifier.defaultWeight().padding(horizontal = 1.5.dp)) {
                Column(
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        .cornerRadius(6.dp)
                        .background(rgb(status.color, 0.18f))
                        .padding(vertical = 2.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    SecondaryLabel(other.label, size = 9.sp)
                    WidgetLabel(WidgetFormat.value(reading, other), size = 11.sp, weight = FontWeight.Bold)
                }
            }
        }
    }
}

/** Draws [AirQualityWidget], and starts or stops the refresh as widgets are added and removed. */
class AirQualityWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = AirQualityWidget()

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        WidgetReceivers.sync(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        WidgetReceivers.deleted(context, appWidgetIds)
    }
}

internal object WidgetReceivers {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /**
     * A widget was placed (or the phone restarted, or the app updated): fetch once now, so a new
     * large or station detail widget gets its forecast and history without waiting a period, and
     * keep the schedule. Repeated calls replace one another.
     */
    fun sync(context: Context) {
        val app = context.applicationContext
        scope.launch { WidgetUpdater.refreshNow(app) }
    }

    fun deleted(context: Context, appWidgetIds: IntArray) {
        val app = context.applicationContext
        appWidgetIds.forEach { WidgetUpdater.scheduleReset(app, it, null) }
        scope.launch { WidgetUpdater.syncSchedule(app) }
    }
}
