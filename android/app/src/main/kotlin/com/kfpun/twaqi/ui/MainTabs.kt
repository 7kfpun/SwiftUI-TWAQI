package com.kfpun.twaqi.ui

import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.pro.ProSettingsRow
import com.kfpun.twaqi.ui.main.MainScreen
import com.kfpun.twaqi.ui.main.MainViewModel
import com.kfpun.twaqi.ui.main.StationListScreen
import com.kfpun.twaqi.ui.navigation.StationRoute
import com.kfpun.twaqi.ui.settings.LanguageSection
import kotlinx.coroutines.delay

/**
 * The app's tabs (iOS `ContentView`). The map (FOX-54) is home; the forecast and favourites tabs
 * join with their tickets, and Help (FOX-97) takes over the placeholder below.
 */
enum class MainTab(@param:StringRes val label: Int, @param:DrawableRes val icon: Int) {
    MAIN(R.string.tabbar_main, R.drawable.ic_tab_home),
    DETAILS_LIST(R.string.tabbar_details_list, R.drawable.ic_tab_list),
    HELP(R.string.tabbar_help, R.drawable.ic_tab_help)
}

/**
 * @param onOpenStation a station tapped on the map, its card or the list.
 * @param onOpenDataScreen debug builds only: the data-layer check screen (FOX-53).
 */
@Composable
fun MainTabs(onOpenStation: (StationRoute) -> Unit, onOpenDataScreen: (() -> Unit)?, modifier: Modifier = Modifier) {
    var selected by rememberSaveable { mutableStateOf(MainTab.MAIN) }
    var query by rememberSaveable { mutableStateOf("") }
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
        // The map draws under the status bar; the navigation bar takes the bottom.
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
        val content = Modifier.fillMaxSize().padding(innerPadding).consumeWindowInsets(innerPadding)
        when (selected) {
            MainTab.MAIN -> MainScreen(viewModel, state, query, { query = it }, openStation, content)
            MainTab.DETAILS_LIST -> StationListScreen(viewModel, state, query, { query = it }, openStation, content)
            MainTab.HELP -> HelpPlaceholder(onOpenDataScreen, content)
        }
    }
}

/** The language picker and the Pro row, until FOX-97's Help screen takes this tab. */
@Composable
private fun HelpPlaceholder(onOpenDataScreen: (() -> Unit)?, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.statusBarsPadding(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        LanguageSection(Modifier.fillMaxWidth().padding(top = 24.dp))
        ProSettingsRow(Modifier.padding(top = 8.dp))
        if (onOpenDataScreen != null) {
            OutlinedButton(onClick = onOpenDataScreen, modifier = Modifier.padding(top = 24.dp)) {
                Text(stringResource(R.string.debug_data_title))
            }
        }
    }
}
