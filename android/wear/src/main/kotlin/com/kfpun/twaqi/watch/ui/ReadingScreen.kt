package com.kfpun.twaqi.watch.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
import androidx.wear.compose.material3.Card
import androidx.wear.compose.material3.CardDefaults
import androidx.wear.compose.material3.CircularProgressIndicator
import androidx.wear.compose.material3.FilledTonalButton
import androidx.wear.compose.material3.Icon
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.Text
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.watch.R
import com.kfpun.twaqi.watch.complication.faceDrawable
import com.kfpun.twaqi.watch.complication.statusLabel
import com.kfpun.twaqi.watch.data.WatchReading
import com.kfpun.twaqi.watch.data.Wind

private val POLLUTANTS = listOf(
    AirIndexType.PM25,
    AirIndexType.PM10,
    AirIndexType.O3,
    AirIndexType.CO,
    AirIndexType.SO2,
    AirIndexType.NO2
)

/**
 * The station's reading (iOS `ReadingView`): AQI first, then the past 12 hours of whichever index
 * is selected, the pollutants behind it, and the Pro row last so it never pushes a reading off.
 */
@Composable
fun ReadingScreen(model: WatchModel, onOpenPicker: () -> Unit, onOpenPaywall: () -> Unit) {
    val state by model.state.collectAsStateWithLifecycle()
    // Drives the history chart; local to this screen, as on the phone's station page.
    var selected by rememberSaveable { mutableStateOf(AirIndexType.AQI) }
    val listState = rememberScalingLazyListState()
    val chinese = isChinese()

    // A new station starts at its headline reading, not wherever the last one was scrolled to.
    LaunchedEffect(state.reading?.stationId) { listState.scrollToItem(0) }

    ScreenScaffold(scrollState = listState) { padding ->
        ScalingLazyColumn(state = listState, contentPadding = padding, modifier = Modifier.fillMaxSize()) {
            item {
                ListHeader {
                    Text(state.reading?.displayName(chinese).orEmpty(), maxLines = 1, textAlign = TextAlign.Center)
                }
            }
            val reading = state.reading
            when {
                reading != null -> {
                    item {
                        Summary(reading, state.source, selected == AirIndexType.AQI) { selected = AirIndexType.AQI }
                    }
                    item { StationsButton(onOpenPicker) }
                    item { ListHeader { Text(stringResource(R.string.watch_history)) } }
                    item { History(state, selected) }
                    items(POLLUTANTS) { type ->
                        PollutantRow(type, reading, selected == type) { selected = type }
                    }
                    // The app and the face complication are free; the number and the other styles are Pro.
                    if (!state.isPro) {
                        item {
                            FilledTonalButton(
                                onClick = onOpenPaywall,
                                modifier = Modifier.fillMaxWidth(),
                                icon = { Icon(painterResource(R.drawable.ic_pro_watch), contentDescription = null) }
                            ) { Text(stringResource(R.string.watch_pro_complications_cta)) }
                        }
                    }
                }

                state.failed -> {
                    item { Failure(onRetry = model::refresh) }
                    item { StationsButton(onOpenPicker) }
                }

                else -> item { Spinner() }
            }
        }
    }
}

@Composable
private fun StationsButton(onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = ButtonDefaults.filledTonalButtonColors(),
        icon = { Icon(painterResource(R.drawable.ic_list), contentDescription = null) }
    ) { Text(stringResource(R.string.watch_stations)) }
}

