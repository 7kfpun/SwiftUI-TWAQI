package com.kfpun.twaqi.onboarding

import android.content.Context
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.airbnb.lottie.LottieComposition
import com.airbnb.lottie.LottieCompositionFactory
import com.airbnb.lottie.compose.LottieAnimation
import com.airbnb.lottie.compose.animateLottieCompositionAsState
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.pro.PlanOffer
import com.kfpun.twaqi.pro.ProFeature
import com.kfpun.twaqi.pro.ProGraph
import com.kfpun.twaqi.pro.nameRes
import com.kfpun.twaqi.ui.common.StationRow
import com.kfpun.twaqi.ui.common.StationRowReading
import com.kfpun.twaqi.ui.common.rgb
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** iOS's flow accent (`Color(0x5AC8FA)`), as in [OnboardingScreen]. */
private val Accent = Color(0xFF5AC8FA)

/** The system's animator duration scale: 0 when animations are removed ("Remove animations"). */
internal fun animatorDurationScale(context: Context): Float =
    Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)

/**
 * One animation, played once (iOS `OnboardingAnimationView`). With animations removed it shows its
 * last frame still ([OnboardingMotion]). Decorative: TalkBack skips it. A file that doesn't load
 * leaves the space empty rather than shifting the step. Read from the iOS file as shipped, with
 * its keys put in the order lottie-android reads them ([OnboardingAnimationJson]).
 */
@Composable
internal fun OnboardingAnimationView(animation: OnboardingAnimation, size: Dp, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val still = remember(context) { OnboardingMotion.stillProgress(animatorDurationScale(context)) }
    val composition by produceState<LottieComposition?>(null, animation) {
        value = withContext(Dispatchers.IO) {
            runCatching {
                val json = context.assets.open(animation.assetPath).bufferedReader().use { it.readText() }
                LottieCompositionFactory.fromJsonStringSync(
                    OnboardingAnimationJson.forLottieAndroid(json),
                    animation.assetPath
                ).value
            }.getOrNull()
        }
    }
    Box(modifier.size(size).clearAndSetSemantics {}) {
        if (still != null) {
            LottieAnimation(composition, progress = { still }, modifier = Modifier.fillMaxSize())
        } else {
            val progress by animateLottieCompositionAsState(composition, iterations = 1)
            LottieAnimation(composition, progress = { progress }, modifier = Modifier.fillMaxSize())
        }
    }
}

/** Every station with its current AQI, to search or browse by area (iOS `OnboardingStationPicker`). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun OnboardingStationPicker(
    stations: List<Pollutant>,
    selectedId: Int?,
    onPick: (Pollutant) -> Unit,
    onDismiss: () -> Unit
) {
    val chinese = AppLocale.isChinese(LocalContext.current)
    var query by rememberSaveable { mutableStateOf("") }
    val sections = remember(stations, query, chinese) { OnboardingStationList.sections(stations, query, chinese) }
    FullScreenDialog(onDismiss) {
        Column(Modifier.fillMaxSize().systemBarsPadding()) {
            TopAppBar(
                title = { Text(stringResource(R.string.onboarding_choose_station_title)) },
                navigationIcon = {
                    TextButton(onClick = onDismiss) { Text(stringResource(R.string.onboarding_cancel), color = Accent) }
                }
            )
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                placeholder = { Text(stringResource(R.string.detailslist_search)) },
                leadingIcon = { Icon(painterResource(R.drawable.ic_search), contentDescription = null) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)
            )
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 16.dp)) {
                sections.forEach { section ->
                    item(key = "area-${section.title}") {
                        Text(
                            section.title,
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp)
                                .semantics { heading() }
                        )
                    }
                    items(section.stations, key = { it.stationId }) { station ->
                        val isSelected = station.stationId == selectedId
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .semantics { selected = isSelected }
                                .clickable(role = Role.Button) { onPick(station) }
                                .padding(horizontal = 16.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            if (isSelected) {
                                Icon(
                                    painterResource(R.drawable.ic_check_circle),
                                    contentDescription = null,
                                    tint = Accent,
                                    modifier = Modifier.size(20.dp)
                                )
                                Spacer(Modifier.width(8.dp))
                            }
                            StationRow(
                                title = station.displayName(chinese),
                                subtitle = station.displayLocality(chinese),
                                reading = StationRowReading(station.aqi, publishTime = null),
                                modifier = Modifier.weight(1f)
                            )
                        }
                        HorizontalDivider(
                            modifier = Modifier.padding(start = 16.dp),
                            color = MaterialTheme.colorScheme.outlineVariant
                        )
                    }
                }
            }
        }
    }
}

/**
 * Pro on the last step: what stays free, what Pro adds, and the plans' real prices from Play.
 * Buying happens on the Pro screen only. Play sells no trial (FOX-58), so none is shown.
 */
@Composable
internal fun OnboardingProSummary(isPro: Boolean) {
    val context = LocalContext.current
    var offers by remember { mutableStateOf<List<PlanOffer>?>(null) }
    LaunchedEffect(isPro) {
        if (!isPro && offers == null) offers = ProGraph.repository(context).queryOffers().offers
    }
    val good = rgb(AirStatus.GOOD.color)
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(
            stringResource(R.string.pro_title),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.semantics { heading() }
        )
        if (isPro) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(
                    painterResource(R.drawable.ic_check_circle),
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(20.dp)
                )
                Text(
                    stringResource(R.string.onboarding_premium_active),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            return@Column
        }
        Text(
            stringResource(R.string.onboarding_premium_body),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Tag(stringResource(R.string.onboarding_free_heading), good)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            IconRow(R.drawable.ic_onboarding_mic, stringResource(R.string.onboarding_free_shortcuts), good)
            IconRow(R.drawable.ic_pro_watch, stringResource(R.string.onboarding_free_complication), good)
            IconRow(R.drawable.ic_pro_widgets, stringResource(R.string.onboarding_free_index_cycling), good)
        }

        Tag(stringResource(R.string.onboarding_pro_heading), Accent)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            ProFeature.entries.forEach { feature ->
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(
                        painterResource(feature.icon),
                        contentDescription = null,
                        tint = good,
                        modifier = Modifier.size(28.dp)
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(stringResource(feature.title), style = MaterialTheme.typography.titleSmall)
                        Text(
                            stringResource(feature.detail),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }

        Prices(offers)
    }
}

@Composable
private fun Prices(offers: List<PlanOffer>?) {
    when {
        offers == null -> Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(color = Accent, modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
        }

        // Play unreachable (an emulator without it): the Pro screen has the plans and a retry.
        offers.isEmpty() -> Unit

        else -> Surface(
            shape = RoundedCornerShape(14.dp),
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(Modifier.padding(horizontal = 12.dp)) {
                offers.forEachIndexed { index, offer ->
                    if (index > 0) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    Row(Modifier.fillMaxWidth().padding(vertical = 10.dp).semantics(mergeDescendants = true) {}) {
                        Text(
                            stringResource(offer.plan.nameRes),
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.weight(1f)
                        )
                        Text(
                            offer.formattedPrice,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun Tag(text: String, color: Color) {
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.Bold,
        color = Color.White,
        modifier = Modifier.background(color, RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 3.dp)
    )
}

@Composable
private fun IconRow(icon: Int, text: String, tint: Color) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(painterResource(icon), contentDescription = null, tint = tint, modifier = Modifier.size(28.dp))
        Text(text, style = MaterialTheme.typography.bodyMedium)
    }
}
