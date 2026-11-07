package com.kfpun.twaqi.widget

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.Action
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.kfpun.twaqi.MainActivity
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.AqiForecast
import com.kfpun.twaqi.data.model.AreaForecast
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.model.TaiwanTime
import com.kfpun.twaqi.pro.ProScreenSource
import com.kfpun.twaqi.ui.navigation.DeepLink
import com.kfpun.twaqi.ui.navigation.StationLinkSource
import com.kfpun.twaqi.ui.station.faceImage

/** A fixed `0xRRGGBB` colour, the same in light and dark (band colours). */
internal fun rgb(color: Int): ColorProvider = ColorProvider(Color(0xFF000000.toInt() or color))

internal fun rgb(color: Int, alpha: Float): ColorProvider =
    ColorProvider(Color(0xFF000000.toInt() or color).copy(alpha = alpha))

internal object WidgetTaps {
    /** Locked widgets open the Pro screen, through the one way in (FOX-58, iOS FOX-47). */
    fun pro(context: Context): Action = actionStartActivity(DeepLink.proIntent(context, ProScreenSource.WIDGET_LOCKED))

    /** Medium, large and station detail open the station shown, the page paged to included. */
    fun station(context: Context, stationId: Int): Action =
        actionStartActivity(DeepLink.stationIntent(context, stationId, StationLinkSource.WIDGET))

    fun app(context: Context): Action = actionStartActivity(
        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    )
}

/** The widget's rounded background, and its tap. */
@Composable
internal fun WidgetContainer(
    onClick: Action,
    background: ColorProvider = GlanceTheme.colors.widgetBackground,
    padding: Dp = 12.dp,
    content: @Composable () -> Unit
) {
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .appWidgetBackground()
            .cornerRadius(16.dp)
            .background(background)
            .clickable(onClick)
            .padding(padding),
        contentAlignment = Alignment.TopStart
    ) {
        content()
    }
}

@Composable
internal fun WidgetLabel(
    text: String,
    size: TextUnit = 12.sp,
    weight: FontWeight = FontWeight.Normal,
    color: ColorProvider = GlanceTheme.colors.onSurface,
    maxLines: Int = 1,
    modifier: GlanceModifier = GlanceModifier
) {
    Text(
        text = text,
        style = TextStyle(color = color, fontSize = size, fontWeight = weight),
        maxLines = maxLines,
        modifier = modifier
    )
}

@Composable
internal fun SecondaryLabel(text: String, size: TextUnit = 11.sp, maxLines: Int = 1) {
    WidgetLabel(text, size = size, color = GlanceTheme.colors.onSurfaceVariant, maxLines = maxLines)
}

/**
 * The index's name. Tapping it steps to the next index ([WidgetPaging.indexCycle]), except on a
 * locked widget and on station detail. TalkBack reads it as "Show PM2.5", the index a tap shows.
 */
@Composable
internal fun IndexLabel(
    type: AirIndexType,
    cycles: Boolean,
    text: WidgetText,
    color: ColorProvider = GlanceTheme.colors.onSurface
) {
    val label = @Composable {
        WidgetLabel(type.label, size = 11.sp, weight = FontWeight.Bold, color = color)
    }
    if (cycles) {
        val next = WidgetPaging.nextIndex(type)
        val description = WidgetAccessibility.showIndex(type).resolve(text)
        Box(
            modifier = GlanceModifier
                .cornerRadius(8.dp)
                .background(rgb(0x808080, 0.22f))
                .padding(horizontal = 5.dp, vertical = 1.dp)
                .semantics { contentDescription = description }
                .clickable(
                    actionRunCallback<CycleWidgetIndexAction>(
                        actionParametersOf(CycleWidgetIndexAction.INDEX to next.key)
                    )
                )
        ) { label() }
    } else {
        label()
    }
}