@Composable
private fun Summary(reading: WatchReading, source: StationSource, isSelected: Boolean, onClick: () -> Unit) {
    val level = reading.level()
    val tint = level.composeColor()
    Card(onClick = onClick, modifier = Modifier.fillMaxWidth(), colors = selectionColors(isSelected)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            AqiGauge(reading)
            Spacer(Modifier.width(10.dp))
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                // The same faces as the phone, so a glance reads the mood before the words.
                Row(verticalAlignment = Alignment.CenterVertically) {
                    faceDrawable(level)?.let {
                        Image(painterResource(it), contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(4.dp))
                    }
                    Text(
                        stringResource(statusLabel(level)),
                        color = tint,
                        fontWeight = FontWeight.Bold,
                        fontSize = 14.sp
                    )
                }
                if (reading.publishTime.isNotEmpty()) {
                    Text(
                        WatchReading.hourMinute(reading.publishTime),
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                WindLine(reading.wind)
            }
        }
        SourceLabel(source)
    }
}

/** Says why this station, when it wasn't picked by hand. */
@Composable
private fun SourceLabel(source: StationSource) {
    val (icon, text) = when (source) {
        StationSource.PINNED -> return
        StationSource.CLOSEST -> R.drawable.ic_location to R.string.watch_closest
        StationSource.FALLBACK -> R.drawable.ic_home to R.string.watch_default_station
    }
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
        Icon(
            painterResource(icon),
            contentDescription = null,
            modifier = Modifier.size(12.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.width(4.dp))
        Text(stringResource(text), fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Which way the air is moving sits with the AQI. */
@Composable
private fun WindLine(wind: Wind) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        if (wind.isCalm) {
            Text(stringResource(R.string.wind_calm), fontSize = 12.sp)
        } else {
            // Drawn pointing south, so the bearing the wind comes from leaves it pointing downwind.
            Icon(
                painterResource(R.drawable.ic_arrow_down),
                contentDescription = null,
                modifier = Modifier.size(12.dp).rotate(wind.direction.toFloat())
            )
            Spacer(Modifier.width(2.dp))
            Text("${wind.compassPoint} ${String.format(java.util.Locale.US, "%.1f", wind.speed)} m/s", fontSize = 12.sp)
        }
    }
}

@Composable
private fun History(state: WatchUiState, type: AirIndexType) {
    if (state.history.size < 2) {
        // A same-station refresh keeps the old bars; only an empty chart waits on a spinner.
        Box(Modifier.fillMaxWidth().heightIn(min = 60.dp), contentAlignment = Alignment.Center) {
            if (state.isLoading || state.isLoadingHistory) {
                CircularProgressIndicator(Modifier.size(24.dp))
            } else {
                Text(
                    stringResource(R.string.details_no_trend_data),
                    fontSize = 12.sp,
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        return
    }
    // Inset from the round edge, which would clip the first and last bars.
    Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp)) {
        Text("${type.label} ${type.unit}".trim(), fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        HistoryBars(state.history, type, Modifier.padding(vertical = 4.dp))
        Row(Modifier.fillMaxWidth()) {
            Text(
                WatchReading.hourMinute(state.history.first().publishTime),
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.weight(1f))
            Text(
                WatchReading.hourMinute(state.history.last().publishTime),
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun PollutantRow(type: AirIndexType, reading: WatchReading, isSelected: Boolean, onClick: () -> Unit) {
    Card(onClick = onClick, modifier = Modifier.fillMaxWidth(), colors = selectionColors(isSelected)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            LevelDot(reading.level(type))
            Spacer(Modifier.width(8.dp))
            Text(type.label)
            Spacer(Modifier.weight(1f))
            Text(reading.formatted(type))
            Spacer(Modifier.width(4.dp))
            Text(type.unit, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Marks the row the chart is showing. */
@Composable
private fun selectionColors(isSelected: Boolean) = if (isSelected) {
    CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.22f))
} else {
    CardDefaults.cardColors()
}

@Composable
fun Failure(onRetry: () -> Unit) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(stringResource(R.string.watch_loading_failed), textAlign = TextAlign.Center)
        Spacer(Modifier.size(8.dp))
        Button(onClick = onRetry) { Text(stringResource(R.string.watch_retry)) }
    }
}

@Composable
fun Spinner() {
    Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
        CircularProgressIndicator(Modifier.size(32.dp))
    }
}
