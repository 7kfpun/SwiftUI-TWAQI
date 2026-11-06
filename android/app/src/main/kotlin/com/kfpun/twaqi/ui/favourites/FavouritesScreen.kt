package com.kfpun.twaqi.ui.favourites

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.ui.common.EmptyState
import com.kfpun.twaqi.ui.common.OfflineEmptyState
import com.kfpun.twaqi.ui.common.OfflineNotice
import com.kfpun.twaqi.ui.common.StationRow
import com.kfpun.twaqi.ui.common.StationRowReading
import com.kfpun.twaqi.ui.common.rememberTaiwanPlaceNames

/** The Favourites tab (iOS `FavouriteListView`); [onOpenStation] pushes the station page (`StationRoute`). */
@Composable
fun FavouritesScreen(
    onOpenStation: (Int) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: FavouritesViewModel = viewModel(factory = FavouritesViewModel.Factory)
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    // Like iOS `onAppear`: every time the list shows again, e.g. back from a station.
    LaunchedEffect(Unit) { viewModel.refresh() }
    FavouritesContent(
        state = state,
        onOpenStation = onOpenStation,
        onRetry = viewModel::refresh,
        onRemove = { viewModel.requestRemove(listOf(it)) },
        onMove = viewModel::move,
        onConfirmRemoval = viewModel::confirmRemoval,
        onCancelRemoval = viewModel::cancelRemoval,
        modifier = modifier
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FavouritesContent(
    state: FavouritesUiState,
    onOpenStation: (Int) -> Unit,
    onRetry: () -> Unit,
    onRemove: (Int) -> Unit,
    onMove: (from: Int, to: Int) -> Unit,
    onConfirmRemoval: () -> Unit,
    onCancelRemoval: () -> Unit,
    modifier: Modifier = Modifier
) {
    var editRequested by rememberSaveable { mutableStateOf(false) }
    val canEdit = state.favouriteIds.isNotEmpty() && state.pollutants.isNotEmpty()
    val editing = editRequested && canEdit
    if (editing) BackHandler { editRequested = false }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.favouritelist_favourites)) },
                actions = {
                    if (canEdit) {
                        TextButton(onClick = { editRequested = !editing }) {
                            Text(stringResource(if (editing) R.string.favourites_done else R.string.favourites_edit))
                        }
                    }
                }
            )
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when {
                state.favouriteIds.isEmpty() -> EmptyState(
                    R.drawable.ic_station_heart_outline,
                    stringResource(R.string.favourites_add_your_first_favourite_station)
                )

                // Saved favourites that can't be shown yet: say why, rather than look like none.
                state.pollutants.isEmpty() && state.loadFailed -> OfflineEmptyState(onRetry = onRetry)

                state.pollutants.isEmpty() -> CircularProgressIndicator(
                    Modifier.align(Alignment.TopCenter).padding(top = 64.dp)
                )

                else -> FavouriteList(state, editing, onOpenStation, onRemove, onMove)
            }
        }
    }

    state.pendingRemoval?.let {
        AlertDialog(
            onDismissRequest = onCancelRemoval,
            title = { Text(stringResource(R.string.favourites_remove_station_with_alerts_title)) },
            text = { Text(stringResource(R.string.favourites_remove_station_with_alerts_message)) },
            confirmButton = {
                TextButton(onClick = onConfirmRemoval) {
                    Text(
                        stringResource(R.string.favourites_remove_and_turn_off_alerts),
                        color = MaterialTheme.colorScheme.error
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = onCancelRemoval) { Text(stringResource(R.string.favourites_cancel)) }
            }
        )
    }
}

/** The pollutants that most often set Taiwan's AQI, on each row; the station page has all six. */
private val KEY_POLLUTANTS = listOf(AirIndexType.PM25, AirIndexType.PM10, AirIndexType.O3)

@Composable
private fun FavouriteList(
    state: FavouritesUiState,
    editing: Boolean,
    onOpenStation: (Int) -> Unit,
    onRemove: (Int) -> Unit,
    onMove: (Int, Int) -> Unit
) {
    val chinese = AppLocale.isChinese(LocalContext.current)
    LazyColumn(Modifier.fillMaxSize()) {
        if (state.isShowingLastGood) {
            item(key = "offline") { OfflineNotice(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) }
        }
        itemsIndexed(state.pollutants, key = { _, it -> it.stationId }) { index, pollutant ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .then(if (editing) Modifier else Modifier.clickable { onOpenStation(pollutant.stationId) })
                    .padding(horizontal = if (editing) 4.dp else 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (editing) {
                    IconButton(onClick = { onRemove(pollutant.stationId) }) {
                        Icon(
                            painterResource(R.drawable.ic_station_remove),
                            contentDescription = stringResource(R.string.favourites_remove_from_favourites),
                            tint = MaterialTheme.colorScheme.error
                        )
                    }
                }
                FavouriteRow(pollutant, chinese, state.alertedStationIds, Modifier.weight(1f))
                if (editing) {
                    IconButton(onClick = { onMove(index, index - 1) }, enabled = index > 0) {
                        Icon(
                            painterResource(R.drawable.ic_station_move_up),
                            contentDescription = stringResource(R.string.favourites_move_up)
                        )
                    }
                    IconButton(onClick = { onMove(index, index + 1) }, enabled = index < state.pollutants.lastIndex) {
                        Icon(
                            painterResource(R.drawable.ic_station_move_down),
                            contentDescription = stringResource(R.string.favourites_move_down)
                        )
                    }
                }
            }
            HorizontalDivider(Modifier.padding(start = 16.dp))
        }
    }
}

@Composable
private fun FavouriteRow(pollutant: Pollutant, chinese: Boolean, alerted: Set<Int>, modifier: Modifier) {
    StationRow(
        title = pollutant.displayName(chinese),
        // The official English names, as the station page shows them (FOX-114).
        subtitle = pollutant.displayLocality(chinese, rememberTaiwanPlaceNames()),
        reading = StationRowReading(
            aqi = pollutant.aqi,
            publishTime = pollutant.publishTime,
            pollutants = KEY_POLLUTANTS.map { it to pollutant.value(it) }
        ),
        alertsOn = pollutant.stationId in alerted,
        modifier = modifier
    )
}
