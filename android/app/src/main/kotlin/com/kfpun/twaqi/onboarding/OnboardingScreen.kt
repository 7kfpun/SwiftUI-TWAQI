package com.kfpun.twaqi.onboarding

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.DrawableRes
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.kfpun.twaqi.R
import com.kfpun.twaqi.TwaqiApplication
import com.kfpun.twaqi.data.favourites.FavouriteAlertsHint
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.pro.Entitlement
import com.kfpun.twaqi.pro.ProGraph
import com.kfpun.twaqi.pro.ProNavigation
import com.kfpun.twaqi.pro.ProScreenSource
import com.kfpun.twaqi.push.AlertNotifications
import com.kfpun.twaqi.push.FavouriteAlerts
import com.kfpun.twaqi.push.PushGraph
import com.kfpun.twaqi.ui.common.rgb
import com.kfpun.twaqi.ui.help.WidgetGuideScreen
import com.kfpun.twaqi.ui.main.LocationAccess
import com.kfpun.twaqi.ui.main.MapPreferences
import com.kfpun.twaqi.ui.settings.DoNotDisturbRows
import com.kfpun.twaqi.ui.station.StationDetailsViewModel
import com.kfpun.twaqi.ui.station.faceImage

/** iOS's flow accent (`Color(0x5AC8FA)`). */
private val Accent = Color(0xFF5AC8FA)

/** A readable width on tablets and in wide windows (iOS 560 pt). */
private val MaxContentWidth = 560.dp

/**
 * The welcome flow (iOS `OnboardingView`, FOX-34 / FOX-84), one step at a time, five at most.
 *
 * Every step can be continued without doing what it asks ("Not now"), and Skip at the top ends the
 * whole flow. Back goes to the step before; on the first step it skips. It opens by itself once,
 * counted when it opens rather than when it ends; Help runs it anytime.
 *
 * @param runKey one per run, so a run from Help starts on the first step with fresh state.
 * @param isLaunchFlow opened by itself at launch rather than from Help. Only that run ends the
 *   launch-time hold on the review prompt.
 */
@Composable
fun OnboardingScreen(runKey: String, isLaunchFlow: Boolean, onFinish: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val app = context.applicationContext as TwaqiApplication
    val viewModel: OnboardingViewModel = viewModel(
        key = runKey,
        factory = remember(app) { OnboardingViewModel.factory(app, locationState(app), notificationState(app)) }
    )
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val pushSync = remember(context) { PushGraph.sync(context) }

    // Back from Settings with location or notifications changed.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                viewModel.permissionsChanged(locationState(context), notificationState(context))
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }

    val locationPrompt =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { results ->
            viewModel.locationAnswered(
                granted = results.containsValue(true) || LocationAccess.isGranted(context),
                prompted = true
            )
        }
    val notificationPrompt = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        // Tell the sender now whether this device can show alerts.
        pushSync.notificationsChanged()
        viewModel.notificationsAnswered(granted)
    }

    fun finish(skippedAt: OnboardingStep? = null) {
        viewModel.finish(skippedAt, isLaunchFlow)
        onFinish()
    }

    val actions = OnboardingActions(
        goForward = viewModel::goForward,
        requestLocation = {
            if (state.location != PermissionState.ASKING) {
                viewModel.locationAsked()
                // The map's own first-launch ask then stays away, as a refusal here should.
                MapPreferences(context).askedForLocation = true
                locationPrompt.launch(LocationAccess.permissions)
            }
        },
        requestNotifications = {
            if (state.notifications != PermissionState.ASKING &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
            ) {
                viewModel.notificationsAsked()
                pushSync.notificationsAsked()
                notificationPrompt.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        },
        openLocationSettings = { openAppSettings(context) },
        openNotificationSettings = { openNotificationSettings(context) },
        openPro = {
            viewModel.proOpened()
            ProNavigation.open(context, ProScreenSource.ONBOARDING)
        },
        finish = { finish() }
    )

    // The suggested station, added through the station page's own model (FOX-31: its alerts with it).
    val shownId = state.shownStationId
    val station = if (state.step == OnboardingStep.CLOSEST_STATION && shownId != null) stationModel(shownId) else null
    // Loads the station record, which adding it waits for, as on the station page.
    LaunchedEffect(station) { station?.refresh() }
    val stationDetails = station?.uiState?.collectAsStateWithLifecycle()?.value
    val canAddStation = stationDetails != null && !stationDetails.isFavourite
    val addStation = {
        val favourites = app.container.favourites
        if (station != null && shownId != null && !favourites.contains(shownId)) {
            station.toggleFavourite()
            if (favourites.contains(shownId)) viewModel.favouriteAdded(shownId)
        }
    }

    BackHandler {
        if (state.step.previous != null) viewModel.goBack() else finish(skippedAt = state.step)
    }

    Surface(modifier = modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(Modifier.fillMaxSize().systemBarsPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
            TopBar(
                step = state.step,
                onBack = viewModel::goBack,
                onSkip = { finish(skippedAt = state.step) }
            )
            Crossfade(
                targetState = state.step,
                animationSpec = tween(200),
                modifier = Modifier.weight(1f),
                label = "step"
            ) { step ->
                // Each step starts at its top.
                val scroll = rememberScrollState()
                Box(Modifier.fillMaxSize().verticalScroll(scroll), contentAlignment = Alignment.TopCenter) {
                    Column(
                        modifier = Modifier
                            .widthIn(max = MaxContentWidth)
                            .fillMaxWidth()
                            .padding(horizontal = 24.dp, vertical = 16.dp),
                        verticalArrangement = Arrangement.spacedBy(20.dp)
                    ) {
                        StepContent(step, state, viewModel, actions)
                    }
                }
            }
            Actions(
                state = state,
                isPro = isPro(),
                canAddStation = canAddStation,
                onAddStation = addStation,
                actions = actions,
                modifier = Modifier
                    .widthIn(max = MaxContentWidth)
                    .fillMaxWidth()
                    .padding(start = 24.dp, end = 24.dp, bottom = 16.dp)
            )
        }
    }
}

