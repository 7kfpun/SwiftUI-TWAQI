package com.kfpun.twaqi.watch.ui

import android.content.Intent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.concurrent.futures.await
import androidx.core.net.toUri
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
import androidx.wear.compose.material3.Icon
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.Text
import androidx.wear.remote.interactions.RemoteActivityHelper
import com.kfpun.twaqi.data.model.AirLevel
import com.kfpun.twaqi.watch.R
import com.kfpun.twaqi.watch.relay.PhoneRelay
import kotlinx.coroutines.launch

/** The phone's Pro screen, `source=watch` for the `pro_screen_opened` funnel (FOX-58). */
private const val PHONE_PRO_LINK = "twaqi://pro?source=watch"

private enum class PaywallStatus { IDLE, OPENING, OPENED_ON_PHONE, PHONE_UNAVAILABLE, RESTORING, NOT_FOUND }

/**
 * Pro on the watch (iOS `PaywallView`): the app and the face complication are free; the
 * complication's number, its other styles and the tile are not (FOX-63).
 *
 * Pro is sold and kept by the phone's Play Billing (FOX-58), so "Subscribe" opens the phone's Pro
 * screen, and "Restore purchase" re-reads what the phone last told the watch.
 */
@Composable
fun PaywallScreen(model: WatchModel, onUnlocked: () -> Unit) {
    val state by model.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val listState = rememberScalingLazyListState()
    var status by remember { mutableStateOf(PaywallStatus.IDLE) }
    val busy = status == PaywallStatus.OPENING || status == PaywallStatus.RESTORING

    LaunchedEffect(state.isPro) { if (state.isPro) onUnlocked() }

    ScreenScaffold(scrollState = listState) { padding ->
        ScalingLazyColumn(state = listState, contentPadding = padding, modifier = Modifier.fillMaxSize()) {
            item {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        painterResource(R.drawable.ic_pro_watch),
                        contentDescription = null,
                        tint = AirLevel.GOOD.composeColor(),
                        modifier = Modifier.size(28.dp)
                    )
                    Text(
                        stringResource(R.string.watch_pro_title),
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center
                    )
                }
            }
            // What Pro adds on the watch; the phone's Pro screen lists the full set.
            item { Feature(R.drawable.ic_pro_watch, R.string.watch_pro_feature_complications) }
            item { Feature(R.drawable.ic_pro_widgets, R.string.watch_pro_feature_indices) }
            item { Feature(R.drawable.ic_pro_ad_off, R.string.watch_pro_feature_no_ads) }
            item {
                Button(
                    onClick = {
                        status = PaywallStatus.OPENING
                        scope.launch {
                            val intent = Intent(
                                Intent.ACTION_VIEW,
                                PHONE_PRO_LINK.toUri()
                            ).addCategory(Intent.CATEGORY_BROWSABLE)
                            status = runCatching { RemoteActivityHelper(context).startRemoteActivity(intent).await() }
                                .fold({ PaywallStatus.OPENED_ON_PHONE }, { PaywallStatus.PHONE_UNAVAILABLE })
                        }
                    },
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth(),
                    icon = { Icon(painterResource(R.drawable.ic_open_in_new), contentDescription = null) }
                ) { Text(stringResource(R.string.watch_pro_open_on_phone)) }
            }
            item {
                Button(
                    onClick = {
                        status = PaywallStatus.RESTORING
                        scope.launch {
                            PhoneRelay.refreshFromPhone(context)
                            // Unlocking leaves the screen (above); still here means nothing was found.
                            status = PaywallStatus.NOT_FOUND
                        }
                    },
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.filledTonalButtonColors()
                ) { Text(stringResource(R.string.help_restore_purchase)) }
            }
            val note = when (status) {
                PaywallStatus.OPENED_ON_PHONE -> R.string.watch_pro_continue_on_phone
                PaywallStatus.PHONE_UNAVAILABLE -> R.string.watch_pro_phone_unavailable
                PaywallStatus.NOT_FOUND -> R.string.watch_pro_failed
                else -> null
            }
            if (note != null) {
                item {
                    Text(
                        stringResource(note),
                        fontSize = 12.sp,
                        textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
        }
    }
}

@Composable
private fun Feature(icon: Int, text: Int) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Icon(painterResource(icon), contentDescription = null, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Text(stringResource(text), fontSize = 13.sp)
    }
}
