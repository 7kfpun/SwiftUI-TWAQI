package com.kfpun.twaqi.ui.forecast

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.kfpun.twaqi.R
import com.kfpun.twaqi.TwaqiApplication
import com.kfpun.twaqi.data.model.ForecastTabArea
import com.kfpun.twaqi.data.model.ForecastTabOrdering
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.ui.common.EmptyState
import com.kfpun.twaqi.ui.common.OfflineEmptyState
import java.time.Instant

/**
 * The Forecast tab (iOS `ForecastView`, FOX-32): MOENV's 空品區 forecast for every zone, each with
 * every day the feed has. The reader's zone comes first, then the favourites' zones, then the
 * rest. Offline it shows the last good copy, else the offline empty state.
 */
@Composable
fun ForecastScreen(
    modifier: Modifier = Modifier,
    viewModel: ForecastViewModel = viewModel(
        factory = ForecastViewModel.factory(LocalContext.current.applicationContext as TwaqiApplication)
    )
) {
    val app = LocalContext.current.applicationContext as TwaqiApplication
    val favourites by app.container.favourites.favourites.collectAsStateWithLifecycle()
    // Each time the tab shows, and when favourites change, as iOS reloads in `onAppear`.
    LaunchedEffect(favourites) { viewModel.load(favourites) }
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    ForecastContent(state, onRetry = { viewModel.load(favourites) }, modifier = modifier)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ForecastContent(
    state: ForecastUiState,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
    now: Instant = Instant.now()
) {
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    Scaffold(
        modifier = modifier.fillMaxSize().nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text(stringResource(R.string.forecast_tab_title)) },
                scrollBehavior = scrollBehavior
            )
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.TopCenter) {
            when (state) {
                ForecastUiState.Loading -> CircularProgressIndicator(Modifier.padding(top = 64.dp))

                ForecastUiState.Empty -> OfflineEmptyState(onRetry, Modifier.padding(horizontal = 32.dp))

                ForecastUiState.NoCurrentForecast -> Column(
                    Modifier.padding(horizontal = 32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    EmptyState(R.drawable.ic_tab_forecast, stringResource(R.string.forecast_none_current))
                    OutlinedButton(onClick = onRetry, modifier = Modifier.padding(top = 16.dp)) {
                        Text(stringResource(R.string.offline_retry))
                    }
                }

                is ForecastUiState.Loaded -> ForecastList(state, now)
            }
        }
    }
}

@Composable
private fun ForecastList(state: ForecastUiState.Loaded, now: Instant) {
    val context = LocalContext.current
    val language = translationLanguage(AppLocale.isChinese(context))
    val shared = state.sharedContent
    LazyColumn(
        // A readable measure on tablets, as the station page.
        Modifier.widthIn(max = 640.dp).fillMaxWidth(),
        contentPadding = PaddingValues(vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp)
    ) {
        if (shared != null) {
            item(key = "shared") {
                ForecastContentText(
                    shared,
                    ForecastTabOrdering.sharedTranslation(state.areas, language),
                    Modifier
                        .padding(horizontal = 16.dp)
                        .clip(ForecastCardShape)
                        .background(cardBackground())
                )
            }
        }
        items(state.areas, key = ForecastTabArea::area) { area ->
            AreaForecastCard(
                forecast = area.forecast,
                heading = ForecastHeading.Area(area.pin),
                showsContent = shared == null || area.forecast.content != shared,
                showsSource = false,
                now = now
            )
        }
        // Once for the whole list rather than under every card.
        item(key = "source") {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                CaptionText(stringResource(R.string.forecast_source))
            }
        }
    }
}