/** What the steps' buttons do. */
private class OnboardingActions(
    val goForward: () -> Unit,
    val requestLocation: () -> Unit,
    val requestNotifications: () -> Unit,
    val openLocationSettings: () -> Unit,
    val openNotificationSettings: () -> Unit,
    val openPro: () -> Unit,
    val finish: () -> Unit
)

@Composable
private fun isPro(): Boolean {
    val context = LocalContext.current
    val entitlement by remember(context) { ProGraph.repository(context).entitlement }.collectAsState()
    return entitlement == Entitlement.PRO
}

// Chrome

@Composable
private fun TopBar(step: OnboardingStep, onBack: () -> Unit, onSkip: () -> Unit) {
    Box(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 8.dp), contentAlignment = Alignment.Center) {
        if (step.previous != null) {
            IconButton(onClick = onBack, modifier = Modifier.align(Alignment.CenterStart)) {
                Icon(
                    painterResource(R.drawable.ic_arrow_back),
                    contentDescription = stringResource(R.string.onboarding_back),
                    tint = Accent
                )
            }
        }
        PageDots(step)
        if (!step.isLast) {
            TextButton(onClick = onSkip, modifier = Modifier.align(Alignment.CenterEnd)) {
                Text(stringResource(R.string.onboarding_skip), color = Accent)
            }
        }
    }
}

@Composable
private fun PageDots(current: OnboardingStep) {
    val label = stringResource(R.string.onboarding_step, current.analyticsIndex, OnboardingStep.entries.size)
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.clearAndSetSemantics { contentDescription = label }
    ) {
        OnboardingStep.entries.forEach { step ->
            Box(
                Modifier
                    .size(7.dp)
                    .background(
                        if (step == current) Accent else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                        CircleShape
                    )
            )
        }
    }
}

/** Smaller at the largest text sizes, so the words get the room (iOS 150 / 110 pt). */
@Composable
private fun animationSize(): Dp = if (LocalDensity.current.fontScale >= 1.5f) 110.dp else 150.dp

@Composable
private fun Header(animation: OnboardingAnimation, title: Int, body: Int) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        OnboardingAnimationView(animation, animationSize(), Modifier.padding(top = 8.dp))
        Text(
            stringResource(title),
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
            modifier = Modifier.semantics { heading() }
        )
        Text(
            stringResource(body),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun Note(text: String, @DrawableRes icon: Int = R.drawable.ic_station_info) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(
            painterResource(icon),
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(20.dp)
        )
        Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** A permission granted or a station added: a check that draws itself, then the words. */
@Composable
private fun SuccessNote(text: String) {
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        OnboardingAnimationView(OnboardingAnimation.SUCCESS, 32.dp)
        Text(text, style = MaterialTheme.typography.bodyMedium)
    }
}

// Steps

