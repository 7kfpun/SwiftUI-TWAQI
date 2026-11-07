package com.kfpun.twaqi.ui

import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.currentWindowDpSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.kfpun.twaqi.R
import com.kfpun.twaqi.ads.AdBanner
import com.kfpun.twaqi.ads.AdPlacement
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.ui.adaptive.HingeLayout
import com.kfpun.twaqi.ui.adaptive.ListDetailLayout
import com.kfpun.twaqi.ui.adaptive.SelectionPlaceholder
import com.kfpun.twaqi.ui.adaptive.offHinge
import com.kfpun.twaqi.ui.adaptive.rememberWindowHinge
import com.kfpun.twaqi.ui.favourites.FavouritesScreen
import com.kfpun.twaqi.ui.forecast.ForecastScreen
import com.kfpun.twaqi.ui.help.HelpHost
import com.kfpun.twaqi.ui.main.MainScreen
import com.kfpun.twaqi.ui.main.MainViewModel
import com.kfpun.twaqi.ui.main.StationListScreen
import com.kfpun.twaqi.ui.navigation.StationRoute
import kotlinx.coroutines.delay

/**
 * The app's tabs (iOS `ContentView`). The map (FOX-54) is home, Favourites is FOX-55's, the
 * station list is Search, Help is FOX-97's, and Forecast (FOX-90) sits second, as iOS FOX-32 put it.
 * [adPlacement] is null where iOS shows no banner (the Forecast tab).
 */
enum class MainTab(@param:StringRes val label: Int, @param:DrawableRes val icon: Int, val adPlacement: AdPlacement?) {
    MAIN(R.string.tabbar_main, R.drawable.ic_tab_home, AdPlacement.MAIN),
    FORECAST(R.string.tabbar_forecast, R.drawable.ic_tab_forecast, null),
    FAVOURITES(R.string.tabbar_favourites, R.drawable.ic_tab_favourites, AdPlacement.FAVOURITES),
    DETAILS_LIST(R.string.tabbar_details_list, R.drawable.ic_tab_list, AdPlacement.DETAILS_LIST),
    HELP(R.string.tabbar_help, R.drawable.ic_tab_help, AdPlacement.HELP)
}

/**
 * @param isPro from the Pro entitlement (FOX-58); hides Help's Premium section.
 * @param onOpenPro opens the Pro screen (FOX-58).
 * @param onOpenStation a station tapped on the map, its card or the list (FOX-54).
 * @param onShowWelcomeGuide Help's "Show welcome guide" (FOX-96).
 * @param onOpenDataScreen debug builds only: a button on the Search tab to the data-layer check (FOX-53).
 * @param selected the tab shown, held by [com.kfpun.twaqi.ui.navigation.HomeNavigationViewModel] (FOX-119).
 * @param panes in a wide window, the station beside the map and the lists (FOX-119); null on phones.
 */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
