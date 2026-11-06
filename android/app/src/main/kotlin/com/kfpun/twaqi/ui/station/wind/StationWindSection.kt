package com.kfpun.twaqi.ui.station.wind

import android.provider.Settings
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.model.Wind
import com.kfpun.twaqi.data.model.wind
import com.kfpun.twaqi.ui.common.SectionLabel
import com.kfpun.twaqi.ui.common.rgb
import com.kfpun.twaqi.ui.common.secondaryText
import com.kfpun.twaqi.ui.station.StationDetailsUiState
import java.util.Locale
import kotlin.math.PI
import kotlin.math.min
import kotlin.math.sin

/**
 * What the wind section shows (iOS `WindView`), kept apart from drawing so it can be tested.
 */
object StationWind {
    /**
     * The wind to show, or null to hide the section. iOS draws `WindView` only when the station has
     * a current reading (`viewModel.pollutant`); a reading without wind fields is dropped by the
     * parser, so no reading means no wind. A `0 / 0` reading is shown, as "Calm".
     */
    fun of(state: StationDetailsUiState): Wind? = state.pollutant?.wind

    /** 「2.6」: one decimal, always with a full stop (iOS `speed.format(f: ".1")`). */
    fun speed(wind: Wind): String = String.format(Locale.US, "%.1f", wind.speed)

    /**
     * Band colour of the pollutant the page is showing (iOS `DetailsView.selectedTint`), so the
     * arrow matches the highlighted reading and the chart above it.
     */
    fun tint(pollutant: Pollutant, selected: AirIndexType): Int =
        AirStatus.of(selected, pollutant.value(selected)).color

    /**
     * Arrow length in dp: a light air is a stub, a strong breeze nearly spans the rose. Floor and
     * ceiling keep a light air visible and a strong breeze inside the ring.
     */
    fun arrowLength(wind: Wind): Float = SHORTEST + (LONGEST - SHORTEST) * wind.strengthFraction.toFloat()

    /** Seconds per swing: stronger wind wavers faster, but never quickly. */
    fun driftDuration(wind: Wind): Double = 2.4 - 1.0 * wind.strengthFraction

    /** Half the sweep, in degrees: past a few degrees the arrow stops reading as "roughly WSW". */
    fun wobble(wind: Wind): Double = 1.5 + 2.5 * wind.strengthFraction

    private const val SHORTEST = 18f
    private const val LONGEST = 46f
}

/**
 * The station page's wind slot (FOX-101): the wind section for the current reading, tinted with
 * the [selected] pollutant's band colour; nothing when the station has no current reading.
 */
@Composable
fun StationWindSection(state: StationDetailsUiState, selected: AirIndexType, modifier: Modifier = Modifier) {
    val pollutant = state.pollutant ?: return
    val wind = StationWind.of(state) ?: return
    WindSection(wind, rgb(StationWind.tint(pollutant, selected)), modifier)
}

/** Which way the air is moving, and how hard (iOS `WindView`). */
@Composable
fun WindSection(wind: Wind, tint: Color, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxWidth().padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        SectionLabel(stringResource(R.string.details_wind))
        Row(horizontalArrangement = Arrangement.spacedBy(20.dp), verticalAlignment = Alignment.CenterVertically) {
            Compass(wind, tint)
            Readings(wind)
        }
    }
}

/**
 * A compass rose rather than a bare arrow in a ring: without a fixed north mark, the arrow's angle
 * is decoration. Decorative for TalkBack; the readings beside it say the same.
 */
@Composable
private fun Compass(wind: Wind, tint: Color) {
    val ring = secondaryText()
    Box(Modifier.size(72.dp).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(72.dp)) {
            drawCircle(
                ring.copy(alpha = 0.18f),
                radius = size.minDimension / 2 - 0.5.dp.toPx(),
                style = Stroke(1.dp.toPx())
            )
            for (degrees in listOf(0f, 90f, 180f, 270f)) {
                val north = degrees == 0f
                val length = (if (north) 8 else 5).dp.toPx()
                rotate(degrees) {
                    drawLine(
                        ring.copy(alpha = if (north) 0.55f else 0.22f),
                        start = Offset(center.x, center.y - 30.dp.toPx() - length / 2),
                        end = Offset(center.x, center.y - 30.dp.toPx() + length / 2),
                        strokeWidth = 1.5.dp.toPx(),
                        cap = StrokeCap.Round
                    )
                }
            }
        }
        Text(
            "N",
            fontSize = 9.sp,
            fontWeight = FontWeight.SemiBold,
            color = ring,
            modifier = Modifier.offset(y = (-40).dp)
        )
        if (wind.isCalm) {
            Text("—", style = MaterialTheme.typography.titleLarge, color = ring)
        } else {
            Arrow(wind, tint)
        }
    }
}

/**
 * Points the way the air is travelling, its length the speed. It wavers a few degrees either side
 * of the bearing, faster in stronger wind, as a vane hunts in real wind; still when the phone's
 * animations are off (iOS Reduce Motion).
 */
@Composable
private fun Arrow(wind: Wind, tint: Color) {
    val resolver = LocalContext.current.contentResolver
    val animationsOff = remember(resolver) {
        Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
    val periodMillis = (2 * StationWind.driftDuration(wind) * 1000).toInt()
    val phase by rememberInfiniteTransition(label = "wind sway").animateFloat(
        initialValue = 0f,
        targetValue = (2 * PI).toFloat(),
        animationSpec = infiniteRepeatable(tween(periodMillis, easing = LinearEasing), RepeatMode.Restart),
        label = "wind sway phase"
    )
    val wobble = StationWind.wobble(wind).toFloat()
    val length = StationWind.arrowLength(wind)
    Canvas(Modifier.size(72.dp)) {
        val sway = if (animationsOff) 0f else wobble * sin(phase)
        rotate(wind.arrowRotation.toFloat() + sway) { drawArrow(length.dp.toPx(), tint) }
    }
}

/** A shaft with a chevron head, pointing south at rest, so rotating it by the bearing points it downwind. */
private fun DrawScope.drawArrow(length: Float, tint: Color) {
    val x = center.x
    val top = center.y - length / 2
    val tip = center.y + length / 2
    val head = min(11.dp.toPx(), length * 0.5f)
    val halfWidth = min(7.dp.toPx(), length * 0.32f)
    val path = Path().apply {
        moveTo(x, top)
        lineTo(x, tip)
        moveTo(x - halfWidth, tip - head)
        lineTo(x, tip)
        lineTo(x + halfWidth, tip - head)
    }
    drawPath(path, tint, style = Stroke(3.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
}

@Composable
private fun Readings(wind: Wind) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        if (wind.isCalm) {
            Text(
                stringResource(R.string.wind_calm),
                style = MaterialTheme.typography.titleLarge,
                fontSize = 20.sp,
                fontWeight = FontWeight.Medium
            )
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(
                    StationWind.speed(wind),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.alignByBaseline()
                )
                Text(
                    "m/s",
                    style = MaterialTheme.typography.labelSmall,
                    color = secondaryText(),
                    modifier = Modifier.alignByBaseline()
                )
                Text(
                    wind.compassPoint,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = secondaryText(),
                    modifier = Modifier.alignByBaseline()
                )
            }
            Text(
                stringResource(wind.descriptor),
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.Light,
                color = secondaryText()
            )
        }
    }
}