@Composable
private fun StepContent(
    step: OnboardingStep,
    state: OnboardingUiState,
    viewModel: OnboardingViewModel,
    actions: OnboardingActions
) {
    when (step) {
        OnboardingStep.WELCOME -> {
            Header(step.animation, R.string.onboarding_welcome_title, R.string.onboarding_welcome_body)
            Note(stringResource(R.string.onboarding_welcome_data))
        }

        OnboardingStep.LOCATION -> {
            Header(step.animation, R.string.onboarding_location_title, R.string.onboarding_location_body)
            when (state.location) {
                PermissionState.ON -> SuccessNote(stringResource(R.string.onboarding_location_on))
                PermissionState.OFF -> Note(stringResource(R.string.onboarding_location_off))
                PermissionState.NOT_ASKED, PermissionState.ASKING -> Unit
            }
        }

        OnboardingStep.CLOSEST_STATION -> ClosestStationStep(state, viewModel)

        OnboardingStep.NOTIFICATIONS -> {
            Header(step.animation, R.string.onboarding_notifications_title, R.string.onboarding_notifications_body)
            when (state.notifications) {
                PermissionState.ON -> SuccessNote(stringResource(R.string.onboarding_notifications_on))

                PermissionState.OFF -> Note(stringResource(R.string.onboarding_notifications_off))

                PermissionState.NOT_ASKED, PermissionState.ASKING ->
                    Note(stringResource(R.string.onboarding_dnd_after_notifications), R.drawable.ic_onboarding_moon)
            }
            if (state.showsQuietHours) QuietHours()
        }

        OnboardingStep.MORE -> MoreStep(actions)
    }
}

@Composable
private fun ClosestStationStep(state: OnboardingUiState, viewModel: OnboardingViewModel) {
    var choosing by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(Unit) { viewModel.loadClosestStation() }

    Header(OnboardingAnimation.CLOSEST_STATION, R.string.onboarding_closest_title, R.string.onboarding_closest_body)
    when (val closest = state.closest) {
        ClosestState.Loading -> Box(
            Modifier.fillMaxWidth().heightIn(min = 88.dp),
            contentAlignment = Alignment.Center
        ) {
            CircularProgressIndicator(color = Accent)
        }

        ClosestState.Failed -> Note(stringResource(R.string.onboarding_closest_failed), R.drawable.ic_station_offline)

        is ClosestState.Loaded -> {
            StationCard(closest.station.pollutant)
            if (closest.station.isFallback) {
                Note(stringResource(R.string.onboarding_closest_fallback), R.drawable.ic_onboarding_location_off)
            }
            if (state.stations.isNotEmpty()) {
                OutlinedButton(onClick = { choosing = true }, modifier = Modifier.fillMaxWidth()) {
                    Icon(
                        painterResource(R.drawable.ic_search),
                        contentDescription = null,
                        tint = Accent,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.onboarding_choose_station), color = Accent)
                }
            }
            FavouriteStatus(closest.station.pollutant.stationId)
        }
    }

    if (choosing) {
        OnboardingStationPicker(
            stations = state.stations,
            selectedId = state.shownStationId,
            onPick = {
                viewModel.chooseStation(it)
                choosing = false
            },
            onDismiss = { choosing = false }
        )
    }
}

/** The station page's own model for the suggested station, so adding it goes the way the heart goes (FOX-31). */
@Composable
private fun stationModel(stationId: Int): StationDetailsViewModel {
    val app = LocalContext.current.applicationContext as TwaqiApplication
    val model: StationDetailsViewModel = viewModel(
        key = "onboarding-station-$stationId",
        factory = StationDetailsViewModel.factory(stationId, app)
    )
    return model
}

@Composable
private fun FavouriteStatus(stationId: Int) {
    val details by stationModel(stationId).uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val alerted by remember(context) {
        (context.applicationContext as TwaqiApplication).container.favourites.alerts.alertedStationIds
    }.collectAsState()
    if (!details.isFavourite) return
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SuccessNote(stringResource(R.string.onboarding_in_favourites))
        when {
            stationId in alerted ->
                IconLine(stringResource(R.string.onboarding_alerts_now_on), R.drawable.ic_station_bell, Accent)

            details.favouriteAlertsHint == FavouriteAlertsHint.CAP_REACHED -> IconLine(
                stringResource(R.string.favourites_alerts_cap_reached_message, FavouriteAlerts.MAX_ALERTED_STATIONS),
                R.drawable.ic_station_bell
            )

            details.favouriteAlertsHint == FavouriteAlertsHint.NOTIFICATIONS_DENIED ->
                IconLine(stringResource(R.string.onboarding_alerts_need_notifications), R.drawable.ic_station_bell)
        }
    }
}

