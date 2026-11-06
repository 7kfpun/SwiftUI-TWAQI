package com.kfpun.twaqi.ui.favourites

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
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
import kotlinx.coroutines.launch

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

/**
 * The rows, with iOS's list gestures: swipe a row to the left to remove it (`onDelete`), touch
 * and hold one and drag it to reorder (`onMove`), in and out of Edit. Edit's buttons stay as the
 * way to do both without gestures, and TalkBack gets the same as custom actions.
 */
@Composable
private fun FavouriteList(
    state: FavouritesUiState,
    editing: Boolean,
    onOpenStation: (Int) -> Unit,
    onRemove: (Int) -> Unit,
    onMove: (Int, Int) -> Unit
) {
    val chinese = AppLocale.isChinese(LocalContext.current)
    val listState = rememberLazyListState()
    val drag = rememberFavouriteDragState(listState)
    val haptics = LocalHapticFeedback.current
    val savedIds = state.pollutants.map { it.stationId }
    // While a row is held, the rows follow the drag; the saved order comes back on drop.
    val byId = state.pollutants.associateBy { it.stationId }
    val shown = drag.order?.mapNotNull { byId[it] } ?: state.pollutants
    val currentIds by rememberUpdatedState(savedIds)
    val currentOnMove by rememberUpdatedState(onMove)

    LazyColumn(Modifier.fillMaxSize(), state = listState) {
        if (state.isShowingLastGood) {
            item(key = "offline") { OfflineNotice(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) }
        }
        itemsIndexed(shown, key = { _, it -> it.stationId }) { index, pollutant ->
            val id = pollutant.stationId
            val held = drag.draggedId == id
            Column(
                Modifier
                    .then(
                        if (held) {
                            Modifier.zIndex(1f).graphicsLayer { translationY = drag.draggedOffset }
                        } else {
                            Modifier.animateItem()
                        }
                    )
                    .pointerInput(id) {
                        detectDragGesturesAfterLongPress(
                            onDragStart = {
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                drag.start(id, currentIds)
                            },
                            onDrag = { change, amount ->
                                change.consume()
                                drag.drag(amount.y)
                            },
                            onDragEnd = { drag.end()?.let { (from, to) -> currentOnMove(from, to) } },
                            onDragCancel = drag::cancel
                        )
                    }
            ) {
                FavouriteItem(
                    pollutant = pollutant,
                    chinese = chinese,
                    alerted = state.alertedStationIds,
                    editing = editing,
                    held = held,
                    swipeEnabled = drag.draggedId == null,
                    canMoveUp = index > 0,
                    canMoveDown = index < shown.lastIndex,
                    // A long press that never moved ends here too; it isn't a tap.
                    onOpen = { if (drag.draggedId == null) onOpenStation(id) },
                    onRemove = { onRemove(id) },
                    onMoveUp = { onMove(index, index - 1) },
                    onMoveDown = { onMove(index, index + 1) }
                )
                if (!held) HorizontalDivider(Modifier.padding(start = 16.dp))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FavouriteItem(
    pollutant: Pollutant,
    chinese: Boolean,
    alerted: Set<Int>,
    editing: Boolean,
    held: Boolean,
    swipeEnabled: Boolean,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onOpen: () -> Unit,
    onRemove: () -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit
) {
    val scope = rememberCoroutineScope()
    val swipe = rememberSwipeToDismissBoxState()
    val removeLabel = stringResource(R.string.favourites_remove_from_favourites)
    val moveUpLabel = stringResource(R.string.favourites_move_up)
    val moveDownLabel = stringResource(R.string.favourites_move_down)

    SwipeToDismissBox(
        state = swipe,
        // Like iOS: only a swipe to the left removes.
        enableDismissFromStartToEnd = false,
        gesturesEnabled = swipeEnabled,
        onDismiss = {
            // Removed at once, or the reader is asked first (alerts on): either way the row
            // slides back, so a cancelled removal leaves it as it was.
            onRemove()
            scope.launch { swipe.reset() }
        },
        backgroundContent = { SwipeRemoveBackground(swipe.dismissDirection == SwipeToDismissBoxValue.EndToStart) }
    ) {
        Surface(
            color = MaterialTheme.colorScheme.surface,
            shadowElevation = if (held) 8.dp else 0.dp,
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .then(if (editing) Modifier else Modifier.clickable(onClick = onOpen))
                    // TalkBack's way to reorder and remove without the gestures or Edit.
                    .semantics {
                        customActions = buildList {
                            if (canMoveUp) {
                                add(
                                    CustomAccessibilityAction(moveUpLabel) {
                                        onMoveUp()
                                        true
                                    }
                                )
                            }
                            if (canMoveDown) {
                                add(
                                    CustomAccessibilityAction(moveDownLabel) {
                                        onMoveDown()
                                        true
                                    }
                                )
                            }
                            add(
                                CustomAccessibilityAction(removeLabel) {
                                    onRemove()
                                    true
                                }
                            )
                        }
                    }
                    .padding(horizontal = if (editing) 4.dp else 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (editing) {
                    IconButton(onClick = onRemove) {
                        Icon(
                            painterResource(R.drawable.ic_station_remove),
                            contentDescription = removeLabel,
                            tint = MaterialTheme.colorScheme.error
                        )
                    }
                }
                FavouriteRow(pollutant, chinese, alerted, Modifier.weight(1f))
                if (editing) {
                    IconButton(onClick = onMoveUp, enabled = canMoveUp) {
                        Icon(painterResource(R.drawable.ic_station_move_up), contentDescription = moveUpLabel)
                    }
                    IconButton(onClick = onMoveDown, enabled = canMoveDown) {
                        Icon(painterResource(R.drawable.ic_station_move_down), contentDescription = moveDownLabel)
                    }
                }
            }
        }
    }
}

/** Behind a row swiped to the left: red, with the remove sign at the trailing edge (iOS's Delete). */
@Composable
private fun SwipeRemoveBackground(active: Boolean) {
    Box(
        Modifier
            .fillMaxSize()
            .background(if (active) MaterialTheme.colorScheme.error else Color.Transparent)
            .padding(horizontal = 24.dp),
        contentAlignment = Alignment.CenterEnd
    ) {
        if (active) {
            Icon(
                painterResource(R.drawable.ic_station_remove),
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onError
            )
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
