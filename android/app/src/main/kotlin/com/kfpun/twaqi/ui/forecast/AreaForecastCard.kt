package com.kfpun.twaqi.ui.forecast

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.AqiForecast
import com.kfpun.twaqi.data.model.AreaForecast
import com.kfpun.twaqi.data.model.ForecastTabArea
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.translation.OnDeviceTranslation
import com.kfpun.twaqi.translation.TranslatesOnDevice
import com.kfpun.twaqi.translation.rememberShownTranslations
import com.kfpun.twaqi.ui.common.SectionLabel
import com.kfpun.twaqi.ui.common.rgb
import com.kfpun.twaqi.ui.common.secondaryText
import java.time.Instant
import java.util.Locale

/** What a forecast card's label says (iOS `AreaForecastView.Heading`). */
sealed interface ForecastHeading {
    /** On a station: 「空品區預報 · 北部空品區」. */
    data object RegionalForecast : ForecastHeading

    /** On the Forecast tab: the area's name, tagged when it is the reader's area or a favourite's. */
    data class Area(val pin: ForecastTabArea.Pin) : ForecastHeading
}

/** The card's corner radius, shared with the shared paragraph above the Forecast tab's cards. */
val ForecastCardShape = RoundedCornerShape(12.dp)

/**
 * 空品區預報 (iOS `AreaForecastView`): MOENV's AQI forecast for one air quality zone, a row per
 * day with its level colour. A regional outlook, not a reading for the station, so it is labelled
 * with the zone. Callers leave it out when there is nothing to show.
 *
 * @param showsContent false on the Forecast tab when this zone's text is the paragraph shown once
 *   above every card.
 * @param showsSource false on the Forecast tab, which names the source once for all cards.
 */
@Composable
fun AreaForecastCard(
    forecast: AreaForecast,
    modifier: Modifier = Modifier,
    heading: ForecastHeading = ForecastHeading.RegionalForecast,
    showsContent: Boolean = true,
    showsSource: Boolean = true,
    now: Instant = Instant.now()
) {
    val context = LocalContext.current
    val chinese = AppLocale.isChinese(context)
    val locale = AppLocale.locale(context)
    Column(modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Label(forecast, heading)

        Column(Modifier.fillMaxWidth().clip(ForecastCardShape).background(cardBackground())) {
            forecast.days.forEachIndexed { index, day ->
                if (index > 0) {
                    HorizontalDivider(Modifier.padding(start = 12.dp), color = MaterialTheme.colorScheme.outlineVariant)
                }
                DayRow(day, chinese, locale, now)
            }
            val content = forecast.content
            if (showsContent && content != null) {
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                ForecastContentText(content, forecast.translatedContent(translationLanguage(chinese)))
            }
        }

        Caption(forecast.publishedAt, showsSource, now)
    }
}

/** The background of a forecast card (iOS `secondarySystemBackground`), as the weather card's. */
@Composable
fun cardBackground() = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)

/**
 * The language the Worker's translation is looked up in, the same one text is translated into on
 * the device (iOS `OnDeviceTranslation.target`): none in Chinese, which reads MOENV's text as
 * written; else English, the app's only other language.
 */
fun translationLanguage(chinese: Boolean): String? = OnDeviceTranslation.target(chinese)

@Composable
private fun Label(forecast: AreaForecast, heading: ForecastHeading) {
    when (heading) {
        ForecastHeading.RegionalForecast -> Row(verticalAlignment = Alignment.CenterVertically) {
            SectionLabel(stringResource(R.string.forecast_title))
            Text(" · ${forecast.areaTitle}", style = MaterialTheme.typography.bodySmall, color = secondaryText())
        }

        is ForecastHeading.Area -> Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(
                forecast.areaTitle,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.semantics { heading() }
            )
            tag(heading.pin)?.let { tag ->
                val accent = MaterialTheme.colorScheme.primary
                Text(
                    stringResource(tag),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = accent,
                    modifier = Modifier
                        .background(accent.copy(alpha = 0.15f), CircleShape)
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                )
            }
        }
    }
}

/** The reader's area and favourites' areas are tagged; the 北部 fallback and the rest are not. */
internal fun tag(pin: ForecastTabArea.Pin): Int? = when (pin) {
    ForecastTabArea.Pin.READER -> R.string.forecast_your_area
    ForecastTabArea.Pin.FAVOURITE -> R.string.forecast_favourite_area
    ForecastTabArea.Pin.FALLBACK, ForecastTabArea.Pin.NONE -> null
}

