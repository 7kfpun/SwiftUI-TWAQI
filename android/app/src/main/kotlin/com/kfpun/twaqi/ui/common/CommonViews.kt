package com.kfpun.twaqi.ui.common

import androidx.annotation.DrawableRes
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.ui.station.PublishTime

/** A `0xRRGGBB` colour from the models ([AirStatus.color]) as a Compose colour. */
fun rgb(value: Int): Color = Color(0xFF000000 or value.toLong())

/** iOS `.secondary` text. */
@Composable
fun secondaryText(): Color = MaterialTheme.colorScheme.onSurfaceVariant

/** iOS's orange, for the offline notice and the alert bell. */
val Orange = Color(0xFFFF9500)

/** Small uppercase heading above a group of rows (iOS `SectionLabel`). */
@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text.uppercase(AppLocale.locale(LocalContext.current)),
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.Medium,
        color = secondaryText(),
        modifier = modifier
    )
}

/** The value in its band colour, as a rounded chip (iOS `LabelView`). */
@Composable
fun ReadingLabel(type: AirIndexType, value: Double, modifier: Modifier = Modifier) {
    val status = AirStatus.of(type, value)
    Text(
        text = type.format(value),
        color = rgb(status.foregroundColor),
        fontWeight = FontWeight.Light,
        textAlign = TextAlign.Center,
        style = MaterialTheme.typography.bodyLarge,
        modifier = modifier
            .background(rgb(status.color), RoundedCornerShape(8.dp))
            .widthIn(min = 41.dp)
            .padding(horizontal = 8.dp, vertical = 4.dp)
    )
}

/** "Last updated Nov 6, 2026, 22:00 · 2 hr. ago", or "22:00 · 2 hr. ago" when [compact] (iOS `LastUpdatedView`). */
@Composable
fun LastUpdated(publishTime: String, modifier: Modifier = Modifier, compact: Boolean = false) {
    val locale = AppLocale.locale(LocalContext.current)
    val time = if (compact) {
        PublishTime.time(publishTime)
    } else {
        stringResource(R.string.details_last_updated) + " " + PublishTime.dateTime(publishTime, locale)
    }
    val age = PublishTime.age(publishTime)
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Icon(
            painterResource(R.drawable.ic_station_clock),
            contentDescription = null,
            tint = secondaryText(),
            modifier = Modifier.size(12.dp)
        )
        Text(
            text = if (age.isEmpty()) time else "$time · $age",
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Light,
            color = secondaryText(),
            modifier = Modifier.padding(start = 4.dp)
        )
    }
}

/** Centred placeholder for an empty or still-loading list (iOS `EmptyStateView`). */
@Composable
fun EmptyState(@DrawableRes icon: Int, message: String, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxWidth().padding(start = 32.dp, end = 32.dp, top = 64.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(painterResource(icon), contentDescription = null, tint = secondaryText(), modifier = Modifier.size(40.dp))
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Light,
            color = secondaryText(),
            textAlign = TextAlign.Center
        )
    }
}

/** One line saying the readings below are the last good ones saved (iOS `OfflineNotice`). */
@Composable
fun OfflineNotice(modifier: Modifier = Modifier) {
    val text = stringResource(R.string.offline_showing_saved_readings)
    Row(
        modifier.clearAndSetSemantics { contentDescription = text },
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            painterResource(R.drawable.ic_station_offline),
            contentDescription = null,
            tint = Orange,
            modifier = Modifier.size(16.dp)
        )
        Text(
            text,
            style = MaterialTheme.typography.bodySmall,
            color = Orange,
            modifier = Modifier.padding(start = 6.dp)
        )
    }
}

/** Nothing could be loaded and nothing was saved (iOS `OfflineEmptyStateView`). */
@Composable
fun OfflineEmptyState(onRetry: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        EmptyState(R.drawable.ic_station_offline, stringResource(R.string.offline_nothing_saved))
        OutlinedButton(onClick = onRetry, modifier = Modifier.padding(top = 16.dp)) {
            Text(stringResource(R.string.offline_retry))
        }
    }
}
