package com.kfpun.twaqi.ui.station

import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.kfpun.twaqi.R
import com.kfpun.twaqi.TwaqiApplication
import com.kfpun.twaqi.ads.AdBanner
import com.kfpun.twaqi.ads.AdPlacement
import com.kfpun.twaqi.data.favourites.FavouriteAlertsHint
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.StationType
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.push.FavouriteAlerts
import com.kfpun.twaqi.translation.OnDeviceTranslation
import com.kfpun.twaqi.translation.TranslatesOnDevice
import com.kfpun.twaqi.translation.rememberShownTranslations
import com.kfpun.twaqi.ui.common.OfflineEmptyState
import com.kfpun.twaqi.ui.common.OfflineNotice
import java.time.Instant
import java.util.Locale

/**
 * Where later tickets plug into the station page, in iOS `DetailsView` order. Each is drawn only
 * when set, so the page has no empty sections until they land.
 *
 * @property share FOX-94: the share button, in the top bar before the heart.
 * @property alerts FOX-57: the alert switches row under the AQI scale (iOS `SettingsRow`), or the
 *   "alerts can't be loaded" card when the station record failed (`stationLoadFailed`).
 * @property forecast FOX-90: the 空品區 forecast (iOS `AreaForecastView`).
 * @property weather FOX-93: the CWA weather card (iOS `StationWeatherView`).
 * @property cam FOX-92: the station cam with its 24-hour history (iOS `StationCamView`).
 * @property wind the wind reading under the chart (iOS `WindView`), FOX-101.
 */
data class StationPageSlots(
    val share: (@Composable (StationDetailsUiState) -> Unit)? = null,
    val alerts: (@Composable (state: StationDetailsUiState, retry: () -> Unit) -> Unit)? = null,
    val forecast: (@Composable (StationDetailsUiState) -> Unit)? = null,
    val weather: (@Composable (StationDetailsUiState) -> Unit)? = null,
    val cam: (@Composable (StationDetailsUiState) -> Unit)? = null,
    val wind: (@Composable (state: StationDetailsUiState, selected: AirIndexType) -> Unit)? = null
)

/**
 * The station page (iOS `DetailsView`). Opened from Favourites here, and from the map and the
 * station list (FOX-54) with the same call.
 *
 * @param onOpenDefinition opens an index's definition; defaults to its Wikipedia article (iOS
 *   `DefinitionPages.url`) until the index guide (FOX-97) takes over.
 * @param onSendFeedback opens the feedback form (FOX-60, `FeedbackNavigation` with
 *   `FeedbackSource.STATION_PAGE`). The "Send feedback" link is hidden while it is null.
 */
