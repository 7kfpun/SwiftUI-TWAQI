package com.kfpun.twaqi.ui.station.share

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.ui.common.rgb
import com.kfpun.twaqi.ui.station.PublishTime
import com.kfpun.twaqi.ui.station.faceImage

/**
 * What each shape has room for (iOS `ShareCardView.Metrics`). The square drops the locality and the
 * guidance rather than squeezing them; the story has room to spare.
 */
internal data class ShareCardMetrics(
    val padding: Dp,
    val titleSize: TextUnit,
    val titleLines: Int,
    val showsLocality: Boolean,
    val numberSize: TextUnit,
    val faceSize: Dp,
    val readingSize: TextUnit,
    val guidanceLines: Int,
    val iconSize: Dp
) {
    companion object {
        fun of(shape: ShareCardShape): ShareCardMetrics = when (shape) {
            ShareCardShape.FEED -> ShareCardMetrics(24.dp, 26.sp, 2, true, 84.sp, 76.dp, 20.sp, 2, 28.dp)
            ShareCardShape.STORY -> ShareCardMetrics(28.dp, 30.sp, 3, true, 112.sp, 100.dp, 22.sp, 4, 36.dp)
            ShareCardShape.SQUARE -> ShareCardMetrics(20.dp, 22.sp, 2, false, 64.sp, 60.dp, 18.sp, 0, 24.dp)
        }
    }
}

/**
 * The image a station is shared as (iOS `ShareCardView`): one reading, legible at a glance in a
 * chat thread or a story, with no app chrome around it.
 *
 * Laid out at a fixed size per shape and rendered off screen, so it depends on nothing from the
 * live screen: no font scale (the caller sets the density), no dark theme, no insets.
 */
