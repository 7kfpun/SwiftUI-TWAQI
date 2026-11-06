package com.kfpun.twaqi.ui

import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
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
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.kfpun.twaqi.R
import com.kfpun.twaqi.ads.AdBanner
import com.kfpun.twaqi.ads.AdPlacement
import com.kfpun.twaqi.data.model.Pollutant
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
 */
@Composable
fun MainTabs(
    isPro: Boolean,
    onOpenPro: () -> Unit,
    onOpenStation: (StationRoute) -> Unit,
    modifier: Modifier = Modifier,
    onOpenDataScreen: (() -> Unit)? = null,
    onShowWelcomeGuide: () -> Unit = {}
) {
    var selected by rememberSaveable { mutableStateOf(MainTab.MAIN) }
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
                MainTab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = tab == selected,
                        onClick = { selected = tab },
                        icon = { Icon(painterResource(tab.icon), contentDescription = null) },
                        label = { Text(stringResource(tab.label)) }
                    )
                }
            }
        }
    ) { innerPadding ->
        // Each tab's banner sits above the tab bar (iOS: the footer banner of each tab), hidden for Pro.
        Column(Modifier.fillMaxSize().padding(innerPadding).consumeWindowInsets(innerPadding)) {
            val content = Modifier.weight(1f).fillMaxWidth()
            tabStates.SaveableStateProvider(selected.name) {
                when (selected) {
                    MainTab.MAIN -> MainScreen(viewModel, state, query, { query = it }, openStation, content)

                    MainTab.DETAILS_LIST -> StationListScreen(
                        viewModel,
                        state,
                        query,
                        { query = it },
                        openStation,
                        content,
                        onOpenDataScreen
                    )

                    MainTab.FAVOURITES -> FavouritesScreen(onOpenStation = {
                        onOpenStation(StationRoute(it))
                    }, modifier = content)

                    MainTab.FORECAST -> ForecastScreen(modifier = content)

                    MainTab.HELP -> HelpHost(
                        isPro = isPro,
                        onOpenPro = onOpenPro,
                        modifier = content,
                        onShowWelcomeGuide = onShowWelcomeGuide
                    )
                }
            }
            selected.adPlacement?.let { AdBanner(it) }
        }
    }
}