/** The status face, or the value in a tinted circle where a band has none. */
@Composable
internal fun Face(status: AirStatus, value: String, size: Dp) {
    val face = status.faceImage()
    if (face != null) {
        Image(provider = ImageProvider(face), contentDescription = null, modifier = GlanceModifier.size(size))
    } else {
        Box(
            modifier = GlanceModifier.size(size).cornerRadius(size / 2).background(rgb(status.color, 0.2f)),
            contentAlignment = Alignment.Center
        ) { WidgetLabel(value, size = 14.sp, weight = FontWeight.Bold, color = rgb(status.color)) }
    }
}

/** The level in words on its band colour, readable for every band (yellow included). */
@Composable
internal fun StatusPill(status: AirStatus, text: WidgetText, size: TextUnit) {
    Box(
        modifier = GlanceModifier
            .cornerRadius(10.dp)
            .background(rgb(status.color))
            .padding(horizontal = 8.dp, vertical = 1.dp)
    ) {
        WidgetLabel(text.status(status), size = size, weight = FontWeight.Bold, color = rgb(status.foregroundColor))
    }
}

/** A favourite: its name, its level in words on large, and its value on its band colour. */
@Composable
internal fun FavouriteRow(reading: Pollutant, type: AirIndexType, text: WidgetText, showsStatus: Boolean) {
    val status = reading.status(type)
    Row(
        modifier = GlanceModifier.fillMaxWidth().padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = GlanceModifier.defaultWeight()) {
            WidgetLabel(text.name(reading), size = 12.sp, weight = FontWeight.Medium)
            // The band colour is on the value beside it; yellow words would be unreadable on the background.
            if (showsStatus) SecondaryLabel(text.status(status), size = 10.sp)
        }
        Box(
            modifier = GlanceModifier
                .width(44.dp)
                .cornerRadius(9.dp)
                .background(rgb(status.color))
                .padding(vertical = 2.dp),
            contentAlignment = Alignment.Center
        ) {
            WidgetLabel(
                WidgetFormat.value(reading, type),
                size = 12.sp,
                weight = FontWeight.Bold,
                color = rgb(status.foregroundColor)
            )
        }
    }
}

/** ‹ 2 / 5 ›: steps through the widget's station and the favourites, wrapping at both ends. */
@Composable
internal fun Pager(entry: WidgetEntry, text: WidgetText) {
    val count = entry.pageIds.size
    Row(verticalAlignment = Alignment.CenterVertically) {
        PageButton(
            entry,
            step = -1,
            icon = R.drawable.ic_widget_chevron_left,
            label = text.string(R.string.widget_previous_station)
        )
        Spacer(GlanceModifier.width(6.dp))
        // TalkBack reads "Station 2 of 5", not "2 slash 5".
        val position = WidgetAccessibility.pagePosition(entry.page, count).resolve(text)
        WidgetLabel(
            "${entry.page + 1} / $count",
            size = 11.sp,
            color = GlanceTheme.colors.onSurfaceVariant,
            modifier = GlanceModifier.semantics { contentDescription = position }
        )
        Spacer(GlanceModifier.width(6.dp))
        PageButton(
            entry,
            step = 1,
            icon = R.drawable.ic_widget_chevron_right,
            label = text.string(R.string.widget_next_station)
        )
    }
}

@Composable
private fun PageButton(entry: WidgetEntry, step: Int, icon: Int, label: String) {
    val page = WidgetPaging.page(entry.page, step, entry.pageIds.size)
    val target = WidgetPaging.target(page, entry.pageIds) ?: -1
    Box(
        modifier = GlanceModifier
            .size(28.dp)
            .cornerRadius(14.dp)
            .background(rgb(0x808080, 0.22f))
            .clickable(
                actionRunCallback<ShowWidgetPageAction>(
                    actionParametersOf(
                        ShowWidgetPageAction.STATION_ID to target,
                        ShowWidgetPageAction.PAGE_IDS to entry.pageIds.joinToString(",")
                    )
                )
            ),
        contentAlignment = Alignment.Center
    ) {
        Image(
            provider = ImageProvider(icon),
            contentDescription = label,
            colorFilter = ColorFilter.tint(GlanceTheme.colors.onSurface),
            modifier = GlanceModifier.size(18.dp)
        )
    }
}

