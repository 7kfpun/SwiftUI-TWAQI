package com.kfpun.twaqi.push

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import kotlin.math.roundToInt

/** Below this, the "above" alert would fire all the time (iOS `SettingsRow.tooSmallPollution`). */
private const val TOO_SMALL_POLLUTION = 110.0

/** Above this, the "below" alert would fire all the time (iOS `SettingsRow.tooLargeCleanliness`). */
private const val TOO_LARGE_CLEANLINESS = 30.0

/**
 * A station's alert card (iOS `SettingsRow`), for the station page's alerts slot (FOX-55,
 * `StationPageSlots.alerts`). Switching an alert on asks for the notification permission on
 * Android 13+ when it hasn't been given.
 */
@Composable
fun StationAlertsCard(stationId: Int, modifier: Modifier = Modifier, siteId: String? = null) {
    val context = LocalContext.current
    val graph = remember(context) { PushGraph.get(context) }
    val viewModel: StationAlertsViewModel = viewModel(
        key = "alerts-$stationId",
        factory = StationAlertsViewModel.factory(stationId, siteId, graph)
    )
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        // The answer goes on the device row at once.
        graph.sync.notificationsChanged()
    }
    StationAlertsCardContent(
        state = state,
        onChange = { setting ->
            val switchedOn = setting.isOn && !state.setting.isOn
            if (viewModel.onChange(setting) && switchedOn && needsNotificationPermission(context)) {
                graph.sync.notificationsAsked()
                permission.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        },
        modifier = modifier
    )
}

private fun needsNotificationPermission(context: android.content.Context): Boolean =
    Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
        PackageManager.PERMISSION_GRANTED

/** The card without its view model, for previews and screenshots. */
@Composable
fun StationAlertsCardContent(
    state: StationAlertsUiState,
    onChange: (StationAlertSetting) -> Unit,
    modifier: Modifier = Modifier
) {
    val setting = state.setting
    AlertsCard(isOn = setting.isOn, modifier = modifier) {
        Threshold(
            title = stringResource(R.string.settings_notice_me_when_aqi_is_above),
            isOn = setting.isPollutionNotificationEnabled,
            locked = state.pollutionLocked,
            value = setting.pollutionThreshold,
            warning = if (setting.pollutionThreshold < TOO_SMALL_POLLUTION) {
                stringResource(R.string.settings_the_value_is_too_small_you_would_get_lots_of_notifications)
            } else {
                null
            },
            onToggle = { onChange(setting.copy(isPollutionNotificationEnabled = it)) },
            onValue = { onChange(setting.copy(pollutionThreshold = it)) }
        )
        Threshold(
            title = stringResource(R.string.settings_notice_me_when_aqi_is_below),
            isOn = setting.isCleanlinessNotificationEnabled,
            locked = state.cleanlinessLocked,
            value = setting.cleanlinessThreshold,
            warning = if (setting.cleanlinessThreshold > TOO_LARGE_CLEANLINESS) {
                stringResource(R.string.settings_the_value_is_too_large_you_would_get_lots_of_notifications)
            } else {
                null
            },
            onToggle = { onChange(setting.copy(isCleanlinessNotificationEnabled = it)) },
            onValue = { onChange(setting.copy(cleanlinessThreshold = it)) }
        )
        // One line under the switches on why they can't be used, if they can't.
        if (state.isAtCap) {
            Caption(stringResource(R.string.settings_alerts_station_limit, FavouriteAlerts.MAX_ALERTED_STATIONS))
        }
    }
}

/** The alerts card when its station hasn't loaded, so there is nothing to switch yet (iOS `AlertsUnavailableCard`). */
@Composable
fun AlertsUnavailableCard(retry: () -> Unit, modifier: Modifier = Modifier) {
    AlertsCard(isOn = null, modifier = modifier) {
        Caption(stringResource(R.string.details_alerts_unavailable))
        OutlinedButton(onClick = retry) { Text(stringResource(R.string.details_alerts_try_again)) }
    }
}

/** The card's frame: the bell, what alerts do and, when known, whether they are on (iOS `AlertsCard`). */
@Composable
private fun AlertsCard(isOn: Boolean?, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Surface(
        modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh
    ) {
        Column {
            Row(
                modifier = Modifier.padding(12.dp).semantics(mergeDescendants = true) { heading() },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(
                    painterResource(R.drawable.ic_notification),
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(28.dp)
                )
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(stringResource(R.string.details_alerts_title), style = MaterialTheme.typography.titleMedium)
                    Text(
                        stringResource(R.string.details_alerts_pitch),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                if (isOn != null) Badge(isOn)
            }
            HorizontalDivider()
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) { content() }
        }
    }
}

@Composable
private fun Badge(isOn: Boolean) {
    val colors = MaterialTheme.colorScheme
    Text(
        text = stringResource(if (isOn) R.string.details_alerts_on else R.string.details_alerts_off),
        style = MaterialTheme.typography.labelMedium,
        color = if (isOn) colors.onPrimary else colors.onSurfaceVariant,
        modifier = Modifier
            .clip(CircleShape)
            .background(if (isOn) colors.primary else colors.surfaceVariant)
            .padding(horizontal = 8.dp, vertical = 3.dp)
    )
}

/**
 * One alert threshold: a switch, and only once it's on, the value and the slider that sets it,
 * side by side. The advice under it shows only while the alert is on.
 */
@Composable
private fun Threshold(
    title: String,
    isOn: Boolean,
    locked: Boolean,
    value: Double,
    warning: String?,
    onToggle: (Boolean) -> Unit,
    onValue: (Double) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                title,
                style = MaterialTheme.typography.bodyMedium,
                color = if (locked) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.weight(1f)
            )
            Switch(checked = isOn, onCheckedChange = onToggle, enabled = !locked)
        }
        if (isOn) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                AqiChip(value)
                Slider(
                    value = value.toFloat(),
                    onValueChange = { onValue(it.roundToInt().toDouble()) },
                    valueRange = 1f..500f,
                    steps = 498,
                    modifier = Modifier.weight(1f)
                )
            }
            warning?.let { Caption(it) }
        }
    }
}

/** The threshold in its AQI band's colour (iOS `LabelView`). */
@Composable
private fun AqiChip(value: Double) {
    val status = AirStatus.of(AirIndexType.AQI, value)
    Text(
        text = value.roundToInt().toString(),
        style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
        color = Color(0xFF000000 or status.foregroundColor.toLong()),
        textAlign = TextAlign.Center,
        modifier = Modifier
            .widthIn(min = 48.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(Color(0xFF000000 or status.color.toLong()))
            .padding(horizontal = 8.dp, vertical = 4.dp)
    )
}

@Composable
private fun Caption(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.fillMaxWidth()
    )
}
