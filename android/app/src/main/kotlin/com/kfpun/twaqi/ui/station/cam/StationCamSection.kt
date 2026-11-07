package com.kfpun.twaqi.ui.station.cam

import androidx.annotation.DrawableRes
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.kfpun.twaqi.R
import com.kfpun.twaqi.TwaqiApplication
import com.kfpun.twaqi.data.cams.StationCam
import com.kfpun.twaqi.data.cams.StationCamHour
import com.kfpun.twaqi.data.cams.StationCamState
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.ui.common.Orange
import com.kfpun.twaqi.ui.common.SectionLabel
import com.kfpun.twaqi.ui.common.secondaryText
import com.kfpun.twaqi.ui.station.StationDetailsUiState
import java.time.Instant
import java.time.OffsetDateTime
import kotlin.math.roundToInt
import kotlinx.coroutines.delay

/** MOENV cams are 1920×1080. */
private const val ASPECT_RATIO = 16f / 9f
private val CornerRadius = 12.dp

/** How long the scrubber must rest before its hour loads in full. */
private const val SETTLE_DELAY_MS = 300L

/**
 * The view from the station (iOS `StationCamView`): MOENV's latest webcam frame, with a scrubber
 * back through the past 24 clock hours. The station page's `cam` slot (FOX-55).
 *
 * Sits under the AQI so the number and the sky it describes are read together. Stations without a
 * cam get one quiet line, not an empty frame. Free for everyone, as on iOS.
 */
@Composable
fun StationCamSection(state: StationDetailsUiState, modifier: Modifier = Modifier) {
    val app = LocalContext.current.applicationContext as TwaqiApplication
    val viewModel: StationCamViewModel<ImageBitmap> = viewModel(
        key = "station-cam-${state.stationId}",
        factory = StationCamViewModel.factory(app)
    )
    // Both requests carry the Chinese name and coordinates the join needs; the first match wins.
    val pollutant = state.pollutant
    val station = state.station
    LaunchedEffect(pollutant?.nameLocal, pollutant?.lat, pollutant?.lon) {
        pollutant?.let { viewModel.findCam(it.nameLocal, it.lat, it.lon) }
    }
    LaunchedEffect(station?.nameLocal, station?.lat, station?.lon) {
        station?.let { viewModel.findCam(it.nameLocal, it.lat, it.lon) }
    }
    val cam by viewModel.cam.collectAsStateWithLifecycle()
    // FOX-119: the scrubber's hour lives with the page's view models too, so it follows the page
    // between the full screen and the panel beside the map or a list when a foldable folds or unfolds.
    val scrubber: CamScrubberPosition = viewModel(key = "station-cam-position-${state.stationId}")

    Column(modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionLabel(stringResource(R.string.details_live_cam))
        when (val current = cam) {
            StationCamState.Loading -> CamBox { CamPlaceholder() }

            is StationCamState.Available -> CamFrameView(current.cam, viewModel.frames, viewModel.history, scrubber)

            StationCamState.Missing -> Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    painterResource(R.drawable.ic_cam_video_off),
                    contentDescription = null,
                    tint = secondaryText(),
                    modifier = Modifier.size(16.dp)
                )
                Text(
                    stringResource(R.string.details_no_cam),
                    style = MaterialTheme.typography.bodySmall,
                    color = secondaryText(),
                    modifier = Modifier.padding(start = 6.dp)
                )
            }
        }
    }
}