/** Today and tomorrow for the station's 空品區 (large and station detail). */
@Composable
internal fun ForecastSection(forecast: AreaForecast, text: WidgetText, compact: Boolean) {
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        SecondaryLabel("${text.string(R.string.forecast_title)} · ${forecast.areaTitle}")
        Spacer(GlanceModifier.height(2.dp))
        forecast.days.forEach { day -> ForecastRow(day, text, compact) }
    }
}

@Composable
private fun ForecastRow(day: AqiForecast, text: WidgetText, compact: Boolean) {
    val status = day.status
    Row(
        modifier = GlanceModifier.fillMaxWidth().padding(vertical = 1.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        WidgetLabel(
            dayTitle(day.forecastDate, text),
            size = 12.sp,
            weight = FontWeight.Medium,
            modifier = GlanceModifier.width(64.dp)
        )
        Box(
            modifier = GlanceModifier.width(
                40.dp
            ).cornerRadius(6.dp).background(rgb(status.color)).padding(vertical = 1.dp),
            contentAlignment = Alignment.Center
        ) {
            WidgetLabel(
                day.aqi?.toString() ?: "—",
                size = 12.sp,
                weight = FontWeight.Bold,
                color = rgb(status.foregroundColor)
            )
        }
        if (!compact) {
            Spacer(GlanceModifier.width(6.dp))
            val words = if (status ==
                AirStatus.UNKNOWN
            ) {
                text.string(R.string.forecast_no_value)
            } else {
                text.status(status)
            }
            SecondaryLabel(words)
        }
    }
}

private fun dayTitle(date: String, text: WidgetText): String = when (TaiwanTime.daysFromToday(date)) {
    0 -> text.string(R.string.forecast_today)
    1 -> text.string(R.string.forecast_tomorrow)
    else -> WidgetFormat.day(date)
}

/** A Pro size without Pro: says so, and a tap opens the Pro screen (iOS `proOnly` / `proBanner`). */
@Composable
internal fun LockedPlaceholder(context: Context, reading: Pollutant?, text: WidgetText) {
    WidgetContainer(onClick = WidgetTaps.pro(context)) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Image(
                    provider = ImageProvider(R.drawable.ic_widget_lock),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(GlanceTheme.colors.onSurface),
                    modifier = GlanceModifier.size(18.dp)
                )
                Spacer(GlanceModifier.width(6.dp))
                WidgetLabel(text.string(R.string.widget_pro_only_title), size = 15.sp, weight = FontWeight.Bold)
            }
            Spacer(GlanceModifier.height(4.dp))
            // The station it would show, as a teaser; its numbers stay hidden.
            reading?.let { WidgetLabel(text.name(it), size = 13.sp, weight = FontWeight.Medium) }
            WidgetLabel(
                text.string(R.string.widget_pro_only_body_android),
                size = 12.sp,
                color = GlanceTheme.colors.onSurfaceVariant,
                maxLines = 3
            )
            Spacer(GlanceModifier.defaultWeight())
            Box(
                modifier = GlanceModifier
                    .cornerRadius(12.dp)
                    .background(GlanceTheme.colors.primary)
                    .padding(horizontal = 10.dp, vertical = 4.dp)
            ) {
                WidgetLabel(
                    text.string(R.string.widget_pro_unlock),
                    size = 12.sp,
                    weight = FontWeight.Bold,
                    color = GlanceTheme.colors.onPrimary
                )
            }
        }
    }
}

/** No reading saved yet: open the app once (iOS `empty`). */
@Composable
internal fun EmptyWidget(context: Context, text: WidgetText) {
    WidgetContainer(onClick = WidgetTaps.app(context)) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            WidgetLabel(text.string(R.string.widget_widget_name), size = 15.sp, weight = FontWeight.Bold)
            Spacer(GlanceModifier.height(4.dp))
            WidgetLabel(
                text.string(R.string.watch_no_station),
                size = 12.sp,
                color = GlanceTheme.colors.onSurfaceVariant,
                maxLines = 3
            )
        }
    }
}
