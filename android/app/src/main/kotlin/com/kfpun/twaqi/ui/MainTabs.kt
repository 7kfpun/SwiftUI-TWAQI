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
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.kfpun.twaqi.R
import com.kfpun.twaqi.ads.AdBanner
import com.kfpun.twaqi.ads.AdPlacement
import com.kfpun.twaqi.ui.help.HelpHost

/**
 * The app's tabs (iOS `ContentView`). The map, forecast, favourites and list tabs join with
 * FOX-54, FOX-90 and FOX-55; until then the main tab is a placeholder.
 */
enum class MainTab(@param:StringRes val label: Int, @param:DrawableRes val icon: Int, val adPlacement: AdPlacement) {
    MAIN(R.string.tabbar_main, R.drawable.ic_tab_home, AdPlacement.MAIN),
    HELP(R.string.tabbar_help, R.drawable.ic_tab_help, AdPlacement.HELP)
}

/**
 * @param isPro from the Pro entitlement (FOX-58); hides Help's Premium section.
 * @param onOpenPro opens the Pro screen (FOX-58).
 * @param onOpenDataScreen debug builds only: a button on the main tab to the data-layer check (FOX-53).
 */
@Composable
fun MainTabs(
    isPro: Boolean,
    onOpenPro: () -> Unit,
    modifier: Modifier = Modifier,
    onOpenDataScreen: (() -> Unit)? = null
) {
    var selected by rememberSaveable { mutableStateOf(MainTab.MAIN) }
    Scaffold(
        modifier = modifier.fillMaxSize(),
        // Each tab's own top bar takes the status bar; the navigation bar takes the bottom.
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
        // Each tab's banner sits above the tab bar (iOS: the footer banner of each tab).
        Column(Modifier.fillMaxSize().padding(innerPadding).consumeWindowInsets(innerPadding)) {
            val content = Modifier.weight(1f).fillMaxWidth()
            when (selected) {
                MainTab.MAIN -> Column(
                    content,
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = stringResource(R.string.app_name),
                        style = MaterialTheme.typography.headlineMedium,
                        color = MaterialTheme.colorScheme.primary
                    )
                    if (onOpenDataScreen != null) {
                        OutlinedButton(onClick = onOpenDataScreen, modifier = Modifier.padding(top = 24.dp)) {
                            Text(stringResource(R.string.debug_data_title))
                        }
                    }
                }

                MainTab.HELP -> HelpHost(isPro = isPro, onOpenPro = onOpenPro, modifier = content)
            }
            AdBanner(selected.adPlacement)
        }
    }
}
