package com.kfpun.twaqi.ui.main

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.locale.AppLocale
import java.util.Locale
import kotlin.math.roundToInt

/**
 * The supported country's stations, nearest first, with search (iOS `DetailsListView`). Each row
 * shows the selected index's reading in its band colour, so the index selector recolours the list
 * as it does the markers. Sorted from the reader's location, or the map centre until it is known.
 *
 * @param showIndexSelector the Search tab has its own; beside the map, the map's serves both.
 */
@Composable
fun StationList(
    state: MainUiState,
    query: String,
    onQueryChange: (String) -> Unit,
    onOpenStation: (Pollutant) -> Unit,
    onRetry: () -> Unit,
    onSelectIndex: (AirIndexType) -> Unit,
    showIndexSelector: Boolean,
    modifier: Modifier = Modifier
) {
    val focusManager = LocalFocusManager.current
    val chinese = AppLocale.isChinese(LocalContext.current)
    val from = state.userLocation ?: state.center
    val rows = remember(state.supportedPollutants, query, from) {
        NearestStations.sortedByNearest(StationSearch.filter(state.supportedPollutants, query), from)
    }
    val lastGood = state.supportedCountryCode in state.lastGoodCountryCodes

    Column(modifier.fillMaxSize()) {
        Text(
            text = stringResource(R.string.detailslist_details),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp)
        )
        OutlinedTextField(
            value = query,
            onValueChange = onQueryChange,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            placeholder = { Text(stringResource(R.string.detailslist_search)) },
            leadingIcon = { Icon(painterResource(R.drawable.ic_search), contentDescription = null) },
            trailingIcon = if (query.isNotEmpty()) {
                {
                    IconButton(onClick = { onQueryChange("") }) {
                        Icon(
                            painterResource(R.drawable.ic_search_clear),
                            contentDescription = stringResource(R.string.map_clear_search)
                        )
                    }
                }
            } else {
                null
            },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { focusManager.clearFocus() })
        )
        if (showIndexSelector) {
            IndexSelector(selected = state.indexType, onSelect = onSelectIndex)
        }
        if (lastGood && rows.isNotEmpty()) {
            Text(
                text = stringResource(R.string.offline_showing_saved_readings),
                style = MaterialTheme.typography.bodySmall,
                color = OfflineOrange,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
            )
        }

        when {
            state.supportedPollutants.isEmpty() && state.loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                CircularProgressIndicator()
            }

            state.supportedPollutants.isEmpty() && state.failed -> EmptyState(
                message = stringResource(R.string.offline_nothing_saved),
                action = stringResource(R.string.offline_retry),
                onAction = onRetry
            )

            rows.isEmpty() -> EmptyState(message = stringResource(R.string.details_no_data))

            else -> LazyColumn(Modifier.fillMaxSize()) {
                items(rows, key = { it.first.stationId }) { (pollutant, distance) ->
                    StationListRow(pollutant, distance, state.indexType, lastGood, chinese, onClick = {
                        focusManager.clearFocus()
                        onOpenStation(pollutant)
                    })
                    HorizontalDivider(Modifier.padding(start = 16.dp))
                }
            }
        }
    }
}

/** One station: name, locality and distance, last update; the selected index's reading on the right (iOS `StationRow`). */
@Composable
private fun StationListRow(
    pollutant: Pollutant,
    distanceKm: Double?,
    type: AirIndexType,
    lastGood: Boolean,
    chinese: Boolean,
    onClick: () -> Unit
) {
    val value = pollutant.value(type)
    val status = AirStatus.of(type, value)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                pollutant.displayName(chinese),
                style = MaterialTheme.typography.bodyLarge,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            val subtitle = listOfNotNull(
                pollutant.displayLocality(chinese),
                distanceKm?.let(::formatDistance)
            ).joinToString(" · ")
            if (subtitle.isNotEmpty()) {
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.Light,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            UpdatedLabel(pollutant, lastGood)
        }
        Spacer(Modifier.width(8.dp))
        Column(Modifier.width(84.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            ValuePill(type, value)
            Text(
                text = stringResource(status.label),
                fontSize = 10.sp,
                fontWeight = FontWeight.Light,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                maxLines = 2,
                modifier = Modifier.padding(top = 4.dp)
            )
        }
    }
}

@Composable
private fun EmptyState(message: String, action: String? = null, onAction: () -> Unit = {}) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 64.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
        if (action != null) OutlinedButton(onClick = onAction) { Text(action) }
    }
}

/** "850 m", "3.4 km", "120 km": the same in both languages. */
internal fun formatDistance(km: Double): String = when {
    km < 1 -> String.format(Locale.US, "%d m", ((km * 100).roundToInt() * 10).coerceAtLeast(10))
    km < 100 -> String.format(Locale.US, "%.1f km", km)
    else -> String.format(Locale.US, "%d km", km.toInt())
}