@Composable
private fun CamFrameView(
    cam: StationCam,
    frames: StationCamFrameLoader<ImageBitmap>,
    history: StationCamHistoryLoader<ImageBitmap>,
    scrubber: CamScrubberPosition
) {
    val frame by frames.state.collectAsStateWithLifecycle()
    val hours by history.state.collectAsStateWithLifecycle()

    // 0 until 24 are the hourly slots, oldest first; 24 is live.
    // Starts from [scrubber], which outlives a move of the page (FOX-119); rememberSaveable covers
    // process death, and SideEffect hands its value back to [scrubber].
    var position by rememberSaveable { mutableFloatStateOf(scrubber.position) }
    SideEffect { scrubber.position = position }
    val selectedIndex = position.roundToInt().takeIf { it < StationCamHour.COUNT }

    // Keyed by the cam, whose capture time versions the frame: a new frame in the manifest loads
    // again, the same one doesn't.
    LaunchedEffect(cam) {
        frames.load(cam)
        history.configure(cam.siteId, cam.capturedAt ?: Instant.now())
        // A new anchor slides the hours under a resting scrubber.
        selectedIndex?.let(history::settle)
    }
    // Each move shows what memory or disk has at once, and settles once the scrubber has rested.
    LaunchedEffect(selectedIndex) {
        if (selectedIndex == null) {
            history.showLive()
            return@LaunchedEffect
        }
        history.preview(selectedIndex, frames.state.value.image)
        delay(SETTLE_DELAY_MS)
        history.settle(selectedIndex)
    }

    val context = LocalContext.current
    val locale = AppLocale.locale(context)
    val now = Instant.now()
    val pickedHour = hours.selected?.takeIf { selectedIndex != null }
    val liveLabel = stringResource(R.string.details_cam_live)
    val liveCam = stringResource(R.string.details_live_cam)

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        CamBox(
            Modifier.semantics(mergeDescendants = true) {
                contentDescription = liveCam
                role = Role.Image
            }
        ) {
            if (selectedIndex == null) LiveFrame(frame) else HistoryFrame(hours)
            if (pickedHour != null) {
                Text(
                    CamTime.clock(pickedHour.hour),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(8.dp)
                        .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.8f), CircleShape)
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                )
            }
        }

        // "Captured 22:30 · 36 min ago · Image: MOENV": of the live frame shown, which offline may
        // be older than the manifest's, or of the picked hour.
        val captured: Instant? = pickedHour?.hour
            ?: (if (frame.image != null) frame.imageTime else cam.time)?.let(::parseCaptureTime)
        Caption(captured, now, locale)

        val accessibilityValue = pickedHour?.let {
            "${CamTime.clock(it.hour)} ${CamTime.relative(it.hour, now, locale)}"
        } ?: liveLabel
        Scrubber(
            position = position,
            onPositionChange = { position = it },
            isLive = selectedIndex == null,
            accessibilityValue = accessibilityValue
        )

        if (selectedIndex == null && frame.refreshFailed && frame.image != null) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    painterResource(R.drawable.ic_station_offline),
                    contentDescription = null,
                    tint = Orange,
                    modifier = Modifier.size(14.dp)
                )
                Text(
                    stringResource(R.string.details_cam_showing_saved),
                    style = MaterialTheme.typography.labelSmall,
                    color = Orange,
                    modifier = Modifier.padding(start = 6.dp)
                )
            }
        }
    }
}

private fun parseCaptureTime(time: String): Instant? = runCatching {
    OffsetDateTime.parse(time).toInstant()
}.getOrNull()

@Composable
private fun BoxScope.LiveFrame(frame: CamFrameState<ImageBitmap>) {
    val image = frame.image
    when {
        image != null -> {
            Crossfade(targetState = image, animationSpec = tween(250), label = "cam frame") {
                Image(
                    it,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize()
                )
            }
            if (frame.isRefreshing) RefreshBadge()
        }

        frame.refreshFailed -> CamMessage(R.drawable.ic_cam_video_off, stringResource(R.string.details_cam_unavailable))

        else -> CamPlaceholder()
    }
}

/**
 * The picked hour. While it loads the last frame stays up, dimmed, rather than a spinner; an hour
 * with no frame says so, and the rest still work.
 */
