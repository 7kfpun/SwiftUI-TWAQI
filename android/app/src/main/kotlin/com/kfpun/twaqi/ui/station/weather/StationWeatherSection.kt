package com.kfpun.twaqi.ui.station.weather

import android.icu.text.MeasureFormat
import android.icu.text.NumberFormat
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import android.text.format.DateUtils
import androidx.annotation.DrawableRes
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.kfpun.twaqi.R
import com.kfpun.twaqi.TwaqiApplication
import com.kfpun.twaqi.data.weather.StationWeather
import com.kfpun.twaqi.data.weather.WeatherCode
import com.kfpun.twaqi.data.weather.WeatherIcon
import com.kfpun.twaqi.data.weather.WeatherPeriod
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.ui.common.SectionLabel
import com.kfpun.twaqi.ui.common.secondaryText
import com.kfpun.twaqi.ui.station.StationDetailsUiState
import java.time.Instant
import java.util.Locale

/**
 * The station page's weather slot (FOX-93): finds CWA weather for the station once its reading or
 * record has loaded, and draws [StationWeatherCard], or nothing when nothing is in range.
 */
@Composable
fun StationWeatherSection(
    state: StationDetailsUiState,
    viewModel: StationWeatherViewModel = viewModel(
        key = "weather-${state.stationId}",
        factory = StationWeatherViewModel.factory(LocalContext.current.applicationContext as TwaqiApplication)
    )
) {
    val queries = remember(state.pollutant, state.station) { WeatherQuery.from(state) }
    LaunchedEffect(queries) { viewModel.find(queries) }
    val card by viewModel.card.collectAsStateWithLifecycle()
    card?.let { StationWeatherCard(it) }
}

/**
 * CWA weather for the station (iOS `StationWeatherView`, FOX-11): the nearest CWA station's latest
 * reading, then the county's next three forecast periods. Free, not Pro; sits above the cam.
 */
@Composable
fun StationWeatherCard(card: StationWeatherCardState, modifier: Modifier = Modifier, now: Instant = Instant.now()) {
    val context = LocalContext.current
    val chinese = AppLocale.isChinese(context)
    val weather = card.weather
    Column(modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            SectionLabel(stringResource(R.string.weather_title))
            headingCounty(card, chinese)?.let { county ->
                Text(
                    " · $county",
                    style = MaterialTheme.typography.bodySmall,
                    color = secondaryText()
                )
            }
        }

        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
        ) {
            weather.now?.let { NowRow(it, chinese, now) }
            weather.periods.forEachIndexed { index, period ->
                if (index > 0 || weather.now != null) {
                    HorizontalDivider(Modifier.padding(start = 12.dp), color = MaterialTheme.colorScheme.outlineVariant)
                }
                PeriodRow(period, chinese, now)
            }
        }

        Text(
            stringResource(R.string.weather_source),
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Light,
            color = secondaryText(),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

/**
 * The forecast's county: the station's own name for it, else (in Chinese) the CWA county it was
 * matched to. Only when there is a forecast to label.
 */
internal fun headingCounty(card: StationWeatherCardState, chinese: Boolean): String? {
    if (card.weather.periods.isEmpty()) return null
    card.countyTitle(chinese)?.takeIf { it.isNotEmpty() }?.let { return it }
    return if (chinese) card.weather.county else null
}

@Composable
private fun NowRow(now: StationWeather.Now, chinese: Boolean, at: Instant) {
    val reading = now.observation
    val context = LocalContext.current
    val resources = LocalResources.current
    val temperature = WeatherFormat.temperature(reading.temp)
    val temperatureLabel = stringResource(R.string.weather_temperature, temperature)
    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                temperature,
                fontSize = 34.sp,
                fontWeight = FontWeight.SemiBold,
                fontFamily = FontFamily.SansSerif,
                modifier = Modifier.clearAndSetSemantics { contentDescription = temperatureLabel }
            )
            Spacer(Modifier.weight(1f))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.Top) {
                Metric(
                    stringResource(R.string.weather_humidity),
                    WeatherFormat.percent(reading.humidity),
                    R.drawable.ic_weather_humidity
                )
                Metric(
                    stringResource(R.string.weather_rain_today),
                    WeatherFormat.millimetres(reading.rain),
                    R.drawable.ic_weather_umbrella
                )
                Metric(
                    stringResource(R.string.weather_wind),
                    WeatherFormat.windSpeed(reading.wind),
                    R.drawable.ic_weather_wind
                )
            }
        }
        Text(
            stationLine(now, chinese, at, AppLocale.locale(context)) { id, args -> resources.getString(id, *args) },
            style = MaterialTheme.typography.bodySmall,
            color = secondaryText(),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun Metric(title: String, value: String, @DrawableRes icon: Int) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Icon(
                painterResource(icon),
                contentDescription = null,
                tint = secondaryText(),
                modifier = Modifier.size(14.dp)
            )
            Text(value, style = MaterialTheme.typography.bodyMedium, maxLines = 1)
        }
        Text(title, style = MaterialTheme.typography.labelSmall, color = secondaryText(), maxLines = 1)
    }
}

