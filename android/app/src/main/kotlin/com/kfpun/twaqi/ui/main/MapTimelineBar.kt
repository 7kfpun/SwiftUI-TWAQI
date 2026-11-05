package com.kfpun.twaqi.ui.main

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kfpun.twaqi.R
import kotlin.math.roundToInt

/** One row tall, so the map keeps the room (iOS `MapTimelineView.preferredHeight`). */
private val BarHeight = 38.dp

/**
 * iOS's time column, wide enough for 「昨天 22:00」. The bar widens it to the app language's widest
 * clock ("Yesterday 22:00" in English), so the track still doesn't shift as the hour changes.
 */
private val TimeColumnWidth = 70.dp

private val TrackY = 14.dp
private val ThumbSize = 14.dp
private const val TABULAR = "tnum"
private val ClockStyle = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold, fontFeatureSettings = TABULAR)

/**
 * The map's bottom bar for scrubbing back through the past 24 hours (iOS `MapTimelineView`): play,
 * the selected hour, then the track.
 *
 * Hourly steps only: readings are published on the hour, so a continuous slider would only ever
 * show the same map between ticks. Disabled until the latest publish time ([anchor]) is known.
 *
 * @param hoursAgo hours before the latest reading the map is showing; 0 is live.
 * @param progress stations loaded out of those in view, while any are outstanding. Shown in place
 *   of 「N 小時前」 until they're in.
 * @param onInteractionBegan a finger came down on the track, before any change.
 */
@Composable
fun MapTimelineBar(
    anchor: String?,
    hoursAgo: Int,
    playing: Boolean,
    progress: HistoryProgress?,
    onInteractionBegan: () -> Unit,
    onChange: (Int) -> Unit,
    onPlay: () -> Unit,
    modifier: Modifier = Modifier
) {
    val description = anchor?.let { MapTimeline.describe(it, hoursAgo) }
    val clock = description?.let { timelineClock(it) } ?: stringResource(R.string.timeline_title)
    val relative = description?.let { timelineRelative(it) }
    val detail = if (progress != null && progress.isLoading) {
        stringResource(R.string.timeline_loading, progress.done, progress.total)
    } else {
        relative.orEmpty()
    }

    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val widestClock = "${stringResource(R.string.timeline_yesterday)} 22:00"
    val timeColumnWidth = remember(widestClock, density) {
        val measured = measurer.measure(widestClock, ClockStyle).size.width
        maxOf(TimeColumnWidth, with(density) { measured.toDp() } + 2.dp)
    }

    Surface(
        modifier = modifier.widthIn(max = 560.dp).fillMaxWidth().height(BarHeight),
        shape = RoundedCornerShape(BarHeight / 2),
        color = MaterialTheme.colorScheme.surface,
        shadowElevation = 4.dp
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.width(6.dp))
            PlayButton(playing = playing, enabled = anchor != null, onClick = onPlay)
            Spacer(Modifier.width(8.dp))
            Column(Modifier.width(timeColumnWidth).semantics(mergeDescendants = true) {}) {
                Text(text = clock, style = ClockStyle, maxLines = 1)
                Text(
                    text = detail,
                    fontSize = 10.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = TextStyle(fontFeatureSettings = TABULAR),
                    maxLines = 1
                )
            }
            Spacer(Modifier.width(2.dp))
            TimelineTrack(
                anchor = anchor,
                hoursAgo = hoursAgo,
                stateText = listOfNotNull(description?.let { clock }, relative).joinToString(" "),
                onInteractionBegan = onInteractionBegan,
                onChange = onChange,
                modifier = Modifier.weight(1f).fillMaxHeight()
            )
            Spacer(Modifier.width(10.dp))
        }
    }
}

/** 「昨天 17:00」 or 「17:00」. */
@Composable
fun timelineClock(hour: TimelineHour): String =
    if (hour.yesterday) "${stringResource(R.string.timeline_yesterday)} ${hour.clock}" else hour.clock

/** 「3 小時前」, or 「最新」 at the latest reading. */
@Composable
fun timelineRelative(hour: TimelineHour): String = if (hour.hoursAgo == 0) {
    stringResource(R.string.timeline_latest)
} else {
    stringResource(R.string.timeline_hours_ago, hour.hoursAgo)
}

