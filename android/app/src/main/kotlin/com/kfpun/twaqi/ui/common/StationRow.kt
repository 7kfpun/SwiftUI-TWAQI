package com.kfpun.twaqi.ui.common

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus

/**
 * One station in a list: identity on the left, an optional current reading on the right (iOS
 * `StationRow`). Shared by Favourites and the station list (FOX-54) so both stay in step.
 *
 * @param reading omitted on the search list, where no reading has been fetched.
 * @param alertsOn a bell beside the name: the station has an AQI alert on (FOX-57).
 */
@Composable
fun StationRow(
    title: String,
    subtitle: String?,
    modifier: Modifier = Modifier,
    reading: StationRowReading? = null,
    alertsOn: Boolean = false
) {
    Row(modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(title, style = MaterialTheme.typography.bodyLarge)
                if (alertsOn) {
                    Icon(
                        painterResource(R.drawable.ic_station_bell),
                        contentDescription = stringResource(R.string.favourites_alerts_on),
                        tint = Orange,
                        modifier = Modifier.padding(start = 6.dp).size(14.dp)
                    )
                }
            }
            if (subtitle != null) {
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.Light,
                    color = secondaryText(),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            if (reading != null && reading.pollutants.isNotEmpty()) {
                PollutantLine(reading.pollutants, Modifier.padding(top = 2.dp))
            }
            reading?.publishTime?.let { LastUpdated(it, compact = true) }
        }
        Spacer(Modifier.width(8.dp))
        if (reading != null) ReadingBadge(reading.aqi)
    }
}

/** @property pollutants a few pollutants on one line under the locality; empty leaves just the AQI. */
data class StationRowReading(
    val aqi: Double,
    val publishTime: String?,
    val pollutants: List<Pair<AirIndexType, Double>> = emptyList()
)

/**
 * "PM2.5 18   PM10 32   O3 41.2", each value in its band colour. Zero is "—": several stations
 * report 0.0 for what they don't measure.
 */
@Composable
private fun PollutantLine(pollutants: List<Pair<AirIndexType, Double>>, modifier: Modifier = Modifier) {
    val secondary = secondaryText()
    val text = buildAnnotatedString {
        pollutants.forEachIndexed { index, (type, value) ->
            if (index > 0) append("   ")
            withStyle(SpanStyle(color = secondary)) { append("${type.label} ") }
            val hasReading = value > 0
            withStyle(
                SpanStyle(
                    fontWeight = FontWeight.Medium,
                    color = if (hasReading) rgb(AirStatus.of(type, value).color) else secondary
                )
            ) { append(if (hasReading) type.format(value) else "—") }
        }
    }
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = modifier
    )
}

@Composable
private fun ReadingBadge(aqi: Double) {
    val status = AirStatus.of(AirIndexType.AQI, aqi)
    Column(Modifier.width(84.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        ReadingLabel(AirIndexType.AQI, aqi)
        Text(
            stringResource(status.label),
            fontSize = 10.sp,
            fontWeight = FontWeight.Light,
            color = secondaryText(),
            textAlign = TextAlign.Center,
            maxLines = 2,
            modifier = Modifier.padding(top = 4.dp)
        )
    }
}
