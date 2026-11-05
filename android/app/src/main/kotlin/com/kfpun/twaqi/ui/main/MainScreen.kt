package com.kfpun.twaqi.ui.main

import android.content.Context
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import com.kfpun.twaqi.R
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.Pollutant

/**
 * The home tab: the map, and in a wide window (a tablet, an unfolded foldable) the station list
 * beside it, its divider on the fold when there is one. The tab host puts the main banner under both.
 */
@Composable
fun MainScreen(
    viewModel: MainViewModel,
    state: MainUiState,
    query: String,
    onQueryChange: (String) -> Unit,
    onOpenStation: (Pollutant) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val foldX = rememberFoldX()
    val density = LocalDensity.current
    var containerLeft by remember { mutableFloatStateOf(0f) }
    Column(modifier.fillMaxSize()) {
        BoxWithConstraints(
            Modifier
                .weight(1f)
                .onGloballyPositioned { containerLeft = with(density) { it.positionInWindow().x.toDp().value } }
        ) {
            if (WideLayout.isWide(maxWidth.value, maxHeight.value)) {
                val listWidth = WideLayout.listWidth(maxWidth.value, containerLeft, foldX)
                Row(Modifier.fillMaxSize()) {
                    StationList(
                        state = state,
                        query = query,
                        onQueryChange = onQueryChange,
                        onOpenStation = onOpenStation,
                        onRetry = viewModel::refresh,
                        onSelectIndex = { selectIndex(context, viewModel, it) },
                        showIndexSelector = false,
                        modifier = Modifier.width(listWidth.dp).fillMaxHeight().statusBarsPadding()
                    )
                    VerticalDivider()
                    MapScreen(viewModel, state, onOpenStation, Modifier.weight(1f))
                }
            } else {
                MapScreen(viewModel, state, onOpenStation)
            }
        }
    }
}

/**
 * The Search tab: the station list on its own, with its own index selector (iOS `DetailsListView`).
 * [onOpenDataScreen] (debug builds only) adds a button to the data-layer check screen (FOX-53).
 */
@Composable
fun StationListScreen(
    viewModel: MainViewModel,
    state: MainUiState,
    query: String,
    onQueryChange: (String) -> Unit,
    onOpenStation: (Pollutant) -> Unit,
    modifier: Modifier = Modifier,
    onOpenDataScreen: (() -> Unit)? = null
) {
    val context = LocalContext.current
    Column(modifier.fillMaxSize()) {
        StationList(
            state = state,
            query = query,
            onQueryChange = onQueryChange,
            onOpenStation = onOpenStation,
            onRetry = viewModel::refresh,
            onSelectIndex = { selectIndex(context, viewModel, it) },
            showIndexSelector = true,
            modifier = Modifier.weight(1f).statusBarsPadding()
        )
        if (onOpenDataScreen != null) {
            TextButton(onClick = onOpenDataScreen, modifier = Modifier.align(Alignment.CenterHorizontally)) {
                Text(stringResource(R.string.debug_data_title))
            }
        }
    }
}

/** Picks the index for the map and the list, and logs `select_index` as iOS does. */
internal fun selectIndex(context: Context, viewModel: MainViewModel, type: AirIndexType) {
    viewModel.selectIndex(type)
    Analytics.logEvent(context, Analytics.SELECT_INDEX, mapOf("label" to type.key))
}

/**
 * x of a fold running down the window, in window dp: a book-style foldable, opened (a fold is only
 * reported while it crosses the window). Null otherwise, and the layout keeps its own split.
 */
@Composable
private fun rememberFoldX(): Float? {
    val activity = LocalActivity.current ?: return null
    val density = LocalDensity.current
    var foldX by remember { mutableStateOf<Float?>(null) }
    LaunchedEffect(activity) {
        WindowInfoTracker.getOrCreate(activity).windowLayoutInfo(activity).collect { info ->
            val fold = info.displayFeatures.filterIsInstance<FoldingFeature>().firstOrNull {
                it.orientation == FoldingFeature.Orientation.VERTICAL
            }
            foldX = fold?.let { with(density) { it.bounds.exactCenterX().toDp().value } }
        }
    }
    return foldX
}