@Composable
private fun IconLine(text: String, @DrawableRes icon: Int, tint: Color = MaterialTheme.colorScheme.onSurfaceVariant) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(painterResource(icon), contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            color = if (tint == Accent) MaterialTheme.colorScheme.onSurface else tint
        )
    }
}

/** The suggested station's current AQI, with its face and level. */
@Composable
private fun StationCard(pollutant: Pollutant) {
    val chinese = AppLocale.isChinese(LocalContext.current)
    val value = pollutant.value(AirIndexType.AQI)
    val status = AirStatus.of(AirIndexType.AQI, value)
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        modifier = Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}
    ) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            status.faceImage()?.let {
                Image(painterResource(it), contentDescription = null, modifier = Modifier.size(48.dp))
                Spacer(Modifier.width(14.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    pollutant.displayName(chinese),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold
                )
                pollutant.displayLocality(chinese)?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    stringResource(status.label),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold
                )
            }
            Spacer(Modifier.width(8.dp))
            Column(
                modifier = Modifier
                    .sizeIn(minWidth = 72.dp, minHeight = 72.dp)
                    .background(rgb(status.color), RoundedCornerShape(12.dp))
                    .padding(8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                val foreground = rgb(status.foregroundColor)
                Text(
                    "AQI",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                    color = foreground
                )
                Text(
                    if (value != 0.0) AirIndexType.AQI.format(value) else "-",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    color = foreground,
                    maxLines = 1
                )
            }
        }
    }
}

/** Help's quiet-hours controls (FOX-57), written as Help writes them. */
@Composable
private fun QuietHours() {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(Modifier.padding(vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                Modifier.padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    painterResource(R.drawable.ic_onboarding_moon),
                    contentDescription = null,
                    modifier = Modifier.size(20.dp)
                )
                Text(
                    stringResource(R.string.onboarding_dnd_title),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.semantics { heading() }
                )
            }
            Text(
                stringResource(R.string.onboarding_dnd_body),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp)
            )
            DoNotDisturbRows(showsCancelAll = false)
            Text(
                stringResource(R.string.onboarding_dnd_footer),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp)
            )
        }
    }
}

@Composable
private fun MoreStep(actions: OnboardingActions) {
    var showingWidgetGuide by rememberSaveable { mutableStateOf(false) }
    Header(OnboardingAnimation.MORE, R.string.onboarding_more_title, R.string.onboarding_more_body)
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        MoreRow(
            icon = R.drawable.ic_pro_widgets,
            color = AirStatus.GOOD,
            title = R.string.onboarding_more_widgets_title,
            detail = R.string.onboarding_more_widgets_body,
            onClick = { showingWidgetGuide = true }
        )
        // Android has no guide page for these; the detail says how (iOS links its Shortcuts guide).
        MoreRow(
            icon = R.drawable.ic_onboarding_mic,
            color = AirStatus.UNHEALTHY_FOR_SENSITIVE_GROUP,
            title = R.string.onboarding_more_shortcuts_title,
            detail = R.string.onboarding_more_shortcuts_body,
            onClick = null
        )
        MoreRow(
            icon = R.drawable.ic_tab_forecast,
            color = AirStatus.MODERATE,
            title = R.string.onboarding_more_forecast_title,
            detail = R.string.onboarding_more_forecast_body,
            onClick = null
        )
    }
    OnboardingProSummary(isPro = isPro())

    if (showingWidgetGuide) {
        FullScreenDialog(onDismiss = { showingWidgetGuide = false }) {
            WidgetGuideScreen(onBack = { showingWidgetGuide = false })
        }
    }
}

