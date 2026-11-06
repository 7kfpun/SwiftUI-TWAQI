package com.kfpun.twaqi.ui.station

import androidx.annotation.DrawableRes
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.AqiTrendDirection
import com.kfpun.twaqi.data.model.HistoricalPollutant
import com.kfpun.twaqi.data.model.StationType
import com.kfpun.twaqi.ui.common.LastUpdated
import com.kfpun.twaqi.ui.common.SectionLabel
import com.kfpun.twaqi.ui.common.rgb
import com.kfpun.twaqi.ui.common.secondaryText

/** The face for a band; [AirStatus.UNKNOWN] has none. */
@DrawableRes
fun AirStatus.faceImage(): Int? = when (this) {
    AirStatus.GOOD -> R.drawable.status_good
    AirStatus.MODERATE -> R.drawable.status_moderate
    AirStatus.UNHEALTHY_FOR_SENSITIVE_GROUP -> R.drawable.status_unhealthyforsensitivegroup
    AirStatus.UNHEALTHY -> R.drawable.status_unhealthy
    AirStatus.VERY_UNHEALTHY -> R.drawable.status_veryunhealthy
    AirStatus.HAZARDOUS -> R.drawable.status_hazardous
    AirStatus.UNKNOWN -> null
}

/** Top of the station page: identity, current AQI, and how fresh it is (iOS `StationHeaderView`). */
@Composable
fun StationHeader(
    title: String,
    locality: String?,
    area: String?,
    stationType: StationType,
    aqi: Double,
    publishTime: String?,
    modifier: Modifier = Modifier
) {
    val status = AirStatus.of(AirIndexType.AQI, aqi)
    val hasReading = aqi > 0
    Column(
        modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                title,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.semantics { heading() }
            )
            if (locality != null) {
                Text(
                    locality,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Light,
                    color = secondaryText()
                )
            }
            val meta = listOfNotNull(stationType.label?.let { stringResource(it) }, area)
            if (meta.isNotEmpty()) {
                Text(
                    meta.joinToString("  "),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Light,
                    color = secondaryText(),
                    modifier = Modifier.padding(top = 2.dp)
                )
            }
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            status.faceImage()?.let {
                Image(painterResource(it), contentDescription = null, modifier = Modifier.size(64.dp))
                Spacer(Modifier.width(16.dp))
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(
                        AirIndexType.AQI.label,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Light,
                        color = secondaryText(),
                        modifier = Modifier.padding(bottom = 8.dp)
                    )
                    Text(
                        if (hasReading) aqi.toInt().toString() else "—",
                        fontSize = 40.sp,
                        fontWeight = FontWeight.Thin,
                        modifier = Modifier.padding(start = 6.dp)
                    )
                }
                Text(
                    stringResource(status.label),
                    style = MaterialTheme.typography.bodySmall,
                    color = rgb(status.foregroundColor),
                    modifier = Modifier
                        .background(rgb(status.color), RoundedCornerShape(6.dp))
                        .padding(horizontal = 10.dp, vertical = 3.dp)
                )
            }
        }

        if (publishTime != null) LastUpdated(publishTime)
    }
}

/**
 * The AQI scale with a marker where this reading falls (iOS `AqiScaleView`). The segments are sized
 * in proportion to the bands, so the marker's position is honest.
 */
@Composable
fun AqiScale(aqi: Double, modifier: Modifier = Modifier) {
    val status = AirStatus.of(AirIndexType.AQI, aqi)
    val fraction = (aqi / SCALE_MAX).coerceIn(0.0, 1.0).toFloat()
    val background = MaterialTheme.colorScheme.surface
    Column(modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Canvas(Modifier.fillMaxWidth().height(14.dp).clearAndSetSemantics { }) {
            val gap = 2.dp.toPx()
            val barTop = 4.dp.toPx()
            val barHeight = 6.dp.toPx()
            var lower = 0.0
            SCALE_BANDS.forEach { (upper, band) ->
                val x = (lower / SCALE_MAX * size.width).toFloat()
                val width = ((upper - lower) / SCALE_MAX * size.width).toFloat() - gap
                drawRoundRect(
                    rgb(band.color),
                    topLeft = Offset(x, barTop),
                    size = Size(width.coerceAtLeast(0f), barHeight),
                    cornerRadius = CornerRadius(barHeight / 2)
                )
                lower = upper
            }
            if (aqi > 0) {
                val radius = 7.dp.toPx()
                val center = Offset(size.width * fraction, barTop + barHeight / 2)
                drawCircle(background, radius, center)
                drawCircle(rgb(status.color), radius - 1.5.dp.toPx(), center, style = Stroke(3.dp.toPx()))
            }
        }
        Row(Modifier.fillMaxWidth().clearAndSetSemantics { }) {
            Text(
                "0",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Light,
                color = secondaryText()
            )
            Spacer(Modifier.weight(1f))
            Text(
                "500",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Light,
                color = secondaryText()
            )
        }
    }
}

