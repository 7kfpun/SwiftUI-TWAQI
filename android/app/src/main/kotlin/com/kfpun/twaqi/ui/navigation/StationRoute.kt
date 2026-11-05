package com.kfpun.twaqi.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import com.kfpun.twaqi.feedback.FeedbackNavigation
import com.kfpun.twaqi.feedback.FeedbackSource
import com.kfpun.twaqi.push.AlertsUnavailableCard
import com.kfpun.twaqi.push.StationAlertsCard
import com.kfpun.twaqi.ui.station.StationPageSlots
import com.kfpun.twaqi.ui.station.StationScreen
import com.kfpun.twaqi.ui.station.cam.StationCamSection
import com.kfpun.twaqi.ui.station.forecast.StationForecastSection
import com.kfpun.twaqi.ui.station.weather.StationWeatherSection

/**
 * The one way into a station's screen: the map's markers and closest-station card and the
 * station list all open it with the station's id (iOS `DetailsView(stationId:)`).
 */
data class StationRoute(val stationId: Int)

/**
 * The station page (FOX-55) for [route], with its own view model each time it opens, cleared on
 * back, as iOS builds a new `DetailsViewModel` per push: a page opened again reloads rather than
 * showing what it held last time. Its "Send feedback" link opens the feedback form (FOX-60); its
 * alerts slot holds the station's alert switches (FOX-57), its cam slot the station cam (FOX-92),
 * its weather slot the CWA weather card (FOX-93) and its forecast slot the zone forecast (FOX-90).
 */
@Composable
fun StationDestination(route: StationRoute, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val owner = remember(route.stationId) {
        object : ViewModelStoreOwner {
            override val viewModelStore = ViewModelStore()
        }
    }
    DisposableEffect(owner) { onDispose { owner.viewModelStore.clear() } }
    val context = LocalContext.current
    CompositionLocalProvider(LocalViewModelStoreOwner provides owner) {
        StationScreen(
            stationId = route.stationId,
            onBack = onBack,
            modifier = modifier,
            onSendFeedback = { FeedbackNavigation.open(context, FeedbackSource.STATION_PAGE) },
            slots = StationPageSlots(
                // FOX-57: the alert switches, or why they can't be shown yet.
                alerts = { state, retry ->
                    if (state.stationLoadFailed) AlertsUnavailableCard(retry) else StationAlertsCard(route.stationId)
                },
                // FOX-92: the station cam with its 24-hour history.
                cam = { StationCamSection(it) },
                // FOX-90: the station's 空品區 forecast, hidden when its zone has none.
                forecast = { StationForecastSection(it) },
                // FOX-93: CWA weather near the station, hidden when nothing is in range.
                weather = { StationWeatherSection(it) }
            )
        )
    }
}