@Composable
fun StationScreen(
    stationId: Int,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    slots: StationPageSlots = StationPageSlots(),
    onOpenDefinition: ((AirIndexType) -> Unit)? = null,
    onSendFeedback: (() -> Unit)? = null,
    viewModel: StationDetailsViewModel = viewModel(
        key = "station-$stationId",
        factory = StationDetailsViewModel.factory(
            stationId,
            LocalContext.current.applicationContext as TwaqiApplication
        )
    )
) {
    val context = LocalContext.current
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    // Each time the page shows, as iOS reloads in `onAppear`.
    LaunchedEffect(viewModel) { viewModel.refresh() }
    val chinese = AppLocale.isChinese(context)
    StationContent(
        state = state,
        chinese = chinese,
        onBack = onBack,
        onRefresh = viewModel::refresh,
        onToggleFavourite = viewModel::toggleFavourite,
        onConfirmUnfavourite = viewModel::removeFromFavourites,
        onDismissUnfavourite = viewModel::dismissUnfavourite,
        onDismissFavouriteAlertsHint = viewModel::dismissFavouriteAlertsHint,
        onOpenDefinition = onOpenDefinition ?: { DefinitionLinks.open(context, it, chinese) },
        // The form logs `open_feedback_form` (source station_page) itself when it opens (FOX-60).
        onSendFeedback = onSendFeedback,
        slots = slots,
        modifier = modifier
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StationContent(
    state: StationDetailsUiState,
    chinese: Boolean,
    onBack: () -> Unit,
    onRefresh: () -> Unit,
    onToggleFavourite: () -> Unit,
    onConfirmUnfavourite: () -> Unit,
    onDismissUnfavourite: () -> Unit,
    onDismissFavouriteAlertsHint: () -> Unit = {},
    onOpenDefinition: (AirIndexType) -> Unit,
    onSendFeedback: (() -> Unit)?,
    slots: StationPageSlots,
    modifier: Modifier = Modifier,
    now: Instant = Instant.now()
) {
    // Local to this page: the chart's pollutant never re-scores the map (iOS FOX-25 note).
    var selected by rememberSaveable { mutableStateOf(AirIndexType.AQI) }
    val pollutant = state.pollutant
    val station = state.station
    val aqi = state.currentAqi(now)

    Scaffold(
        modifier = modifier.fillMaxSize(),
        // The page opens over the tabs, so it has its own banner (iOS `AdUnitIdDetailsFooter`),
        // below the content, never over it.
        bottomBar = { AdBanner(AdPlacement.DETAILS, Modifier.navigationBarsPadding()) },
        topBar = {
            TopAppBar(
                title = {},
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            painterResource(R.drawable.ic_station_back),
                            contentDescription = stringResource(R.string.details_back)
                        )
                    }
                },
                actions = {
                    slots.share?.invoke(state)
                    FavouriteButton(state, onToggleFavourite)
                }
            )
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.TopCenter) {
            if (state.loading && pollutant == null && state.history.isEmpty()) {
                LinearProgressIndicator(Modifier.fillMaxWidth())
            }
            Column(
                Modifier
                    // A readable measure on tablets, as iOS caps the page at 640 points.
                    .widthIn(max = 640.dp)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
            ) {
                if (state.isShowingLastGood) {
                    OfflineNotice(Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp))
                } else if (state.loadFailed) {
                    OfflineEmptyState(onRetry = onRefresh, modifier = Modifier.padding(bottom = 24.dp))
                }

                // Township and street address come from the API in Chinese only; outside Chinese
                // they are translated on the device once it can (FOX-98).
                val translations = rememberShownTranslations()
                TranslatesOnDevice(OnDeviceTranslation.stationTexts(pollutant, station))
                StationHeader(
                    title = pollutant?.displayName(chinese) ?: station?.displayName(chinese) ?: "",
                    locality = pollutant?.displayLocality(chinese, translations::display)
                        ?: station?.displayLocality(chinese, translations::display),
                    area = pollutant?.displayArea(chinese) ?: station?.displayArea(chinese),
                    stationType = pollutant?.stationType ?: station?.stationType ?: StationType.UNKNOWN,
                    aqi = aqi,
                    publishTime = state.latestPublishTime
                )
                AqiScale(aqi, Modifier.padding(top = 4.dp, bottom = 16.dp))

                // FOX-57: tell me next time, straight under the reading.
                slots.alerts?.let { alerts ->
                    Box(Modifier.padding(bottom = 16.dp)) { alerts(state, onRefresh) }
                }

                if (aqi > 0) HealthGuidance(aqi, Modifier.padding(bottom = 16.dp))

                // Where that number is heading, the weather behind it, and what it looks like outside.
                val outlook = listOfNotNull(slots.forecast, slots.weather, slots.cam)
                if (outlook.isNotEmpty()) {
                    SectionSeparator()
                    Column(Modifier.padding(vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        outlook.forEach { it(state) }
                    }
                }

                SectionSeparator()

                if (state.isNotReporting) NotReporting(Modifier.padding(vertical = 16.dp))

                if (pollutant != null) {
                    PollutantGrid(
                        values = pollutant::value,
                        selected = selected,
                        onSelect = { selected = it },
                        modifier = Modifier.padding(top = 16.dp, bottom = 4.dp)
                    )
                }

                if (state.showsHistory(now)) HistorySection(state.history, selected, onOpenDefinition)

                SectionSeparator()

                if (pollutant != null) {
                    slots.wind?.let { wind ->
                        Box(Modifier.padding(vertical = 16.dp)) { wind(state, selected) }
                        SectionSeparator()
                    }
                }

                val lat = pollutant?.lat ?: station?.lat
                val lon = pollutant?.lon ?: station?.lon
                if (lat != null && lon != null) {
                    StationLocation(
                        lat = lat,
                        lon = lon,
                        address = (pollutant?.address ?: station?.address)?.let(translations::display),
                        coordinateText = String.format(Locale.US, "%.6f, %.6f", lat, lon),
                        modifier = Modifier.padding(vertical = 16.dp)
                    )
                }

                // Low-key and last (iOS FOX-46).
                if (onSendFeedback != null) FeedbackLink(onSendFeedback)
            }
        }
    }

    if (state.confirmingUnfavourite) {
        AlertDialog(
            onDismissRequest = onDismissUnfavourite,
            title = { Text(stringResource(R.string.favourites_remove_station_with_alerts_title)) },
            text = { Text(stringResource(R.string.favourites_remove_station_with_alerts_message)) },
            confirmButton = {
                TextButton(onClick = onConfirmUnfavourite) {
                    Text(
                        stringResource(R.string.favourites_remove_and_turn_off_alerts),
                        color = MaterialTheme.colorScheme.error
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = onDismissUnfavourite) { Text(stringResource(R.string.favourites_cancel)) }
            }
        )
    }

    // Favourited, but its alerts couldn't be switched on: one line on why, and the way to fix it
    // when it's a setting (iOS `favouriteAlertsHint`, FOX-57).
    state.favouriteAlertsHint?.let { hint ->
        FavouriteAlertsHintDialog(hint, onDismissFavouriteAlertsHint)
    }
}