@Composable
private fun DayRow(day: AqiForecast, chinese: Boolean, locale: Locale, now: Instant) {
    val resources = LocalResources.current
    val status = day.status
    Row(
        Modifier
            .padding(horizontal = 12.dp, vertical = 10.dp)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Column(Modifier.width(76.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(
                ForecastFormat.dayTitle(day.forecastDate, now, locale, resources::getString),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1
            )
            Text(
                ForecastFormat.dateSubtitle(day.forecastDate, locale),
                style = MaterialTheme.typography.labelSmall,
                color = secondaryText(),
                maxLines = 1
            )
        }

        Text(
            day.aqi?.toString() ?: "—",
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = rgb(status.foregroundColor),
            textAlign = TextAlign.Center,
            modifier = Modifier
                .widthIn(min = 52.dp)
                .heightIn(min = 26.dp)
                .background(rgb(status.color), RoundedCornerShape(6.dp))
                .padding(horizontal = 4.dp, vertical = 3.dp)
        )

        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(
                if (status == AirStatus.UNKNOWN) {
                    stringResource(R.string.forecast_no_value)
                } else {
                    stringResource(status.label)
                },
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            day.displayMajorPollutant(chinese)?.let { pollutant ->
                Text(
                    stringResource(R.string.forecast_major_pollutant, pollutant),
                    style = MaterialTheme.typography.bodySmall,
                    color = secondaryText(),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

/** 「發布 16:30 · 資料來源：環境部」 */
@Composable
private fun Caption(published: Instant?, showsSource: Boolean, now: Instant) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
            painterResource(R.drawable.ic_station_clock),
            contentDescription = null,
            tint = secondaryText(),
            modifier = Modifier.size(12.dp)
        )
        if (published != null) {
            CaptionText(
                stringResource(R.string.forecast_published, ForecastFormat.publishedText(published, now)),
                Modifier.padding(start = 4.dp)
            )
        }
        Spacer(Modifier.weight(1f).widthIn(min = 8.dp))
        if (showsSource) CaptionText(stringResource(R.string.forecast_source))
    }
}

@Composable
fun CaptionText(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        fontWeight = FontWeight.Light,
        color = secondaryText(),
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = modifier
    )
}

/**
 * MOENV's forecast text (iOS `ForecastContentText`), three lines until opened: on a station's card,
 * and once above the Forecast tab's cards when every zone carries the same paragraph. Outside
 * Chinese it is the Worker's translation ([translated]) when there is one made from this text,
 * else translated on the device once it can be (the sentences the collapsed lines show first, the
 * rest on opening), else the text as written (FOX-98).
 */
@Composable
fun ForecastContentText(content: String, translated: String?, modifier: Modifier = Modifier) {
    var expanded by rememberSaveable(content) { mutableStateOf(false) }
    // Whether the text runs past the collapsed lines; the toggle only shows when there is more.
    var truncated by rememberSaveable(content) { mutableStateOf(false) }
    // Width the text lays out at, to guess how much of it the collapsed lines show. Zero until measured.
    var textWidth by remember { mutableIntStateOf(0) }
    val style = MaterialTheme.typography.bodySmall
    val fontSize = with(LocalDensity.current) { style.fontSize.toPx() }
    val translations = rememberShownTranslations()
    val segments = remember(content) { OnDeviceTranslation.segments(content) }
    val shown = translations.forecastText(content, translated)
    TranslatesOnDevice(
        when {
            translated != null -> emptyList()

            expanded -> segments

            textWidth <= 0 || fontSize <= 0f -> emptyList()

            // A CJK character is about one font size wide.
            else -> OnDeviceTranslation.leadingSegments(
                segments,
                (textWidth / fontSize).toInt().coerceAtLeast(1) * COLLAPSED_LINES
            )
        }
    )
    val toggle = if (truncated) {
        Modifier.clickable(role = Role.Button) { expanded = !expanded }
    } else {
        Modifier
    }
    Column(
        modifier
            .fillMaxWidth()
            .then(toggle)
            .semantics(mergeDescendants = true) {}
            .padding(12.dp)
            .animateContentSize(),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(
            shown,
            style = style,
            maxLines = if (expanded) Int.MAX_VALUE else COLLAPSED_LINES,
            overflow = TextOverflow.Ellipsis,
            onTextLayout = { if (it.hasVisualOverflow) truncated = true },
            modifier = Modifier.fillMaxWidth().onSizeChanged { textWidth = it.width }
        )
        if (truncated) {
            Text(
                stringResource(if (expanded) R.string.forecast_less else R.string.forecast_more),
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.primary
            )
        }
    }
}

private const val COLLAPSED_LINES = 3
