package com.kfpun.twaqi.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.graphics.Bitmap
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
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.RowScope
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
import com.kfpun.twaqi.data.cams.CamFrame
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.ui.station.HistoryChart
import com.kfpun.twaqi.ui.station.TrendDisplay
import com.kfpun.twaqi.ui.station.cam.CamTime
import java.time.Instant
import java.time.OffsetDateTime

/**
 * The station detail widget (iOS extra large, `StationDetailWidgetView`, FOX-72): one station in
 * detail, as much of the station page as fits. Header and every index with wind; the 24-hour trend
 * and the 空品區 forecast; the station cam's last frame (FOX-92); one line of health advice. Where
 * the widget is too short, the advice goes first, then the cam, then the forecast. Pro; locked
 * without it. Nothing here is interactive but the tap, which opens the station.
 */
class StationDetailWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Exact

    override val stateDefinition: GlanceStateDefinition<*> = PreferencesGlanceStateDefinition

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val source = WidgetDataSource(context)
        // Loaded before the first frame, so the widget never draws empty while it reads the caches.
        val initial = source.snapshot(
            WidgetStateKeys.config(getAppWidgetState<Preferences>(context, id)),
            includeHistory = true
        )
        provideContent {
            val prefs = currentState<Preferences>()
            val config = WidgetStateKeys.config(prefs)
            val version = prefs[WidgetStateKeys.VERSION] ?: 0L
            var snapshot by remember { mutableStateOf(initial) }
            LaunchedEffect(config, version) { snapshot = source.snapshot(config, includeHistory = true) }
            val text = remember(version) { WidgetText.of(context) }
            val size = LocalSize.current
            GlanceTheme {
                snapshot.let { loaded ->
                    val entry = WidgetEntry.make(
                        family = WidgetFamily.STATION_DETAIL,
                        leading = loaded.leading,
                        config = config,
                        favouriteIds = loaded.favouriteIds,
                        readings = loaded.readings,
                        isPro = loaded.isPro,
                        state = WidgetPageState(),
                        now = Instant.now()
                    )
                    val reading = entry.reading
                    when {
                        entry.isLocked -> LockedPlaceholder(context, reading, text)

                        reading == null -> EmptyWidget(context, text)

                        else -> DetailContent(
                            context,
                            reading,
                            entry.type,
                            loaded,
                            text,
                            text.updatedLine(
                                reading,
                                prefs[WidgetStateKeys.OFFLINE] == true,
                                loaded.savedAt[reading.stationId]
                            ),
                            size.width.value,
                            size.height.value
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun DetailContent(
    context: Context,
    reading: Pollutant,
    type: AirIndexType,
    snapshot: WidgetSnapshot,
    text: WidgetText,
    updated: String?,
    widthDp: Float,
    heightDp: Float
) {
    val forecast = snapshot.forecast(reading, text.chinese)
    val wide = widthDp >= WIDE_DP
    // The first layout that fits the height, as iOS's ViewThatFits: each drops one more section.
    val shownForecast = forecast?.takeIf { heightDp >= (if (wide) 250f else 360f) }
    // Wide, the cam sits above the forecast beside the trend, so together they need more height.
    val camHeight = if (wide) (if (shownForecast != null) 360f else 330f) else 480f
    val shownCam = snapshot.cam?.takeIf { heightDp >= camHeight }
    val showsAdvice = if (shownCam !=
        null
    ) {
        heightDp >= camHeight + ADVICE_DP
    } else {
        heightDp >= (if (wide) 300f else 420f)
    }
    WidgetContainer(onClick = WidgetTaps.station(context, reading.stationId)) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            if (wide) {
                Row(modifier = GlanceModifier.fillMaxWidth()) {
                    Box(modifier = GlanceModifier.width(150.dp)) { Header(reading, type, text, updated) }
                    Spacer(GlanceModifier.width(10.dp))
                    Box(modifier = GlanceModifier.defaultWeight()) { Indices(reading, type, text) }
                }
            } else {
                Header(reading, type, text, updated)
                Spacer(GlanceModifier.height(6.dp))
                Indices(reading, type, text)
            }
            Spacer(GlanceModifier.height(8.dp))
            if (wide && (shownForecast != null || shownCam != null)) {
                Row(modifier = GlanceModifier.fillMaxWidth()) {
                    Box(modifier = GlanceModifier.defaultWeight()) { Trend(snapshot, type, text) }
                    Spacer(GlanceModifier.width(12.dp))
                    Column(modifier = GlanceModifier.defaultWeight()) {
                        shownCam?.let { Cam(it, text) }
                        if (shownCam != null && shownForecast != null) Spacer(GlanceModifier.height(6.dp))
                        shownForecast?.let { ForecastSection(it, text, compact = true) }
                    }
                }
            } else {
                Trend(snapshot, type, text)
                shownCam?.let {
                    Spacer(GlanceModifier.height(6.dp))
                    Cam(it, text)
                }
                if (shownForecast != null) {
                    Spacer(GlanceModifier.height(6.dp))
                    ForecastSection(shownForecast, text, compact = false)
                }
            }
            if (showsAdvice) {
                Spacer(GlanceModifier.defaultWeight())
                Advice(reading, text)
            }
        }
    }
}

/** Name, county and 空品區, the index big with its face and level, and when it was published. */
@Composable
private fun Header(reading: Pollutant, type: AirIndexType, text: WidgetText, updated: String?) {
    val status = reading.status(type)
    val value = WidgetFormat.value(reading, type)
    Column {
        WidgetLabel(text.name(reading), size = 15.sp, weight = FontWeight.Bold)
        val place = listOfNotNull(
            if (text.chinese) reading.countyLocal else reading.county,
            reading.displayArea(text.chinese)
        ).filter { it.isNotEmpty() }.joinToString(" · ")
        if (place.isNotEmpty()) SecondaryLabel(place)
        Spacer(GlanceModifier.height(4.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Face(status, value, 36.dp)
            Spacer(GlanceModifier.width(8.dp))
            Column {
                SecondaryLabel("${type.label} ${type.unit}".trim(), size = 10.sp)
                WidgetLabel(value, size = 24.sp, weight = FontWeight.Bold)
            }
        }
        Spacer(GlanceModifier.height(3.dp))
        Box(
            modifier = GlanceModifier.cornerRadius(
                10.dp
            ).background(rgb(status.color)).padding(horizontal = 8.dp, vertical = 1.dp)
        ) {
            WidgetLabel(
                text.status(status),
                size = 11.sp,
                weight = FontWeight.Bold,
                color = rgb(status.foregroundColor)
            )
        }
        updated?.let { SecondaryLabel(it, size = 10.sp) }
    }
}

private val indexRows: List<List<AirIndexType?>> = listOf(
    listOf(AirIndexType.AQI, AirIndexType.PM25, AirIndexType.PM10, AirIndexType.O3),
    // null: wind
    listOf(AirIndexType.CO, AirIndexType.SO2, AirIndexType.NO2, null)
)

/** Every index and the wind, two rows of four; the widget's own index is outlined in its colour. */
@Composable
private fun Indices(reading: Pollutant, type: AirIndexType, text: WidgetText) {
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        SecondaryLabel(text.string(R.string.details_pollutants), size = 10.sp)
        indexRows.forEachIndexed { rowIndex, row ->
            if (rowIndex > 0) Spacer(GlanceModifier.height(3.dp))
            Row(modifier = GlanceModifier.fillMaxWidth()) {
                row.forEachIndexed { position, index ->
                    if (position > 0) Spacer(GlanceModifier.width(3.dp))
                    Box(modifier = GlanceModifier.defaultWeight()) {
                        if (index != null) IndexCell(reading, index, index == type) else WindCell(reading, text)
                    }
                }
            }
        }
    }
}

@Composable
private fun IndexCell(reading: Pollutant, index: AirIndexType, chosen: Boolean) {
    val hasReading = reading.value(index) > 0
    val status = reading.status(index)
    val background = if (chosen && hasReading) rgb(status.color, 0.22f) else rgb(0x808080, 0.12f)
    Column(
        modifier = GlanceModifier.fillMaxWidth().cornerRadius(
            6.dp
        ).background(background).padding(horizontal = 5.dp, vertical = 3.dp)
    ) {
        WidgetLabel(index.label, size = 10.sp, weight = FontWeight.Bold)
        WidgetLabel(
            WidgetFormat.value(reading, index),
            size = 13.sp,
            weight = FontWeight.Bold,
            color = if (hasReading) rgb(status.color) else GlanceTheme.colors.onSurfaceVariant
        )
    }
}

@Composable
private fun WindCell(reading: Pollutant, text: WidgetText) {
    val calm = reading.windSpeed < WidgetFormat.CALM_WIND
    Column(
        modifier = GlanceModifier.fillMaxWidth().cornerRadius(
            6.dp
        ).background(rgb(0x808080, 0.12f)).padding(horizontal = 5.dp, vertical = 3.dp)
    ) {
        // The cell is a quarter of half the widget: room for the speed in m/s only ("風速", not "風向風速").
        WidgetLabel(text.string(R.string.widget_wind_speed), size = 10.sp, weight = FontWeight.Bold)
        val speed = if (calm) {
            text.string(R.string.wind_calm)
        } else {
            String.format(java.util.Locale.US, "%.1f", reading.windSpeed)
        }
        WidgetLabel(speed, size = 12.sp, weight = FontWeight.Bold)
    }
}

/** The index over the last 24 hours, and which way it is going (iOS `trend`). */
@Composable
private fun Trend(snapshot: WidgetSnapshot, type: AirIndexType, text: WidgetText) {
    val chart = HistoryChart.of(snapshot.history, type)
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        SecondaryLabel("${type.label} · 24h", size = 10.sp)
        if (!chart.hasTrend) {
            SecondaryLabel(text.string(R.string.details_no_trend_data), size = 11.sp, maxLines = 2)
            return@Column
        }
        val verdict = TrendDisplay.of(chart.values, type)
        WidgetLabel(
            text.string(verdict.title),
            size = 13.sp,
            weight = FontWeight.Bold,
            color = verdict.tint?.let { rgb(it) } ?: GlanceTheme.colors.onSurfaceVariant
        )
        when (val detail = verdict.detail) {
            is TrendDisplay.Detail.Points -> SecondaryLabel(text.string(detail.format, detail.value), size = 10.sp)
            is TrendDisplay.Detail.Text -> SecondaryLabel(detail.text, size = 10.sp)
            TrendDisplay.Detail.None -> Unit
        }
        Spacer(GlanceModifier.height(3.dp))
        Bars(chart, type)
        Row(modifier = GlanceModifier.fillMaxWidth()) {
            val first = snapshot.history.takeLast(HistoryChart.MAX_POINTS).firstOrNull()?.publishedAt
            Box(modifier = GlanceModifier.defaultWeight()) {
                first?.let { SecondaryLabel(WidgetFormat.hour(it), size = 9.sp) }
            }
            SecondaryLabel(text.string(R.string.details_now), size = 9.sp)
        }
    }
}

/**
 * Bars in each hour's band colour, scaled to the day's own range as on the station page. Glance
 * allows ten children in a Row, so the bars sit in groups of [BARS_PER_GROUP], with each bar's
 * padding as the gap.
 */
@Composable
private fun Bars(chart: HistoryChart, type: AirIndexType) {
    Row(modifier = GlanceModifier.fillMaxWidth().height(BARS_HEIGHT.dp), verticalAlignment = Alignment.Bottom) {
        chart.values.chunked(BARS_PER_GROUP).forEach { group ->
            Row(
                modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
                verticalAlignment = Alignment.Bottom
            ) {
                group.forEach { value -> Bar(value, chart, type) }
            }
        }
        // A short history keeps its bars as wide as a full day's.
        repeat(MAX_GROUPS - (chart.values.size + BARS_PER_GROUP - 1) / BARS_PER_GROUP) {
            Spacer(GlanceModifier.defaultWeight())
        }
    }
}

@Composable
private fun RowScope.Bar(value: Double, chart: HistoryChart, type: AirIndexType) {
    val height = (BARS_HEIGHT * chart.barFraction(value)).toFloat().coerceAtLeast(3f)
    Box(modifier = GlanceModifier.defaultWeight().padding(horizontal = 1.dp)) {
        Box(
            modifier = GlanceModifier
                .fillMaxWidth()
                .height(height.dp)
                .cornerRadius(2.dp)
                .background(rgb(AirStatus.of(type, value).color))
        ) {}
    }
}

/** The cam's last frame, 16:9, with when it was captured on it (iOS `camSection`). */
@Composable
private fun Cam(frame: CamFrame<Bitmap>, text: WidgetText) {
    val captured = frame.time?.let { runCatching { OffsetDateTime.parse(it).toInstant() }.getOrNull() }
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        SecondaryLabel(text.string(R.string.details_live_cam), size = 10.sp)
        Spacer(GlanceModifier.height(2.dp))
        Box(
            modifier = GlanceModifier.fillMaxWidth().height(CAM_HEIGHT_DP.dp).cornerRadius(8.dp),
            contentAlignment = Alignment.BottomStart
        ) {
            Image(
                provider = ImageProvider(frame.image),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = GlanceModifier.fillMaxSize().cornerRadius(8.dp)
            )
            if (captured != null) {
                Box(modifier = GlanceModifier.padding(5.dp)) {
                    Box(
                        modifier = GlanceModifier
                            .cornerRadius(8.dp)
                            .background(rgb(0x000000, 0.45f))
                            .padding(horizontal = 5.dp, vertical = 2.dp)
                    ) {
                        WidgetLabel(
                            text.string(R.string.details_cam_captured, CamTime.clock(captured)),
                            size = 9.sp,
                            weight = FontWeight.Medium,
                            color = rgb(0xFFFFFF)
                        )
                    }
                }
            }
        }
    }
}

/** The general-public line of the station page's health advice, for AQI. */
@Composable
private fun Advice(reading: Pollutant, text: WidgetText) {
    val status = reading.status(AirIndexType.AQI)
    val guidance = status.generalPublicGuidance ?: return
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(modifier = GlanceModifier.width(3.dp).height(12.dp).background(rgb(status.color))) {}
        Spacer(GlanceModifier.width(6.dp))
        WidgetLabel(text.string(R.string.details_health_advice), size = 11.sp, weight = FontWeight.Bold)
        Spacer(GlanceModifier.width(4.dp))
        SecondaryLabel(text.string(guidance), size = 11.sp)
    }
}

private const val WIDE_DP = 300f
private const val BARS_HEIGHT = 30

/** The cam frame's height, 16:9 at about the half-width it gets on a 4-column widget. */
private const val CAM_HEIGHT_DP = 90

/** The advice line and the gap above it, for the height check. */
private const val ADVICE_DP = 22f

private const val BARS_PER_GROUP = 3
private val MAX_GROUPS = (HistoryChart.MAX_POINTS + BARS_PER_GROUP - 1) / BARS_PER_GROUP

/** Draws [StationDetailWidget], and starts or stops the refresh as widgets are added and removed. */
class StationDetailWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = StationDetailWidget()

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        WidgetReceivers.sync(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        WidgetReceivers.deleted(context, appWidgetIds)
    }
}