@Composable
private fun PlayButton(playing: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val label = stringResource(if (playing) R.string.timeline_pause else R.string.timeline_play)
    Box(
        modifier = Modifier
            .size(26.dp)
            .alpha(if (enabled) 1f else 0.4f)
            .clip(CircleShape)
            .background(MapAccent)
            .clickable(enabled = enabled, role = Role.Button, onClickLabel = label, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center
    ) {
        Icon(
            painter = painterResource(if (playing) R.drawable.ic_timeline_pause else R.drawable.ic_timeline_play),
            contentDescription = null,
            tint = Color.White,
            modifier = Modifier.size(16.dp)
        )
    }
}

/**
 * The hour ticks, their labels and the thumb. Index 0 is 24 hours ago at the left; index 24 is the
 * latest reading at the right. A tap jumps to an hour and a drag scrubs, with one handler; TalkBack
 * adjusts it as a slider.
 */
@Composable
private fun TimelineTrack(
    anchor: String?,
    hoursAgo: Int,
    stateText: String,
    onInteractionBegan: () -> Unit,
    onChange: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val steps = MapTimeline.HOURS
    val index = MapTimeline.index(hoursAgo)
    val animatedIndex by animateFloatAsState(index.toFloat(), tween(150), label = "timelineThumb")
    val haptics = LocalHapticFeedback.current
    val currentHoursAgo by rememberUpdatedState(hoursAgo)
    val began by rememberUpdatedState(onInteractionBegan)
    val changed by rememberUpdatedState(onChange)
    val measurer = rememberTextMeasurer()
    val nowText = stringResource(R.string.timeline_now)
    val ticks = remember(anchor, nowText) {
        anchor?.let(MapTimeline::tickLabels).orEmpty() + TimelineTick(steps, nowText)
    }
    val majorTicks = remember(ticks) { ticks.map { it.index }.toSet() }
    val labelColor = MaterialTheme.colorScheme.onSurfaceVariant
    val railColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f)
    val labelStyle = TextStyle(
        fontSize = 9.sp,
        fontWeight = FontWeight.Medium,
        color = labelColor,
        fontFeatureSettings = TABULAR
    )
    val accessibilityLabel = stringResource(R.string.timeline_accessibility_label)

    fun select(newHoursAgo: Int) {
        if (newHoursAgo == currentHoursAgo) return
        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        changed(newHoursAgo)
    }

    Canvas(
        modifier = modifier
            .semantics {
                contentDescription = accessibilityLabel
                stateDescription = stateText
                progressBarRangeInfo = ProgressBarRangeInfo(index.toFloat(), 0f..steps.toFloat(), steps - 1)
                if (anchor != null) {
                    setProgress { value ->
                        began()
                        changed(MapTimeline.hoursAgo(value.roundToInt()))
                        true
                    }
                }
            }
            .pointerInput(anchor != null) {
                if (anchor == null) return@pointerInput
                val inset = ThumbSize.toPx() / 2 + 2.dp.toPx()
                fun indexAt(x: Float): Int {
                    val fraction = (x - inset) / (size.width - inset * 2).coerceAtLeast(1f)
                    return (fraction * steps).roundToInt().coerceIn(0, steps)
                }
                awaitEachGesture {
                    val down = awaitFirstDown()
                    began()
                    select(MapTimeline.hoursAgo(indexAt(down.position.x)))
                    down.consume()
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id } ?: break
                        if (!change.pressed) break
                        select(MapTimeline.hoursAgo(indexAt(change.position.x)))
                        change.consume()
                    }
                }
            }
    ) {
        val inset = ThumbSize.toPx() / 2 + 2.dp.toPx()
        val trackWidth = size.width - inset * 2
        val trackY = TrackY.toPx()
        fun x(i: Float) = inset + trackWidth * i / steps
        val railHeight = 4.dp.toPx()
        val radius = CornerRadius(railHeight / 2)

        drawRoundRect(railColor, Offset(inset, trackY - railHeight / 2), Size(trackWidth, railHeight), radius)

        // Ticks first, so the filled stretch reads as one bar over them.
        for (tick in 0..steps) {
            val major = tick in majorTicks
            val height = (if (major) 7 else 4).dp.toPx()
            drawRect(
                color = if (major) labelColor else labelColor.copy(alpha = 0.45f),
                topLeft = Offset(x(tick.toFloat()) - 0.5.dp.toPx(), trackY - height / 2),
                size = Size(1.dp.toPx(), height)
            )
        }

        // From the selected hour up to now: the stretch the map has stepped back over.
        val selected = x(animatedIndex)
        drawRoundRect(
            MapAccent.copy(alpha = 0.55f),
            Offset(selected, trackY - railHeight / 2),
            Size(x(steps.toFloat()) - selected, railHeight),
            radius
        )

        for (tick in ticks) {
            val layout = measurer.measure(tick.text, labelStyle)
            // The end label ("Now") hangs left of its tick rather than off the bar.
            val left = (x(tick.index.toFloat()) - layout.size.width / 2f)
                .coerceIn(0f, (size.width - layout.size.width).coerceAtLeast(0f))
            drawText(layout, topLeft = Offset(left, trackY + 6.dp.toPx()))
        }

        val thumbRadius = ThumbSize.toPx() / 2
        val center = Offset(selected, trackY)
        drawCircle(Color.Black.copy(alpha = 0.18f), thumbRadius + 0.5.dp.toPx(), center + Offset(0f, 1.dp.toPx()))
        drawCircle(Color.White, thumbRadius, center)
        drawCircle(MapAccent, thumbRadius - 1.5.dp.toPx(), center, style = Stroke(3.dp.toPx()))
    }
}
