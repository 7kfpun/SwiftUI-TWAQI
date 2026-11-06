package com.kfpun.twaqi.watch.ui

import android.app.RemoteInput
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
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
import androidx.wear.compose.material3.Icon
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.Text
import androidx.wear.input.RemoteInputIntentHelper
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.watch.BuildConfig
import com.kfpun.twaqi.watch.R
import com.kfpun.twaqi.watch.data.WatchPro
import com.kfpun.twaqi.watch.data.WatchReading

private const val SEARCH_KEY = "query"

/**
 * Every station with its current AQI, so the list doubles as an overview (iOS
 * `StationPickerView`), with the phone's favourites first in their level colours (FOX-62).
 */
@Composable
fun StationPickerScreen(model: WatchModel, onDone: () -> Unit) {
    val state by model.state.collectAsStateWithLifecycle()
    var query by rememberSaveable { mutableStateOf("") }
    val listState = rememberScalingLazyListState()
    val searchLabel = stringResource(R.string.detailslist_search)
    val search = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val text = result.data?.let { RemoteInput.getResultsFromIntent(it) }?.getCharSequence(SEARCH_KEY)
        query = text?.toString()?.trim().orEmpty()
    }

    LaunchedEffect(Unit) {
        if (state.stations.isEmpty()) model.loadStations()
        model.loadFavourites()
    }

    val pick = { reading: WatchReading? ->
        model.pin(reading)
        onDone()
    }
    val filtered = filter(state.stations, query)

    ScreenScaffold(scrollState = listState) { padding ->
        ScalingLazyColumn(state = listState, contentPadding = padding, modifier = Modifier.fillMaxSize()) {
            item { ListHeader { Text(stringResource(R.string.watch_stations)) } }
            item {
                Button(
                    onClick = {
                        if (query.isNotEmpty()) {
                            query = ""
                        } else {
                            val intent: Intent = RemoteInputIntentHelper.createActionRemoteInputIntent()
                            RemoteInputIntentHelper.putRemoteInputsExtra(
                                intent,
                                listOf(RemoteInput.Builder(SEARCH_KEY).setLabel(searchLabel).build())
                            )
                            search.launch(intent)
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.filledTonalButtonColors(),
                    icon = { Icon(painterResource(R.drawable.ic_search), contentDescription = null) }
                ) { Text(query.ifEmpty { searchLabel }, maxLines = 1) }
            }

            if (query.isEmpty()) {
                // Home: the closest station, or the 中正 default without a location.
                item { ClosestRow(state, onClick = { pick(null) }) }
                if (state.favourites.isNotEmpty()) {
                    item { ListHeader { Text(stringResource(R.string.favouritelist_favourites)) } }
                    items(state.favourites, key = { "favourite-${it.stationId}" }) { reading ->
                        StationRow(
                            reading,
                            isCurrent = !state.isHome && state.reading?.stationId == reading.stationId
                        ) {
                            pick(reading)
                        }
                    }
                    item { ListHeader { Text(stringResource(R.string.watch_stations)) } }
                }
            }

            items(filtered, key = { it.stationId }) { reading ->
                StationRow(reading, isCurrent = !state.isHome && state.reading?.stationId == reading.stationId) {
                    pick(reading)
                }
            }

            if (state.stations.isEmpty()) {
                item { if (state.failed) Failure(onRetry = model::loadStations) else Spinner() }
            }

            if (query.isEmpty()) {
                if (state.developerMode) item { DeveloperSection(state.proOverride, model::setProOverride) }
                item { Version(onSeventhTap = model::toggleDeveloperMode) }
            }
        }
    }
}

@Composable
private fun ClosestRow(state: WatchUiState, onClick: () -> Unit) {
    val chinese = isChinese()
    Card(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        painterResource(R.drawable.ic_location),
                        contentDescription = null,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(stringResource(R.string.watch_closest))
                }
                // Which station that is right now, on its own line: the watch is too narrow for brackets.
                state.home?.let {
                    Text(it.displayName(chinese), fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (state.isHome) Icon(painterResource(R.drawable.ic_check), contentDescription = null)
        }
    }
}

@Composable
private fun StationRow(reading: WatchReading, isCurrent: Boolean, onClick: () -> Unit) {
    Card(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        StationRowLabel(reading) {
            if (isCurrent) {
                Icon(painterResource(R.drawable.ic_check), contentDescription = null)
            } else {
                Text(reading.formatted(AirIndexType.AQI), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** Tap 7 times to show or hide the developer section, as on the phone. */
@Composable
private fun Version(onSeventhTap: () -> Unit) {
    var taps by rememberSaveable { mutableIntStateOf(0) }
    val haptics = LocalHapticFeedback.current
    Button(
        onClick = {
            taps += 1
            if (taps >= 7) {
                taps = 0
                onSeventhTap()
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            }
        },
        modifier = Modifier.fillMaxWidth(),
        colors = ButtonDefaults.childButtonColors()
    ) {
        Text(
            "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
            modifier = Modifier.fillMaxWidth(),
            textAlign = TextAlign.Center,
            fontSize = 11.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

/**
 * The watch keeps its own Pro override: the phone's doesn't reach it. Debug builds only; elsewhere
 * the section says so, so unlocking it is never a silent no-op. English only, as on iOS.
 */
@Composable
private fun DeveloperSection(current: WatchPro.Override, onSelect: (WatchPro.Override) -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        ListHeader { Text("Developer") }
        if (!WatchPro.overrideAvailable) {
            Text(
                "Pro override is only available in debug builds.",
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            return
        }
        val labels = mapOf(
            WatchPro.Override.PHONE to "Phone",
            WatchPro.Override.FORCE_PRO to "Force Pro",
            WatchPro.Override.FORCE_FREE to "Force Free"
        )
        WatchPro.Override.entries.forEach { option ->
            Card(onClick = { onSelect(option) }, modifier = Modifier.fillMaxWidth()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Pro: ${labels.getValue(option)}", modifier = Modifier.weight(1f))
                    if (option == current) Icon(painterResource(R.drawable.ic_check), contentDescription = null)
                }
            }
        }
    }
}

/** Matches the name in either language, the county and the township, like the phone's search. */
internal fun filter(stations: List<WatchReading>, query: String): List<WatchReading> {
    val needle = query.trim()
    if (needle.isEmpty()) return stations
    return stations.filter { reading ->
        listOfNotNull(reading.name, reading.nameLocal, reading.county, reading.countyLocal, reading.township)
            .any { it.contains(needle, ignoreCase = true) }
    }
}