@Composable
fun ShareCard(content: ShareCardContent, shape: ShareCardShape, modifier: Modifier = Modifier) {
    val status = AirStatus.of(AirIndexType.AQI, content.aqi)
    val foreground = rgb(status.foregroundColor)
    val background = rgb(status.color)
    val hasReading = content.aqi > 0
    val metrics = ShareCardMetrics.of(shape)
    val locale = AppLocale.locale(LocalContext.current)

    Column(
        modifier
            .requiredSize(shape.widthDp.dp, shape.heightDp.dp)
            .clipToBounds()
            .drawBehind {
                drawRect(Color.Black)
                drawRect(
                    Brush.linearGradient(
                        listOf(background, background.copy(alpha = 0.82f)),
                        start = Offset.Zero,
                        end = Offset(size.width, size.height)
                    )
                )
            }
            .padding(metrics.padding)
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            CardText("Taiwan Air", foreground.copy(alpha = 0.85f), 13.sp, FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            content.publishTime?.let {
                CardText(PublishTime.dateTime(it, locale), foreground.copy(alpha = 0.85f), 12.sp, FontWeight.Light)
            }
        }

        FlexibleSpace()

        CardText(
            content.title,
            foreground,
            metrics.titleSize,
            FontWeight.SemiBold,
            maxLines = metrics.titleLines,
            minScale = 0.6f
        )

        if (metrics.showsLocality && content.locality != null) {
            CardText(
                content.locality,
                foreground.copy(alpha = 0.85f),
                14.sp,
                FontWeight.Light,
                minScale = 0.8f,
                modifier = Modifier.padding(top = 2.dp)
            )
        }

        Row(
            Modifier.fillMaxWidth().padding(top = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Column(Modifier.weight(1f)) {
                CardText("AQI", foreground.copy(alpha = 0.85f), 13.sp, FontWeight.Medium)
                CardText(
                    if (hasReading) content.aqi.toInt().toString() else "—",
                    foreground,
                    metrics.numberSize,
                    FontWeight.Thin,
                    minScale = 0.6f
                )
            }
            // The faces are black line art, which vanishes on the darker bands; tinted, they take
            // the text colour (iOS draws them as templates).
            status.faceImage()?.let {
                Image(
                    painterResource(it),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(foreground),
                    modifier = Modifier.size(metrics.faceSize)
                )
            }
        }

        CardText(
            stringResource(status.label),
            foreground,
            15.sp,
            FontWeight.SemiBold,
            minScale = 0.7f,
            modifier = Modifier
                .background(foreground.copy(alpha = 0.15f), RoundedCornerShape(8.dp))
                .padding(horizontal = 12.dp, vertical = 4.dp)
        )

        FlexibleSpace()

        content.readings?.let { readings ->
            Row(Modifier.fillMaxWidth().padding(bottom = 12.dp)) {
                readings.forEach { (type, value) ->
                    Reading(type, value, metrics.readingSize, foreground, Modifier.weight(1f))
                }
            }
        }

        val guidance = status.generalPublicGuidance
        if (hasReading && metrics.guidanceLines > 0 && guidance != null) {
            CardText(
                stringResource(guidance),
                foreground,
                13.sp,
                FontWeight.Light,
                maxLines = metrics.guidanceLines,
                minScale = 0.8f,
                modifier = Modifier.padding(bottom = 12.dp)
            )
        }

        Brand(metrics.iconSize, foreground)
    }
}

/** iOS `Spacer(minLength: 12)`: the two share what the shape leaves over. */
@Composable
private fun ColumnScope.FlexibleSpace() {
    Spacer(Modifier.weight(1f).heightIn(min = 12.dp))
}

/**
 * The app icon and where to get it, so the picture still points at the app when a chat or a story
 * drops the text sent with it.
 */
@Composable
private fun Brand(iconSize: Dp, foreground: Color) {
    Row(
        Modifier
            .fillMaxWidth()
            .drawBehind { drawRect(foreground.copy(alpha = 0.25f), size = size.copy(height = 1.dp.toPx())) }
            .padding(top = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Image(
            ImageBitmap.imageResource(R.drawable.share_card_app_icon),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            filterQuality = FilterQuality.High,
            modifier = Modifier.size(iconSize).clip(RoundedCornerShape(iconSize * 0.225f))
        )
        Spacer(Modifier.width(8.dp))
        CardText(
            stringResource(R.string.share_download),
            foreground,
            12.sp,
            FontWeight.Medium,
            maxLines = 2,
            minScale = 0.8f,
            modifier = Modifier.weight(1f)
        )
    }
}

/** Zero means the station doesn't measure it, as on the pollutant grid. */
@Composable
private fun Reading(type: AirIndexType, value: Double, size: TextUnit, foreground: Color, modifier: Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        CardText(type.label, foreground.copy(alpha = 0.85f), 12.sp, FontWeight.Medium)
        Row(Modifier.fillMaxWidth()) {
            BasicText(
                if (value > 0) type.format(value) else "—",
                style = TextStyle(color = foreground, fontSize = size, fontWeight = FontWeight.Normal),
                maxLines = 1,
                modifier = Modifier.alignByBaseline()
            )
            if (value > 0) {
                BasicText(
                    type.unit,
                    style = TextStyle(
                        color = foreground.copy(alpha = 0.85f),
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Light
                    ),
                    maxLines = 1,
                    modifier = Modifier.alignByBaseline().padding(start = 3.dp)
                )
            }
        }
    }
}

/**
 * One line (or [maxLines]) of card text that shrinks to as little as [minScale] of [size] before
 * it is cut, as iOS `minimumScaleFactor` does, so a long name never pushes the card taller.
 */
@Composable
private fun CardText(
    text: String,
    color: Color,
    size: TextUnit,
    weight: FontWeight,
    modifier: Modifier = Modifier,
    maxLines: Int = 1,
    minScale: Float? = null
) {
    BasicText(
        text,
        modifier = modifier,
        style = TextStyle(color = color, fontSize = size, fontWeight = weight),
        maxLines = maxLines,
        overflow = TextOverflow.Ellipsis,
        autoSize = minScale?.let {
            TextAutoSize.StepBased(minFontSize = size * it, maxFontSize = size, stepSize = 0.5.sp)
        }
    )
}
