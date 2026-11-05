package com.kfpun.twaqi.ui.debug

import android.text.format.DateUtils
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AppLocale
import com.kfpun.twaqi.data.model.Pollutant
import java.time.Instant

/**
 * Debug builds only: loads stations, readings and the forecast through the data layer and shows
 * whether they came live or from the offline cache. The real screens replace it in later tickets.
 */
@Composable
fun DataDebugScreen(
    modifier: Modifier = Modifier,
    viewModel: DataDebugViewModel = viewModel(factory = DataDebugViewModel.Factory)
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    DataDebugContent(state, onRefresh = viewModel::refresh, modifier = modifier)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DataDebugContent(state: DataDebugUiState, onRefresh: () -> Unit, modifier: Modifier = Modifier) {
    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.debug_data_title)) },
                actions = { TextButton(onClick = onRefresh) { Text(stringResource(R.string.offline_retry)) } }
            )
        }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            if (state.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
            StatusLine(state)
            Text(
                text = stringResource(
                    R.string.debug_data_counts,
                    state.stationCount,
                    state.pollutants.size,
                    state.forecastRowCount
                ),
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
            )
            HorizontalDivider()
            if (state.failed && state.pollutants.isEmpty()) {
                Column(
                    Modifier.fillMaxSize().padding(32.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(stringResource(R.string.offline_nothing_saved), style = MaterialTheme.typography.bodyLarge)
                    Button(onClick = onRefresh, modifier = Modifier.padding(top = 16.dp)) {
                        Text(stringResource(R.string.offline_retry))
                    }
                }
            } else {
                LazyColumn(Modifier.fillMaxSize()) {
                    items(state.pollutants, key = { it.stationId }) { PollutantRow(it) }
                }
            }
        }
    }
}

@Composable
private fun StatusLine(state: DataDebugUiState) {
    val updated = state.updatedAt?.let(::relative)
    val text = when {
        state.stale && updated != null -> stringResource(R.string.offline_updated_ago, updated)
        state.stale -> stringResource(R.string.offline_showing_saved_readings)
        updated != null -> stringResource(R.string.details_last_updated) + " · " + updated
        else -> null
    } ?: return
    Text(
        text = text,
        style = MaterialTheme.typography.titleSmall,
        color = if (state.stale) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
    )
}

@Composable
private fun PollutantRow(pollutant: Pollutant) {
    val chinese = AppLocale.isChinese()
    val status = pollutant.status()
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(48.dp).background(Color(0xFF000000 or status.color.toLong()), RoundedCornerShape(8.dp)),
            contentAlignment = Alignment.Center
        ) {
            Text(
                AirIndexType.AQI.format(pollutant.aqi),
                color = Color(0xFF000000 or status.foregroundColor.toLong()),
                fontWeight = FontWeight.Bold
            )
        }
        Column(Modifier.padding(start = 12.dp).weight(1f)) {
            Text(pollutant.displayName(chinese), style = MaterialTheme.typography.bodyLarge)
            val place = listOfNotNull(
                pollutant.displayArea(chinese),
                pollutant.displayLocality(chinese)
            ).joinToString(" · ")
            if (place.isNotEmpty()) Text(place, style = MaterialTheme.typography.bodySmall)
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(stringResource(status.label), style = MaterialTheme.typography.bodySmall)
            Text(
                "${AirIndexType.PM25.label} ${AirIndexType.PM25.format(pollutant.pm25)}",
                style = MaterialTheme.typography.bodySmall
            )
        }
    }
}

private fun relative(instant: Instant): String = DateUtils.getRelativeTimeSpanString(
    instant.toEpochMilli(),
    System.currentTimeMillis(),
    DateUtils.MINUTE_IN_MILLIS
).toString()
