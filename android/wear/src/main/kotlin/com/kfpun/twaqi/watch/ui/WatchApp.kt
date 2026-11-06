package com.kfpun.twaqi.watch.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.navigation.SwipeDismissableNavHost
import androidx.wear.compose.navigation.composable
import androidx.wear.compose.navigation.rememberSwipeDismissableNavController
import kotlinx.coroutines.flow.MutableStateFlow

private const val READING = "reading"
private const val PICKER = "picker"
private const val PAYWALL = "paywall"

@Composable
fun WatchApp(model: WatchModel, openPaywall: MutableStateFlow<Boolean>) {
    val navController = rememberSwipeDismissableNavController()
    val showPaywall by openPaywall.collectAsState()
    LaunchedEffect(showPaywall) {
        if (showPaywall) {
            navController.navigate(PAYWALL) { launchSingleTop = true }
            openPaywall.value = false
        }
    }

    WatchTheme {
        AppScaffold {
            SwipeDismissableNavHost(navController = navController, startDestination = READING) {
                composable(READING) {
                    ReadingScreen(
                        model = model,
                        onOpenPicker = { navController.navigate(PICKER) },
                        onOpenPaywall = { navController.navigate(PAYWALL) }
                    )
                }
                composable(PICKER) {
                    StationPickerScreen(model = model, onDone = { navController.popBackStack() })
                }
                composable(PAYWALL) {
                    PaywallScreen(model = model, onUnlocked = { navController.popBackStack() })
                }
            }
        }
    }
}
