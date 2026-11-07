package com.kfpun.twaqi.ui.main

import androidx.annotation.DrawableRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.locale.AppLocale

/** The selected pill and the map buttons' tint (iOS `IndexSelectorView.accent`). */
val MapAccent = Color(0xFF5AC8FA)

/** Width shared by the closest-station card and the air status bar (iOS `ClosestStationView.preferredSize`). */
private val CardWidth = 232.dp

/** `0xRRGGBB` as a Compose colour. */
fun rgb(color: Int): Color = Color(0xFF000000 or color.toLong())

/** The face for a band; none for [AirStatus.UNKNOWN]. */
@DrawableRes
fun faceImage(status: AirStatus): Int? = when (status) {
    AirStatus.GOOD -> R.drawable.status_good
    AirStatus.MODERATE -> R.drawable.status_moderate
    AirStatus.UNHEALTHY_FOR_SENSITIVE_GROUP -> R.drawable.status_unhealthyforsensitivegroup
    AirStatus.UNHEALTHY -> R.drawable.status_unhealthy
    AirStatus.VERY_UNHEALTHY -> R.drawable.status_veryunhealthy
    AirStatus.HAZARDOUS -> R.drawable.status_hazardous
    AirStatus.UNKNOWN -> null
}

/** "AQI 54" on the band colour, as on the closest-station card and the list rows. */
@Composable
fun ValuePill(type: AirIndexType, value: Double, modifier: Modifier = Modifier) {
    val status = AirStatus.of(type, value)
    val text = if (value != 0.0) type.format(value) else "-"
    Box(
        modifier = modifier
            .widthIn(min = 56.dp)
            // Grows with the font scale rather than clipping the text (FOX-112).
            .heightIn(min = 24.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(rgb(status.color))
            .padding(horizontal = 6.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = "${type.label} $text",
            color = rgb(status.foregroundColor),
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1
        )
    }
}

/**
 * Floating card for the station nearest the map centre (iOS `ClosestStationView`): name,
 * locality, status and last update on the left; the value pill and the health face on the right.
 * Tapping it opens the station when it is in the supported country.
 *
 * @param lastGood the reading is the last saved one, because the latest request failed: says so
 *   with its age instead of a bare clock time.
 * @param timelineContext set while the map timeline is scrubbed back, e.g. 「昨天 17:00・24 小時前」.
 *   Replaces "Last updated HH:mm", which reads the same 24 hours ago as it does now.
 */
@Composable
fun ClosestStationCard(
    pollutant: Pollutant,
    type: AirIndexType,
    lastGood: Boolean,
    onClick: (() -> Unit)?,
    modifier: Modifier = Modifier,
    timelineContext: String? = null
) {
    val context = LocalContext.current
    val chinese = AppLocale.isChinese(context)
    val value = pollutant.value(type)
    val status = AirStatus.of(type, value)
    Surface(
        modifier = modifier
            .width(CardWidth)
            // iOS's 96 pt at the default font size; taller when its lines need it (FOX-112), so the
            // last line ("Last updated 11:00", the timeline's hour) is never cut off.
            .heightIn(min = 96.dp)
            .let { if (onClick != null) it.clickable(role = Role.Button, onClick = onClick) else it },
        shape = RoundedCornerShape(10.dp),
        color = MaterialTheme.colorScheme.surface,
        shadowElevation = 4.dp
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(
                modifier = Modifier.weight(1f).padding(start = 12.dp, end = 4.dp, top = 8.dp, bottom = 8.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = maxLength(pollutant.displayName(chinese), 16),
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                pollutant.displayLocality(chinese)?.let {
                    Text(
                        text = maxLength(it, 22),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Light,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                Text(text = maxLength(stringResource(status.label), 20), fontSize = 12.sp, maxLines = 1)
                if (timelineContext != null) {
                    Text(
                        text = timelineContext,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Light,
                        maxLines = 1,
                        modifier = Modifier.padding(top = 3.dp)
                    )
                } else {
                    UpdatedLabel(pollutant, lastGood, Modifier.padding(top = 3.dp))
                }
            }
            Column(
                // At least iOS's 72 dp; a longer reading ("PM2.5 21") takes what it needs.
                modifier = Modifier
                    .widthIn(min = 72.dp)
                    .align(Alignment.Top)
                    .padding(top = 12.dp, end = 8.dp, bottom = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                ValuePill(type, value)
                faceImage(status)?.let {
                    Image(
                        painter = painterResource(it),
                        contentDescription = null,
                        modifier = Modifier.padding(top = 8.dp).size(36.dp)
                    )
                }
            }
        }
    }
}

/** "Last updated 14:00", or "Offline · updated 2 hr. ago" in orange for a last good reading. */
@Composable
fun UpdatedLabel(pollutant: Pollutant, lastGood: Boolean, modifier: Modifier = Modifier) {
    val publishedAt = pollutant.publishedAt ?: return
    if (lastGood) {
        Text(
            text = stringResource(R.string.offline_updated_ago, PublishTimes.relativeAge(publishedAt)),
            fontSize = 10.sp,
            fontWeight = FontWeight.Light,
            color = OfflineOrange,
            maxLines = 1,
            modifier = modifier
        )
    } else {
        Text(
            text = "${stringResource(R.string.details_last_updated)} ${PublishTimes.clock(publishedAt)}",
            fontSize = 10.sp,
            fontWeight = FontWeight.Light,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            modifier = modifier
        )
    }
}

/** iOS `.systemOrange`. */
val OfflineOrange = Color(0xFFFF9500)

/** The six faces with their colours, under the closest-station card (iOS `AirStatusBarView`). */
@Composable
fun AirStatusBar(modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.width(CardWidth).height(32.dp),
        shape = RoundedCornerShape(5.dp),
        color = MaterialTheme.colorScheme.surface,
        shadowElevation = 2.dp
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            AirStatus.showAllCases.forEach { status ->
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    faceImage(status)?.let {
                        Image(
                            painterResource(it),
                            contentDescription = stringResource(status.label),
                            Modifier.size(20.dp)
                        )
                    }
                    Spacer(Modifier.height(1.dp))
                    Box(
                        Modifier
                            .width(20.dp)
                            .height(3.dp)
                            .clip(RoundedCornerShape(2.dp))
                            .background(rgb(status.color))
                    )
                }
            }
        }
    }
}

/**
 * The index picker above the map's bottom edge (iOS `IndexSelectorView`): centred at its natural
 * width when there is room, otherwise full width and scrolling. The selected pill is filled with
 * the accent colour, so it reads at a glance over a busy map.
 */
@Composable
fun IndexSelector(selected: AirIndexType, onSelect: (AirIndexType) -> Unit, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.fillMaxWidth().height(54.dp), contentAlignment = Alignment.Center) {
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 15.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            AirIndexType.entries.forEach { type ->
                val isSelected = type == selected
                Surface(
                    modifier = Modifier
                        .width(if (type == AirIndexType.AQI) 62.dp else 72.dp)
                        .height(42.dp)
                        .semantics { this.selected = isSelected },
                    shape = RoundedCornerShape(21.dp),
                    color = if (isSelected) MapAccent else MaterialTheme.colorScheme.surface,
                    contentColor = if (isSelected) Color.White else MaterialTheme.colorScheme.onSurface,
                    shadowElevation = 3.dp,
                    onClick = { onSelect(type) }
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Text(type.label, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                    }
                }
            }
        }
    }
}