@Composable
private fun FavouriteAlertsHintDialog(hint: FavouriteAlertsHint, onDismiss: () -> Unit) {
    val context = LocalContext.current
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.favourites_added_to_favourites)) },
        text = {
            Text(
                when (hint) {
                    FavouriteAlertsHint.CAP_REACHED -> stringResource(
                        R.string.favourites_alerts_cap_reached_message,
                        FavouriteAlerts.MAX_ALERTED_STATIONS
                    )

                    FavouriteAlertsHint.NOTIFICATIONS_DENIED -> stringResource(
                        R.string.favourites_notifications_off_message
                    )
                }
            )
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.favourites_ok)) }
        },
        dismissButton = if (hint == FavouriteAlertsHint.NOTIFICATIONS_DENIED) {
            {
                TextButton(onClick = {
                    onDismiss()
                    context.startActivity(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                    )
                }) { Text(stringResource(R.string.favourites_open_settings)) }
            }
        } else {
            null
        }
    )
}

/** Disabled until the station is known to exist, unless it is already a favourite (iOS FOX-74). */
@Composable
private fun FavouriteButton(state: StationDetailsUiState, onToggle: () -> Unit) {
    IconButton(onClick = onToggle, enabled = state.canToggleFavourite) {
        Icon(
            painterResource(
                if (state.isFavourite) R.drawable.ic_station_heart else R.drawable.ic_station_heart_outline
            ),
            contentDescription = stringResource(
                if (state.isFavourite) {
                    R.string.favourites_remove_from_favourites
                } else {
                    R.string.favourites_add_to_favourites
                }
            ),
            tint = if (state.isFavourite) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
        )
    }
}

@Composable
private fun FeedbackLink(onClick: () -> Unit) {
    Box(Modifier.fillMaxWidth().padding(vertical = 16.dp), contentAlignment = Alignment.Center) {
        TextButton(onClick = onClick) {
            Icon(
                painterResource(R.drawable.ic_station_feedback),
                contentDescription = null,
                modifier = Modifier.size(16.dp)
            )
            Text(
                stringResource(R.string.details_send_feedback),
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(start = 6.dp)
            )
        }
    }
}