private const val SCALE_MAX = 500.0
private val SCALE_BANDS = listOf(
    50.0 to AirStatus.GOOD,
    100.0 to AirStatus.MODERATE,
    150.0 to AirStatus.UNHEALTHY_FOR_SENSITIVE_GROUP,
    200.0 to AirStatus.UNHEALTHY,
    300.0 to AirStatus.VERY_UNHEALTHY,
    500.0 to AirStatus.HAZARDOUS
)

/** Advice for the general public and for sensitive groups at this AQI (iOS `HealthGuidanceView`). */
@Composable
fun HealthGuidance(aqi: Double, modifier: Modifier = Modifier) {
    val status = AirStatus.of(AirIndexType.AQI, aqi)
    val general = status.generalPublicGuidance ?: return
    val sensitive = status.sensitiveGroupGuidance ?: return
    Column(modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SectionLabel(stringResource(R.string.details_health_advice))
        Advice(stringResource(R.string.details_general_public), stringResource(general), rgb(status.color))
        Advice(stringResource(R.string.details_sensitive_group), stringResource(sensitive), rgb(status.color))
    }
}

@Composable
private fun Advice(title: String, body: String, color: Color) {
    // A colour rule rather than a boxed chip: it ties the advice to the band without competing
    // with the header's status pill.
    Row(Modifier.height(IntrinsicSize.Min)) {
        Box(Modifier.width(3.dp).fillMaxHeight().background(color, RoundedCornerShape(1.5.dp)))
        Column(Modifier.padding(start = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Medium)
            Text(
                body,
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.Light,
                color = secondaryText()
            )
        }
    }
}

/**
 * The six pollutants, each tappable to drive the 24-hour chart (iOS `PollutantGridView`). Tapping
 * the selected one again returns the chart to AQI. Zero is "—" and not tappable: several stations
 * report 0.0 for what they don't measure.
 */
@Composable
fun PollutantGrid(
    values: (AirIndexType) -> Double,
    selected: AirIndexType,
    onSelect: (AirIndexType) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionLabel(stringResource(R.string.details_pollutants))
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            GRID_ROWS.forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { type ->
                        PollutantCell(
                            type,
                            values(type),
                            isSelected = selected == type,
                            onClick = { onSelect(if (selected == type) AirIndexType.AQI else type) },
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
        }
    }
}

private val GRID_ROWS = listOf(
    listOf(AirIndexType.PM25, AirIndexType.PM10, AirIndexType.O3),
    listOf(AirIndexType.NO2, AirIndexType.SO2, AirIndexType.CO)
)

@Composable
private fun PollutantCell(
    type: AirIndexType,
    value: Double,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier
) {
    val hasReading = value > 0
    val color = rgb(AirStatus.of(type, value).color)
    val shape = RoundedCornerShape(10.dp)
    Surface(
        onClick = onClick,
        enabled = hasReading,
        shape = shape,
        color = if (isSelected) color.copy(alpha = 0.16f) else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f),
        border = if (isSelected) BorderStroke(1.5.dp, color) else null,
        modifier = modifier.semantics { selected = isSelected }
    ) {
        Column(
            Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Text(type.label, style = MaterialTheme.typography.labelMedium, color = secondaryText())
            Row(verticalAlignment = Alignment.Bottom) {
                Text(
                    if (hasReading) type.format(value) else "—",
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Medium,
                    color = if (hasReading) color else secondaryText()
                )
                if (hasReading) {
                    Text(
                        type.unit,
                        style = MaterialTheme.typography.labelSmall,
                        color = secondaryText(),
                        modifier = Modifier.padding(start = 3.dp, bottom = 2.dp)
                    )
                }
            }
        }
    }
}

/**
 * The last 24 hours, answering one question: is it getting better or worse? (iOS
 * `DetailsHistoryView`.) Follows the pollutant tapped in the grid; the info button opens that
 * index's definition.
 */
