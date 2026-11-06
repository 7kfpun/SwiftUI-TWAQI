package com.kfpun.twaqi.ui.main

import android.content.Context
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.kfpun.twaqi.R
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.ui.adaptive.HingeLayout
import com.kfpun.twaqi.ui.adaptive.rememberWindowHinge

/**
 * The home tab: the map, and in a wide window (a tablet, an unfolded foldable) the open station's
 * page in a [panel] at its trailing edge, the divider on the fold when there is one (iOS `MainView`,
 * FOX-119). On a phone [panel] is null and the station covers the tabs instead. The tab host puts the
 * main banner under both.
 */
@Composable
fun MainScreen(
    viewModel: MainViewModel,
    state: MainUiState,
    onOpenStation: (Pollutant) -> Unit,
    modifier: Modifier = Modifier,
    panel: (@Composable (Modifier) -> Unit)? = null
) {
    val hinge = rememberWindowHinge()
    val density = LocalDensity.current
    // Window dp; the hinge comes in window coordinates.
    var bounds by remember { mutableStateOf(Rect.Zero) }
    Column(modifier.fillMaxSize()) {
        BoxWithConstraints(
            Modifier
                .weight(1f)
                .onGloballyPositioned { coordinates ->
                    bounds = with(density) {
                        val box = coordinates.boundsInWindow()
                        Rect(
                            box.left.toDp().value,
                            box.top.toDp().value,
                            box.right.toDp().value,
                            box.bottom.toDp().value
                        )
                    }
                }
        ) {
            val width = maxWidth.value
            val foldX = hinge?.takeIf { it.vertical }?.let { (it.left + it.right) / 2 }
            val panelWidth = panel?.let { WideLayout.panelWidth(width, bounds.left, foldX) }
            val mapWidth = width - (panelWidth ?: 0f)
            // Nothing a finger has to hit across a half-open hinge: in the book posture the map's
            // controls keep to one side of it, in the tabletop posture the map takes the top half.
            val hingeInsets = HingeLayout.insets(
                hinge,
                bounds.left,
                bounds.top,
                mapWidth,
                maxHeight.value,
                splitTabletop = true
            )
            Row(Modifier.fillMaxSize()) {
                // The map stays at one place in the tree, so its camera survives the panel opening.
                MapScreen(viewModel, state, onOpenStation, Modifier.weight(1f), hingeInsets)
                if (panel != null && panelWidth != null) {
                    VerticalDivider()
                    panel(Modifier.width(panelWidth.dp).fillMaxHeight())
                }
            }
        }
    }
}

/**
 * The Search tab: the station list on its own, with its own index selector (iOS `DetailsListView`).
 * [onOpenDataScreen] (debug builds only) adds a button to the data-layer check screen (FOX-53).
 * [listState] is held by the tab, so the scroll position survives the move to and from the wide
 * layout (FOX-119).
 */
@Composable
fun StationListScreen(
    viewModel: MainViewModel,
    state: MainUiState,
    query: String,
    onQueryChange: (String) -> Unit,
    onOpenStation: (Pollutant) -> Unit,
    modifier: Modifier = Modifier,
    onOpenDataScreen: (() -> Unit)? = null,
    listState: LazyListState = rememberLazyListState()
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
            modifier = Modifier.weight(1f).statusBarsPadding(),
            listState = listState
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
