package com.kfpun.twaqi.shortcuts

import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.net.toUri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.kfpun.twaqi.R
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.ui.common.rgb
import com.kfpun.twaqi.ui.navigation.DeepLink
import com.kfpun.twaqi.ui.navigation.KnownStations
import com.kfpun.twaqi.ui.navigation.StationLinkSource
import com.kfpun.twaqi.ui.station.faceImage
import com.kfpun.twaqi.ui.theme.TWAQITheme
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * "What's the air?" (FOX-95, iOS `GetAirQualityIntent`): a card over whatever was on screen with
 * the AQI of the nearest station (or a favourite), its level, the main pollutant and what to do,
 * in the same words Siri says ([AirQualityAnswer]). Opened by `twaqi://air-quality` through
 * [DeepLink]: the "Air quality" launcher shortcut and Google Assistant. "Open station" goes on to
 * the station's page; a tap outside closes it.
 */
class AirQualityAnswerActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val link = DeepLink.parse(intent.data) as? DeepLink.AirQuality ?: DeepLink.AirQuality(null)
        setContent {
            TWAQITheme {
                val model: AirQualityAnswerViewModel = viewModel()
                LaunchedEffect(link) { model.start(link) }
                val state by model.state.collectAsStateWithLifecycle()
                AnswerScreen(
                    state = state,
                    onClose = ::finish,
                    onOpenStation = { stationId ->
                        startActivity(DeepLink.stationIntent(this, stationId, StationLinkSource.SHORTCUT))
                        finish()
                    }
                )
            }
        }
    }

    companion object {
        /** Opens the card for [stationId], or the nearest station. */
        fun intent(context: Context, stationId: Int? = null): Intent = Intent(
            Intent.ACTION_VIEW,
            DeepLink.airQualityUri(stationId).toUri(),
            context,
            AirQualityAnswerActivity::class.java
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
}

/** What the card shows. */
sealed interface AnswerState {
    data object Loading : AnswerState

    data class Answered(val reading: Pollutant?, val text: String, val chinese: Boolean) : AnswerState
}

/** Looks the answer up once per card, surviving rotation, and logs it as iOS does. */
class AirQualityAnswerViewModel(application: Application) : AndroidViewModel(application) {
    private val mutableState = MutableStateFlow<AnswerState>(AnswerState.Loading)
    val state: StateFlow<AnswerState> = mutableState.asStateFlow()
    private var started = false

    fun start(link: DeepLink.AirQuality) {
        if (started) return
        started = true
        val app = getApplication<Application>()
        viewModelScope.launch {
            // The router drops a station the app has never seen; the card then answers for the nearest.
            val known = link.stationId?.let { KnownStations.contains(app, it) } ?: true
            val requested = (DeepLink.route(link, isPro = false) { known } as? DeepLink.AirQuality)?.stationId
            val result = AirQualityLookup.create(app).lookup(requested)
            val strings = AnswerStrings.from(app)
            mutableState.value = AnswerState.Answered(
                reading = result.reading,
                text = AirQualityAnswer.text(result.reading, result.freshness, result.note, strings),
                chinese = strings.chinese
            )
            Analytics.logEvent(
                app,
                Analytics.APP_INTENT_RUN,
                mapOf(
                    "intent" to "get_air_quality",
                    "station" to result.kind,
                    "result" to when {
                        result.reading == null -> "none"
                        result.freshness == AnswerFreshness.LIVE -> "live"
                        else -> "cached"
                    }
                )
            )
        }
    }
}

@Composable
private fun AnswerScreen(state: AnswerState, onClose: () -> Unit, onOpenStation: (Int) -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.4f))
            .clickable(
                interactionSource = remember {
                    MutableInteractionSource()
                },
                indication = null,
                onClick = onClose
            )
            .safeDrawingPadding()
            .padding(24.dp),
        contentAlignment = Alignment.Center
    ) {
        Surface(
            shape = RoundedCornerShape(20.dp),
            tonalElevation = 6.dp,
            modifier = Modifier
                .widthIn(max = 420.dp)
                .fillMaxWidth()
                // Taps on the card stay on the card.
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {}
        ) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    stringResource(R.string.intent_get_air_quality_title),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.semantics { heading() }
                )
                when (state) {
                    AnswerState.Loading -> Box(Modifier.fillMaxWidth().padding(24.dp), Alignment.Center) {
                        CircularProgressIndicator()
                    }

                    is AnswerState.Answered -> {
                        state.reading?.takeIf { it.status(AirIndexType.AQI) != AirStatus.UNKNOWN }?.let {
                            ReadingCard(it, state.chinese)
                        }
                        Text(state.text, style = MaterialTheme.typography.bodyLarge)
                    }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = onClose) { Text(stringResource(R.string.intent_answer_close)) }
                    val stationId = (state as? AnswerState.Answered)?.reading?.stationId
                    if (stationId != null) {
                        TextButton(onClick = { onOpenStation(stationId) }) {
                            Text(stringResource(R.string.intent_open_station_title))
                        }
                    }
                }
            }
        }
    }
}

/** The face, the station, the level and the AQI on the level's colour (iOS `AirQualitySnippetView`). */
@Composable
private fun ReadingCard(reading: Pollutant, chinese: Boolean) {
    val status = reading.status(AirIndexType.AQI)
    val foreground = rgb(status.foregroundColor)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(rgb(status.color))
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        status.faceImage()?.let {
            Image(painterResource(it), contentDescription = null, modifier = Modifier.size(56.dp))
            Spacer(Modifier.size(14.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(
                AirQualityAnswer.name(reading, chinese),
                color = foreground,
                style = MaterialTheme.typography.titleMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                stringResource(status.label),
                color = foreground,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2
            )
        }
        Column(horizontalAlignment = Alignment.End) {
            Text("AQI", color = foreground.copy(alpha = 0.8f), style = MaterialTheme.typography.labelMedium)
            Text(
                AirIndexType.AQI.format(reading.aqi),
                color = foreground,
                fontSize = 40.sp,
                fontWeight = FontWeight.Bold
            )
        }
    }
}