@Composable
fun HistorySection(
    history: List<HistoricalPollutant>,
    type: AirIndexType,
    onOpenDefinition: (AirIndexType) -> Unit,
    modifier: Modifier = Modifier
) {
    val chart = HistoryChart.of(history, type)
    Column(modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        if (!chart.hasTrend) {
            Text(
                stringResource(R.string.details_no_trend_data),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Light,
                color = secondaryText()
            )
            return@Column
        }
        // Names what the chart shows: without it, tapping a pollutant changes the bars with nothing to say why.
        Row(verticalAlignment = Alignment.CenterVertically) {
            SectionLabel(type.label)
            IconButton(onClick = { onOpenDefinition(type) }, modifier = Modifier.size(32.dp)) {
                Icon(
                    painterResource(R.drawable.ic_station_info),
                    contentDescription = stringResource(R.string.details_about_index, type.label),
                    tint = secondaryText(),
                    modifier = Modifier.size(16.dp)
                )
            }
        }
        TrendHeadline(TrendDisplay.of(chart.values, type))
        Bars(chart, type)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Summary(stringResource(R.string.details_low), chart.lowest, type)
            Summary(stringResource(R.string.details_high), chart.highest, type)
            Summary(stringResource(R.string.details_average), chart.average, type)
        }
    }
}

@Composable
private fun TrendHeadline(trend: TrendDisplay) {
    val tint = trend.tint?.let(::rgb) ?: secondaryText()
    val icon = when (trend.direction) {
        AqiTrendDirection.IMPROVING -> R.drawable.ic_station_trend_improving
        AqiTrendDirection.WORSENING -> R.drawable.ic_station_trend_worsening
        AqiTrendDirection.STEADY -> R.drawable.ic_station_trend_steady
    }
    val detail = when (val d = trend.detail) {
        TrendDisplay.Detail.None -> ""
        is TrendDisplay.Detail.Points -> stringResource(d.format, d.value)
        is TrendDisplay.Detail.Text -> d.text
    }
    Row(verticalAlignment = Alignment.Top) {
        Icon(
            painterResource(icon),
            contentDescription = null,
            tint = tint,
            modifier = Modifier.padding(top = 2.dp).size(20.dp)
        )
        Column(Modifier.padding(start = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(trend.title), style = MaterialTheme.typography.titleMedium, color = tint)
            if (detail.isNotEmpty()) {
                Text(
                    detail,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Light,
                    color = secondaryText()
                )
            }
        }
    }
}

@Composable
private fun Bars(chart: HistoryChart, type: AirIndexType) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Canvas(Modifier.fillMaxWidth().height(72.dp).clearAndSetSemantics { }) {
            val gap = 3.dp.toPx()
            val count = chart.values.size
            val barWidth = ((size.width - gap * (count - 1)) / count).coerceAtLeast(1f)
            chart.values.forEachIndexed { index, value ->
                val height = (chart.barFraction(value) * size.height).toFloat()
                drawRoundRect(
                    rgb(AirStatus.of(type, value).color),
                    topLeft = Offset(index * (barWidth + gap), size.height - height),
                    size = Size(barWidth, height),
                    cornerRadius = CornerRadius(2.5.dp.toPx())
                )
            }
        }
        // Three anchors only: a label per hour is noise.
        Row(Modifier.fillMaxWidth()) {
            AxisLabel(PublishTime.time(chart.times.first()))
            Spacer(Modifier.weight(1f))
            AxisLabel(PublishTime.time(chart.times[chart.times.size / 2]))
            Spacer(Modifier.weight(1f))
            AxisLabel(stringResource(R.string.details_now))
        }
    }
}

@Composable
private fun AxisLabel(text: String) {
    Text(text, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Light, color = secondaryText())
}

@Composable
private fun Summary(label: String, value: Double, type: AirIndexType) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Light,
            color = secondaryText()
        )
        Text(
            type.format(value),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Medium,
            color = rgb(AirStatus.of(type, value).color),
            modifier = Modifier.padding(start = 4.dp)
        )
    }
}

/** The station is listed but has no current reading: retired, or offline for maintenance. */
@Composable
fun NotReporting(modifier: Modifier = Modifier) {
    val title = stringResource(R.string.details_not_reporting)
    val message = stringResource(R.string.details_not_reporting_message)
    Column(
        modifier.fillMaxWidth().padding(horizontal = 32.dp).clearAndSetSemantics {
            contentDescription =
                "$title. $message"
        },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(
            painterResource(R.drawable.ic_station_not_reporting),
            contentDescription = null,
            tint = secondaryText(),
            modifier = Modifier.size(32.dp)
        )
        Text(title, style = MaterialTheme.typography.titleMedium)
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Light,
            color = secondaryText(),
            textAlign = TextAlign.Center
        )
    }
}

/** The thick rule between groups of sections (iOS `Separator().frame(height: 8)`). */
@Composable
fun SectionSeparator() {
    Box(Modifier.fillMaxWidth().height(8.dp).background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f)))
}