/** One thing the app does outside the app, with how to add it. */
@Composable
private fun MoreRow(@DrawableRes icon: Int, color: AirStatus, title: Int, detail: Int, onClick: (() -> Unit)?) {
    Surface(
        shape = RoundedCornerShape(14.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        modifier = Modifier
            .fillMaxWidth()
            .let { if (onClick != null) it.clickable(onClick = onClick) else it.semantics(mergeDescendants = true) {} }
    ) {
        Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(
                Modifier.size(40.dp).background(rgb(color.color), RoundedCornerShape(10.dp)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    painterResource(icon),
                    contentDescription = null,
                    tint = rgb(color.foregroundColor),
                    modifier = Modifier.size(24.dp)
                )
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(stringResource(title), style = MaterialTheme.typography.titleMedium)
                Text(
                    stringResource(detail),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                if (onClick != null) {
                    Text(
                        stringResource(R.string.onboarding_how_to_add),
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = Accent
                    )
                }
            }
        }
    }
}

// Buttons

@Composable
private fun Actions(
    state: OnboardingUiState,
    isPro: Boolean,
    canAddStation: Boolean,
    onAddStation: () -> Unit,
    actions: OnboardingActions,
    modifier: Modifier = Modifier
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        when (state.step) {
            OnboardingStep.WELCOME -> WideButton(R.string.onboarding_get_started, onClick = actions.goForward)

            OnboardingStep.LOCATION -> when (state.location) {
                PermissionState.NOT_ASKED -> WideButton(
                    R.string.onboarding_enable_location,
                    onClick = actions.requestLocation
                )

                PermissionState.ASKING -> WideButton(R.string.onboarding_enable_location, enabled = false, onClick = {})

                PermissionState.ON, PermissionState.OFF -> WideButton(
                    R.string.onboarding_continue,
                    onClick = actions.goForward
                )
            }

            OnboardingStep.CLOSEST_STATION ->
                if (canAddStation) {
                    WideButton(R.string.onboarding_add_to_favourites, onClick = onAddStation)
                } else {
                    WideButton(R.string.onboarding_continue, onClick = actions.goForward)
                }

            OnboardingStep.NOTIFICATIONS -> when (state.notifications) {
                PermissionState.NOT_ASKED ->
                    WideButton(R.string.onboarding_allow_notifications, onClick = actions.requestNotifications)

                PermissionState.ASKING ->
                    WideButton(R.string.onboarding_allow_notifications, enabled = false, onClick = {})

                PermissionState.ON, PermissionState.OFF -> WideButton(
                    R.string.onboarding_continue,
                    onClick = actions.goForward
                )
            }

            OnboardingStep.MORE -> WideButton(R.string.onboarding_done, onClick = actions.finish)
        }

        val secondary: Pair<Int, () -> Unit>? = when {
            state.step == OnboardingStep.LOCATION && state.location == PermissionState.NOT_ASKED ->
                R.string.onboarding_not_now to actions.goForward

            state.step == OnboardingStep.NOTIFICATIONS && state.notifications == PermissionState.NOT_ASKED ->
                R.string.onboarding_not_now to actions.goForward

            state.step == OnboardingStep.LOCATION && state.location == PermissionState.OFF ->
                R.string.onboarding_open_settings to actions.openLocationSettings

            state.step == OnboardingStep.NOTIFICATIONS && state.notifications == PermissionState.OFF ->
                R.string.onboarding_open_settings to actions.openNotificationSettings

            state.step == OnboardingStep.CLOSEST_STATION && canAddStation ->
                R.string.onboarding_not_now to
                    actions.goForward

            state.step == OnboardingStep.MORE && !isPro -> R.string.onboarding_see_pro_plans to actions.openPro

            else -> null
        }
        // Keeps the primary button where it was from step to step.
        Box(Modifier.fillMaxWidth().heightIn(min = 40.dp), contentAlignment = Alignment.Center) {
            secondary?.let { (label, onClick) ->
                TextButton(onClick = onClick) { Text(stringResource(label), color = Accent) }
            }
        }
    }
}

@Composable
private fun WideButton(label: Int, enabled: Boolean = true, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = enabled,
        colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Color.White),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)
    ) {
        Text(stringResource(label), style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
    }
}

/** A page over the flow (a guide, the station list), closed back onto it. */
@Composable
internal fun FullScreenDialog(onDismiss: () -> Unit, content: @Composable () -> Unit) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)
    ) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) { content() }
    }
}

// Permissions as Android has them now

private fun locationState(context: Context): PermissionState =
    PermissionState.of(LocationAccess.isGranted(context), asked = MapPreferences(context).askedForLocation)

/** Below Android 13 there is no prompt: notifications are on unless turned off in Settings. */
private fun notificationState(context: Context): PermissionState = PermissionState.of(
    AlertNotifications.canPost(context),
    asked = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || PushGraph.sync(context).wasAskedForNotifications
)

private fun openAppSettings(context: Context) {
    start(
        context,
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
    )
}

private fun openNotificationSettings(context: Context) {
    val intent = Intent(
        Settings.ACTION_APP_NOTIFICATION_SETTINGS
    ).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
    if (!start(context, intent)) openAppSettings(context)
}

private fun start(context: Context, intent: Intent): Boolean = try {
    context.startActivity(intent)
    true
} catch (_: ActivityNotFoundException) {
    false
}