@Composable
private fun PeriodRow(period: WeatherPeriod, chinese: Boolean, now: Instant) {
    val context = LocalContext.current
    val resources = LocalResources.current
    val locale = AppLocale.locale(context)
    val chance = WeatherFormat.percent(period.pop)
    val chanceLabel = stringResource(R.string.weather_chance_of_rain, chance)
    val icon = WeatherCode.icon(period.wx, period.isNight)
    Row(
        Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Column(Modifier.width(76.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(
                WeatherFormat.dayTitle(period, now, locale, resources::getString),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            Text(WeatherFormat.timeRange(period), style = MaterialTheme.typography.labelSmall, color = secondaryText())
        }
        Icon(
            painterResource(icon.drawable()),
            contentDescription = null,
            tint = icon.tint(),
            modifier = Modifier.size(26.dp)
        )
        Text(
            WeatherCode.text(period.wx, period.text, chinese, resources::getString).orEmpty(),
            style = MaterialTheme.typography.bodyMedium,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f)
        )
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(
                WeatherFormat.temperatureRange(period.minT, period.maxT),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(3.dp),
                modifier = Modifier.clearAndSetSemantics { contentDescription = chanceLabel }
            ) {
                Icon(
                    painterResource(R.drawable.ic_weather_umbrella),
                    contentDescription = null,
                    tint = secondaryText(),
                    modifier = Modifier.size(12.dp)
                )
                Text(chance, style = MaterialTheme.typography.bodySmall, color = secondaryText())
            }
        }
    }
}

/**
 * 「臺北測站，距離 2.9 公里 · 觀測於 20 分鐘前」. The station's name is CWA's Chinese and is only
 * shown in Chinese.
 */
private fun stationLine(
    now: StationWeather.Now,
    chinese: Boolean,
    at: Instant,
    locale: Locale,
    getString: (Int, Array<out Any>) -> String
): String {
    val distance = MeasureFormat.getInstance(
        locale,
        MeasureFormat.FormatWidth.SHORT,
        NumberFormat.getInstance(locale).apply {
            minimumFractionDigits = 1
            maximumFractionDigits = 1
        }
    ).format(Measure(now.distanceKm, MeasureUnit.KILOMETER))
    val station = if (chinese) {
        getString(R.string.weather_station_named, arrayOf(now.observation.name, distance))
    } else {
        getString(R.string.weather_station_nearby, arrayOf(distance))
    }
    val observed = minOf(now.observedAt, at)
    val age = DateUtils.getRelativeTimeSpanString(
        observed.toEpochMilli(),
        at.toEpochMilli(),
        DateUtils.MINUTE_IN_MILLIS,
        DateUtils.FORMAT_ABBREV_RELATIVE
    ).toString()
    return "$station · ${getString(R.string.weather_observed, arrayOf(age))}"
}

@DrawableRes
private fun WeatherIcon.drawable(): Int = when (this) {
    WeatherIcon.SUN_MAX -> R.drawable.ic_weather_clear_day

    WeatherIcon.MOON_STARS -> R.drawable.ic_weather_clear_night

    WeatherIcon.CLOUD_SUN -> R.drawable.ic_weather_partly_cloudy_day

    WeatherIcon.CLOUD_MOON -> R.drawable.ic_weather_partly_cloudy_night

    WeatherIcon.CLOUD -> R.drawable.ic_weather_cloudy

    WeatherIcon.CLOUD_DRIZZLE, WeatherIcon.CLOUD_SUN_RAIN, WeatherIcon.CLOUD_MOON_RAIN -> R.drawable.ic_weather_drizzle

    WeatherIcon.CLOUD_RAIN -> R.drawable.ic_weather_rain

    WeatherIcon.CLOUD_BOLT_RAIN, WeatherIcon.CLOUD_SUN_BOLT, WeatherIcon.CLOUD_MOON_BOLT ->
        R.drawable.ic_weather_thunderstorm

    WeatherIcon.CLOUD_SLEET -> R.drawable.ic_weather_sleet

    WeatherIcon.SUN_HAZE -> R.drawable.ic_weather_haze

    WeatherIcon.CLOUD_FOG -> R.drawable.ic_weather_fog

    WeatherIcon.SNOWFLAKE -> R.drawable.ic_weather_snow
}

/** One colour per icon, standing in for iOS's multicolour symbols: sun amber, rain blue, cloud grey. */
@Composable
private fun WeatherIcon.tint(): Color = when (this) {
    WeatherIcon.SUN_MAX, WeatherIcon.CLOUD_SUN, WeatherIcon.SUN_HAZE, WeatherIcon.CLOUD_SUN_RAIN,
    WeatherIcon.CLOUD_SUN_BOLT -> Color(0xFFF5A623)

    WeatherIcon.MOON_STARS, WeatherIcon.CLOUD_MOON, WeatherIcon.CLOUD_MOON_RAIN, WeatherIcon.CLOUD_MOON_BOLT ->
        Color(0xFF8E8CD8)

    WeatherIcon.CLOUD_DRIZZLE, WeatherIcon.CLOUD_RAIN, WeatherIcon.CLOUD_BOLT_RAIN -> Color(0xFF4A90E2)

    WeatherIcon.CLOUD_SLEET, WeatherIcon.SNOWFLAKE -> Color(0xFF5AC8FA)

    WeatherIcon.CLOUD, WeatherIcon.CLOUD_FOG -> secondaryText()
}
