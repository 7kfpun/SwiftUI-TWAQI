package com.kfpun.twaqi.widget

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.Preferences
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.lifecycle.lifecycleScope
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.Country
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.ui.theme.TWAQITheme
import kotlinx.coroutines.launch

/**
 * Picks a widget's station and index when it is added, and again from the widget's settings
 * (iOS: the widget's edit sheet, `SelectIndexIntent`). The station is the nearest one (the
 * default), the first favourite, or any station. Saving starts the page state afresh and fetches.
 */
class WidgetConfigureActivity : AppCompatActivity() {
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        appWidgetId = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        // Backing out cancels adding the widget.
        setResult(RESULT_CANCELED, resultIntent())
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        val container = WidgetDataSource.containerOf(this)
        setContent {
            TWAQITheme {
                var initial by remember { mutableStateOf<WidgetConfig?>(null) }
                var stations by remember { mutableStateOf<List<Pollutant>>(emptyList()) }
                LaunchedEffect(Unit) {
                    initial = runCatching {
                        val glanceId = GlanceAppWidgetManager(this@WidgetConfigureActivity).getGlanceIdBy(appWidgetId)
                        WidgetStateKeys.config(
                            getAppWidgetState<Preferences>(
                                this@WidgetConfigureActivity,
                                PreferencesGlanceStateDefinition,
                                glanceId
                            )
                        )
                    }.getOrNull() ?: WidgetConfig()
                    stations = container.airQuality.savedPollutants(Country.SUPPORTED_CODE)?.value
                        ?: container.airQuality.currentPollutants(Country.SUPPORTED_CODE).valueOrNull.orEmpty()
                }
                val favouriteIds by container.favourites.favourites.collectAsState()
                initial?.let { config ->
                    WidgetConfigureScreen(
                        initial = config,
                        stations = stations,
                        favouriteIds = favouriteIds,
                        chinese = AppLocale.isChinese(this),
                        onSave = ::save
                    )
                }
            }
        }
    }

    private fun save(config: WidgetConfig) {
        lifecycleScope.launch {
            val manager = GlanceAppWidgetManager(this@WidgetConfigureActivity)
            val glanceId = runCatching { manager.getGlanceIdBy(appWidgetId) }.getOrNull()
            if (glanceId != null) {
                updateAppWidgetState(this@WidgetConfigureActivity, glanceId) { prefs ->
                    WidgetStateKeys.writeConfig(prefs, config)
                    WidgetStateKeys.bumpVersion(prefs, java.time.Instant.now())
                }
                widgetFor(appWidgetId).update(this@WidgetConfigureActivity, glanceId)
                WidgetUpdater.scheduleReset(this@WidgetConfigureActivity, appWidgetId, null)
            }
            WidgetUpdater.refreshNow(applicationContext)
            setResult(RESULT_OK, resultIntent())
            finish()
        }
    }

    private fun widgetFor(appWidgetId: Int): GlanceAppWidget {
        val provider = AppWidgetManager.getInstance(this).getAppWidgetInfo(appWidgetId)?.provider?.className
        return if (provider ==
            StationDetailWidgetReceiver::class.java.name
        ) {
            StationDetailWidget()
        } else {
            AirQualityWidget()
        }
    }

    private fun resultIntent() = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
}

@OptIn(ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
private fun WidgetConfigureScreen(
    initial: WidgetConfig,
    stations: List<Pollutant>,
    favouriteIds: List<Int>,
    chinese: Boolean,
    onSave: (WidgetConfig) -> Unit
) {
    var station by remember { mutableStateOf(initial.station) }
    var index by remember { mutableStateOf(initial.index) }
    var query by rememberSaveable { mutableStateOf("") }
    val byId = stations.associateBy { it.stationId }
    val favourites = favouriteIds.mapNotNull(byId::get)
    val matches = stations
        .filter {
            query.isBlank() || it.displayName(chinese).contains(query.trim(), ignoreCase = true) ||
                it.name.contains(query.trim(), ignoreCase = true)
        }
        .sortedBy { it.displayName(chinese) }

    Scaffold(
        topBar = { TopAppBar(title = { Text(stringResource(R.string.widget_configure_title)) }) },
        bottomBar = {
            Button(
                onClick = { onSave(WidgetConfig(station, index)) },
                modifier = Modifier.fillMaxWidth().padding(16.dp)
            ) { Text(stringResource(R.string.widget_configure_save)) }
        }
    ) { padding ->
        LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
            item { SectionTitle(stringResource(R.string.widget_index)) }
            item {
                FlowRow(
                    modifier = Modifier.padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    WidgetPaging.indexCycle.forEach { type ->
                        FilterChip(selected = type == index, onClick = { index = type }, label = { Text(type.label) })
                    }
                }
            }
            item { SectionTitle(stringResource(R.string.widget_station)) }
            item {
                ChoiceRow(stringResource(R.string.widget_station_closest), station == StationChoice.Nearest) {
                    station = StationChoice.Nearest
                }
            }
            item {
                ChoiceRow(
                    stringResource(R.string.widget_station_first_favourite),
                    station == StationChoice.FirstFavourite
                ) {
                    station = StationChoice.FirstFavourite
                }
            }
            if (favourites.isNotEmpty()) {
                item { SectionTitle(stringResource(R.string.widget_favourites)) }
                items(favourites, key = { "favourite-${it.stationId}" }) { reading ->
                    StationRow(reading, chinese, station) { station = StationChoice.Station(reading.stationId) }
                }
            }
            item { SectionTitle(stringResource(R.string.widget_all_stations)) }
            item {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    singleLine = true,
                    placeholder = { Text(stringResource(R.string.detailslist_search)) },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)
                )
            }
            items(matches, key = { "station-${it.stationId}" }) { reading ->
                StationRow(reading, chinese, station) { station = StationChoice.Station(reading.stationId) }
            }
        }
    }
}

@Composable
private fun SectionTitle(text: String) {
    Column {
        HorizontalDivider(modifier = Modifier.padding(top = 8.dp))
        Text(
            text,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
        )
    }
}

@Composable
private fun StationRow(reading: Pollutant, chinese: Boolean, selected: StationChoice, onClick: () -> Unit) {
    val locality = reading.displayLocality(chinese)
    ChoiceRow(
        label = reading.displayName(chinese),
        detail = locality,
        selected = selected == StationChoice.Station(reading.stationId),
        onClick = onClick
    )
}

@Composable
private fun ChoiceRow(label: String, selected: Boolean, detail: String? = null, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 8.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        RadioButton(selected = selected, onClick = onClick)
        Column {
            Text(label, style = MaterialTheme.typography.bodyLarge)
            detail?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
