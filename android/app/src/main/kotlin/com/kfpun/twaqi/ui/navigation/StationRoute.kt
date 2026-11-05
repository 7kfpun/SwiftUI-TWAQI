package com.kfpun.twaqi.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import com.kfpun.twaqi.ui.station.StationScreen

/**
 * The one way into a station's screen: the map's markers and closest-station card and the
 * station list all open it with the station's id (iOS `DetailsView(stationId:)`).
 */
data class StationRoute(val stationId: Int)

/**
 * The station page (FOX-55) for [route], with its own view model each time it opens, cleared on
 * back, as iOS builds a new `DetailsViewModel` per push: a page opened again reloads rather than
 * showing what it held last time.
 */
@Composable
fun StationDestination(route: StationRoute, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val owner = remember(route.stationId) {
        object : ViewModelStoreOwner {
            override val viewModelStore = ViewModelStore()
        }
    }
    DisposableEffect(owner) { onDispose { owner.viewModelStore.clear() } }
    CompositionLocalProvider(LocalViewModelStoreOwner provides owner) {
        StationScreen(stationId = route.stationId, onBack = onBack, modifier = modifier)
    }
}