/** A round 60 dp map button with an accent icon (iOS `MyLocationButton`, `DefaultLocationButton`). */
@Composable
fun MapRoundButton(
    @DrawableRes icon: Int,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        onClick = onClick,
        modifier = modifier.size(60.dp),
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surface,
        shadowElevation = 4.dp
    ) {
        Box(contentAlignment = Alignment.Center) {
            Icon(painterResource(icon), contentDescription = contentDescription, tint = MapAccent)
        }
    }
}

/**
 * The wind mode toggle (iOS `WindModeButton`): a round 60 dp button, filled with the accent and a
 * white icon while on, the plain card colour while off.
 */
@Composable
fun WindModeButton(isWindMode: Boolean, onToggle: () -> Unit, modifier: Modifier = Modifier) {
    Surface(
        checked = isWindMode,
        onCheckedChange = { onToggle() },
        modifier = modifier.size(60.dp),
        shape = CircleShape,
        color = if (isWindMode) MapAccent else MaterialTheme.colorScheme.surface,
        shadowElevation = 4.dp
    ) {
        Box(contentAlignment = Alignment.Center) {
            Icon(
                painterResource(R.drawable.ic_map_wind),
                contentDescription = stringResource(R.string.details_wind),
                tint = if (isWindMode) Color.White else MaterialTheme.colorScheme.onSurface
            )
        }
    }
}

/** iOS `maxLength`: cuts at [length] characters and adds "...". */
internal fun maxLength(text: String, length: Int): String =
    if (text.length >= length) text.take(length) + "..." else text

/**
 * Where the wind button goes (FOX-112). It sits bottom left above the index bar, as on iOS, unless
 * that would put it over the closest-station card or the level legend, which happens in landscape
 * and at large font sizes: then it moves to the right, beside the location buttons, where there is
 * room across the width.
 */
object MapButtonsLayout {
    /**
     * @param overlayBottom bottom of the card and legend, in px in window coordinates; 0 before
     *   the first layout.
     * @param buttonRowBottom bottom of the map buttons' row, in the same coordinates.
     * @param buttonHeight the wind button's height; [gap] the space kept above it.
     */
    fun windBesideLocationButtons(
        overlayBottom: Float,
        buttonRowBottom: Float,
        buttonHeight: Float,
        gap: Float
    ): Boolean = overlayBottom > 0f && buttonRowBottom > 0f && buttonRowBottom - buttonHeight - gap < overlayBottom
}
