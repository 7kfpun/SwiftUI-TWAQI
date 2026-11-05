package com.kfpun.twaqi.watch.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material3.ColorScheme
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.Text
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirLevel
import com.kfpun.twaqi.watch.data.HistoryPoint
import com.kfpun.twaqi.watch.data.WatchLocale
import com.kfpun.twaqi.watch.data.WatchReading

/** The level's colour, as on the phone. */
fun AirLevel.composeColor(): Color = Color(0xFF000000 or color.toLong())

/** The app's dark watch theme, with the "Good" green as its accent. */
@Composable
fun WatchTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = ColorScheme(primary = AirLevel.GOOD.composeColor(), onPrimary = Color.White),
        content = content
    )
}

@Composable
fun isChinese(): Boolean = WatchLocale.isChinese(LocalContext.current)

/** A small dot in the level's colour, as the phone's lists. */
@Composable
fun LevelDot(level: AirLevel, size: Dp = 8.dp) {
    Canvas(Modifier.size(size)) { drawCircle(level.composeColor()) }
}

/**
 * The AQI on a 0–500 arc in its level's colour (iOS `Gauge` `.accessoryCircular`), the number in
 * the middle and "AQI" under it.
 */
@Composable
fun AqiGauge(reading: WatchReading, size: Dp = 56.dp) {
    val level = reading.level()
    val colour = level.composeColor()
    val fraction = (reading.aqi.coerceIn(0.0, MAX_AQI) / MAX_AQI).toFloat()
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(size)) {
            val stroke = 5.dp.toPx()
            val inset = stroke / 2
            val arcSize = Size(this.size.width - stroke, this.size.height - stroke)
            drawArc(
                colour.copy(alpha = 0.25f),
                135f,
                270f,
                false,
                Offset(inset, inset),
                arcSize,
                style = Stroke(stroke, cap = StrokeCap.Round)
            )
            drawArc(
                colour,
                135f,
                270f * fraction,
                false,
                Offset(inset, inset),
                arcSize,
                style = Stroke(stroke, cap = StrokeCap.Round)
            )
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(reading.formatted(AirIndexType.AQI), fontSize = 18.sp, fontWeight = FontWeight.Bold)
            Text(AirIndexType.AQI.label, fontSize = 9.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Hourly bars in each hour's level colour, oldest left (iOS `Chart` of `BarMark`s). */
@Composable
fun HistoryBars(points: List<HistoryPoint>, type: AirIndexType, modifier: Modifier = Modifier) {
    val values = points.map { it.value(type) }
    val top = (values.maxOrNull() ?: 0.0).takeIf { it > 0 } ?: 1.0
    Canvas(modifier.fillMaxWidth().height(60.dp)) {
        val gap = 2.dp.toPx()
        val width = (size.width - gap * (values.size - 1)) / values.size.coerceAtLeast(1)
        values.forEachIndexed { index, value ->
            val height = (value / top).toFloat() * size.height
            drawRoundRect(
                color = AirLevel.of(type, value).composeColor(),
                topLeft = Offset(index * (width + gap), size.height - height),
                size = Size(width, height),
                cornerRadius = CornerRadius(2.dp.toPx())
            )
        }
    }
}

/** A row of the station list: level dot, name with its county, AQI on the right. */
@Composable
fun StationRowLabel(reading: WatchReading, trailing: @Composable () -> Unit) {
    val chinese = isChinese()
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        LevelDot(reading.level())
        Column(Modifier.weight(1f).padding(start = 8.dp)) {
            Text(reading.displayName(chinese), maxLines = 1)
            reading.locality(chinese)?.let {
                Text(it, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            }
        }
        trailing()
    }
}

private const val MAX_AQI = 500.0
