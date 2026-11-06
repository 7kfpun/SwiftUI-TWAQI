package com.kfpun.twaqi.ui.settings

import android.app.TimePickerDialog
import android.text.format.DateFormat
import androidx.compose.foundation.clickable
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import com.kfpun.twaqi.R
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.push.DndWindow
import com.kfpun.twaqi.push.PushDevicePayload
import com.kfpun.twaqi.push.PushGraph
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/**
 * Help › Do Not Disturb (iOS `HelpView.doNotDisturbSection`): quiet hours for alerts, which the
 * sender honours, and "cancel all" for every station's alerts. The welcome flow's notifications
 * step (FOX-96) shows the quiet hours only ([showsCancelAll] false).
 */
@Composable
fun DoNotDisturbRows(showsCancelAll: Boolean = true) {
    val context = LocalContext.current
    val graph = remember(context) { PushGraph.get(context) }
    var window by remember { mutableStateOf(graph.sync.dnd) }
    var showCancelled by rememberSaveable { mutableStateOf(false) }

    fun save(new: DndWindow, event: String) {
        window = new
        graph.sync.dndChanged(new)
        Analytics.logEvent(context, event, dndParameters(new))
    }

    ListItem(
        headlineContent = { Text(stringResource(R.string.help_turn_on_do_not_disturb)) },
        trailingContent = {
            Switch(checked = window.enabled, onCheckedChange = {
                save(window.copy(enabled = it), Analytics.SET_DND_NOTIFICATION)
            })
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent)
    )
    if (window.enabled) {
        TimeRow(stringResource(R.string.help_start_time), window.start) {
            save(window.copy(start = it), Analytics.SET_DND_NOTIFICATION_START_TIME)
        }
        TimeRow(stringResource(R.string.help_end_time), window.end) {
            save(window.copy(end = it), Analytics.SET_DND_NOTIFICATION_END_TIME)
        }
    }
    if (!showsCancelAll) return
    ListItem(
        headlineContent = {
            Text(stringResource(R.string.help_cancel_site_notification), color = MaterialTheme.colorScheme.error)
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.clickable(role = Role.Button) {
            graph.favouriteAlerts.cancelAll()
            Analytics.logEvent(context, Analytics.FAVOURITE_STATION_ALL_REMOVED)
            showCancelled = true
        }
    )
    if (showCancelled) {
        AlertDialog(
            onDismissRequest = { showCancelled = false },
            title = { Text(stringResource(R.string.help_all_site_notification_has_been_cancelled)) },
            confirmButton = {
                TextButton(onClick = { showCancelled = false }) { Text(stringResource(R.string.favourites_ok)) }
            }
        )
    }
}

@Composable
private fun TimeRow(label: String, time: LocalTime, onPick: (LocalTime) -> Unit) {
    val context = LocalContext.current
    val formatter =
        remember(context) { DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(AppLocale.locale(context)) }
    ListItem(
        headlineContent = { Text(label, fontWeight = FontWeight.Light) },
        trailingContent = { Text(time.format(formatter), color = MaterialTheme.colorScheme.primary) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.clickable(role = Role.Button) {
            TimePickerDialog(
                context,
                { _, hour, minute -> onPick(LocalTime.of(hour, minute)) },
                time.hour,
                time.minute,
                DateFormat.is24HourFormat(context)
            ).show()
        }
    )
}

/** iOS logs the window as "HH:mm" with every change, with `label` on / off. */
internal fun dndParameters(window: DndWindow): Map<String, String> = mapOf(
    "label" to if (window.enabled) "on" else "off",
    "dndStartTime" to PushDevicePayload.hourMinute(window.start),
    "dndEndTime" to PushDevicePayload.hourMinute(window.end)
)