fun MainTabs(
    isPro: Boolean,
    onOpenPro: () -> Unit,
    onOpenStation: (StationRoute) -> Unit,
    selected: MainTab,
    onSelect: (MainTab) -> Unit,
    modifier: Modifier = Modifier,
    onOpenDataScreen: (() -> Unit)? = null,
    onShowWelcomeGuide: () -> Unit = {},
    panes: StationPanes? = null
) {
    var query by rememberSaveable { mutableStateOf("") }
    // Each tab keeps its own state (Help's open page) while another tab is shown, as on iOS.
    val tabStates = rememberSaveableStateHolder()
    val viewModel: MainViewModel = viewModel(factory = MainViewModel.Factory)
    val state by viewModel.uiState.collectAsStateWithLifecycle()

    // Back in the foreground, possibly back online: retry what failed; refresh every 15 minutes.
    val lifecycleOwner = LocalLifecycleOwner.current
    LaunchedEffect(lifecycleOwner) {
        lifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (true) {
                viewModel.refreshIfNeeded()
                delay(MainViewModel.REFRESH_INTERVAL.toMillis())
            }
        }
    }

    val openStation = { pollutant: Pollutant -> onOpenStation(StationRoute(pollutant.stationId)) }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        // Each tab's own top bar takes the status bar (the map draws under it); the navigation bar
        // takes the bottom.
        contentWindowInsets = WindowInsets(0),
        bottomBar = {
            NavigationBar {
                val tabItem: @Composable RowScope.(MainTab) -> Unit = { tab ->
                    NavigationBarItem(
                        selected = tab == selected,
                        onClick = { onSelect(tab) },
                        icon = { Icon(painterResource(tab.icon), contentDescription = null) },
                        // One line at any font scale (FOX-113): "Favourites" wrapped to "Favourite" / "s" at 1.3.
                        label = { Text(stringResource(tab.label), maxLines = 1, overflow = TextOverflow.Ellipsis) }
                    )
                }
                // FOX-119: on a half-open book-style foldable no tab sits across the hinge.
                val hinge = rememberWindowHinge()
                val windowWidth = currentWindowDpSize().width.value
                val split = HingeLayout.tabsBeforeHinge(MainTab.entries.size, windowWidth, hinge)
                if (split == null || hinge == null) {
                    MainTab.entries.forEach { tabItem(it) }
                } else {
                    Row(Modifier.width(hinge.left.dp)) { MainTab.entries.take(split).forEach { tabItem(it) } }
                    Spacer(Modifier.width((hinge.right - hinge.left).dp))
                    Row(Modifier.weight(1f)) { MainTab.entries.drop(split).forEach { tabItem(it) } }
                }
            }
        }
    ) { innerPadding ->
        // Each tab's banner sits above the tab bar (iOS: the footer banner of each tab), hidden for Pro.
        Column(Modifier.fillMaxSize().padding(innerPadding).consumeWindowInsets(innerPadding)) {
            val content = Modifier.weight(1f).fillMaxWidth()
            // FOX-119: in the tabletop posture the lists, Help and Forecast keep above the hinge. In a
            // wide window the list-detail scaffold already splits on a book-style hinge.
            val pageContent = content.offHinge(book = panes == null)
            tabStates.SaveableStateProvider(selected.name) {
                // FOX-119: each list's scroll position is held here, above the phone/wide switch, so
                // it survives folding, unfolding and resizing.
                val listState = rememberLazyListState()
                when (selected) {
                    MainTab.MAIN -> MainScreen(
                        viewModel,
                        state,
                        openStation,
                        content,
                        panel = panes?.panel(MainTab.MAIN)
                    )

                    MainTab.DETAILS_LIST -> panes.listDetail(MainTab.DETAILS_LIST, pageContent) { listModifier ->
                        StationListScreen(
                            viewModel,
                            state,
                            query,
                            { query = it },
                            openStation,
                            listModifier,
                            onOpenDataScreen,
                            listState
                        )
                    }

                    MainTab.FAVOURITES -> panes.listDetail(MainTab.FAVOURITES, pageContent) { listModifier ->
                        FavouritesScreen(
                            onOpenStation = { onOpenStation(StationRoute(it)) },
                            modifier = listModifier,
                            listState = listState
                        )
                    }

                    MainTab.FORECAST -> ForecastScreen(modifier = content.offHinge())

                    MainTab.HELP -> HelpHost(
                        isPro = isPro,
                        onOpenPro = onOpenPro,
                        modifier = pageContent,
                        onShowWelcomeGuide = onShowWelcomeGuide,
                        wide = panes != null,
                        listState = listState
                    )
                }
            }
            selected.adPlacement?.let { AdBanner(it, Modifier.offHinge(tabletop = false)) }
        }
    }
}

/**
 * In a wide window (FOX-119), the station open on each tab and its page, shown beside the map
 * ([panel]) or a list ([listDetail]).
 */
class StationPanes(
    val stationOf: (MainTab) -> Int?,
    val page: @Composable (tab: MainTab, stationId: Int, modifier: Modifier) -> Unit
) {
    fun panel(tab: MainTab): (@Composable (Modifier) -> Unit)? =
        stationOf(tab)?.let { stationId -> { modifier -> page(tab, stationId, modifier) } }
}

/** [list] on its own on a phone (no panes); in a wide window, with the tab's station or "Select a station" beside it. */
@Composable
private fun StationPanes?.listDetail(tab: MainTab, modifier: Modifier, list: @Composable (Modifier) -> Unit) {
    if (this == null) {
        list(modifier)
    } else {
        ListDetailLayout(
            list = list,
            detail = panel(tab),
            placeholder = {
                SelectionPlaceholder(R.drawable.ic_tile_aqi_medium, stringResource(R.string.details_select_a_station))
            },
            modifier = modifier
        )
    }
}