@Composable
private fun BoxScope.HistoryFrame(hours: CamHistoryState<ImageBitmap>) {
    val image = hours.image
    when {
        hours.selectedState == CamSlotState.MISSING ->
            CamMessage(R.drawable.ic_station_clock, stringResource(R.string.details_cam_hour_missing))

        hours.selectedState == CamSlotState.FAILED ->
            CamMessage(R.drawable.ic_cam_video_off, stringResource(R.string.details_cam_unavailable))

        image != null -> {
            Image(
                image,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().alpha(if (hours.isStandIn) 0.45f else 1f)
            )
            if (hours.isStandIn || hours.selectedState == CamSlotState.LOADING) RefreshBadge()
        }

        else -> CamPlaceholder()
    }
}

/** Past 24 hours on the left, live on the right; whole hours only. */
@Composable
private fun Scrubber(position: Float, onPositionChange: (Float) -> Unit, isLive: Boolean, accessibilityValue: String) {
    val timeline = stringResource(R.string.details_cam_timeline)
    Column {
        Slider(
            value = position,
            onValueChange = onPositionChange,
            valueRange = 0f..StationCamHour.COUNT.toFloat(),
            steps = StationCamHour.COUNT - 1,
            modifier = Modifier.semantics {
                contentDescription = timeline
                stateDescription = accessibilityValue
            }
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.timeline_title),
                style = MaterialTheme.typography.labelSmall,
                color = secondaryText()
            )
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { onPositionChange(StationCamHour.COUNT.toFloat()) }, enabled = !isLive) {
                Text(
                    stringResource(R.string.details_cam_live),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = if (isLive) FontWeight.SemiBold else FontWeight.Normal
                )
            }
        }
    }
}

@Composable
private fun Caption(captured: Instant?, now: Instant, locale: java.util.Locale) {
    val style = MaterialTheme.typography.labelSmall
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(
            painterResource(R.drawable.ic_cam_photo),
            contentDescription = null,
            tint = secondaryText(),
            modifier = Modifier.size(14.dp)
        )
        if (captured != null) {
            Text(
                stringResource(R.string.details_cam_captured, CamTime.clock(captured)),
                style = style,
                fontWeight = FontWeight.Light,
                color = secondaryText(),
                maxLines = 1
            )
            Text(
                "· ${CamTime.relative(captured, now, locale)}",
                style = style,
                fontWeight = FontWeight.Light,
                color = secondaryText().copy(alpha = 0.7f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false)
            )
        }
        Spacer(Modifier.weight(1f).width(8.dp))
        Text(
            stringResource(R.string.details_cam_source),
            style = style,
            fontWeight = FontWeight.Light,
            color = secondaryText(),
            maxLines = 1
        )
    }
}

/** A fixed 16:9 box, so the layout does not jump when the frame arrives. */
@Composable
private fun CamBox(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    Box(
        modifier
            .fillMaxWidth()
            .aspectRatio(ASPECT_RATIO)
            .clip(RoundedCornerShape(CornerRadius))
            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f)),
        contentAlignment = Alignment.Center,
        content = content
    )
}

/** The small spinner in the frame's corner: a newer frame is on its way. */
@Composable
private fun BoxScope.RefreshBadge() {
    Box(
        Modifier
            .align(Alignment.TopEnd)
            .padding(8.dp)
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.8f), CircleShape)
            .padding(6.dp)
    ) {
        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
    }
}

@Composable
private fun CamPlaceholder() {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(
            painterResource(R.drawable.ic_cam_video),
            contentDescription = null,
            tint = secondaryText().copy(alpha = 0.5f),
            modifier = Modifier.size(28.dp)
        )
        CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
    }
}

/** An hour with no frame, or a frame that couldn't load. Only that slot; the others still work. */
@Composable
private fun CamMessage(@DrawableRes icon: Int, text: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(painterResource(icon), contentDescription = null, tint = secondaryText(), modifier = Modifier.size(28.dp))
        Text(text, style = MaterialTheme.typography.bodySmall, color = secondaryText())
    }
}

/**
 * The cam scrubber's position (0 until 24 are the hourly slots, 24 is live), held in the station
 * page's view model store so the picked hour survives the page moving between the full screen and
 * the panel beside the map or a list (FOX-119).
 */
class CamScrubberPosition : ViewModel() {
    var position: Float = StationCamHour.COUNT.toFloat()
}
