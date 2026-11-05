package com.kfpun.twaqi.ui.main

import android.content.res.Configuration
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.google.android.gms.maps.model.MapStyleOptions
import com.google.maps.android.clustering.ClusterManager
import com.google.maps.android.compose.CameraPositionState
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapEffect
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.MapsComposeExperimentalApi
import com.google.maps.android.compose.clustering.Clustering
import com.google.maps.android.compose.rememberCameraPositionState
import com.kfpun.twaqi.R
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.locale.AppLocale
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch

/**
 * The map with its overlays (iOS `GoogleMapViewController`): coloured station markers, the
 * closest-station card and the air status bar at the top, the default-location and my-location
 * buttons and the index selector at the bottom.
 *
 * @param onOpenStation a tapped marker or the closest card, for a station in the supported country.
 */
@Composable
fun MapScreen(
    viewModel: MainViewModel,
    state: MainUiState,
    onOpenStation: (Pollutant) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val preferences = remember(context) { MapPreferences(context) }
    val cameraPositionState = rememberCameraPositionState {
        val initial = preferences.initialCamera
        position = CameraPosition.fromLatLngZoom(LatLng(initial.lat, initial.lon), initial.zoom)
    }
    var locationGranted by remember { mutableStateOf(LocationAccess.isGranted(context)) }
    val currentState by rememberUpdatedState(state)

    fun animateTo(target: MapTarget) = scope.launch {
        cameraPositionState.animate(CameraUpdateFactory.newLatLngZoom(LatLng(target.lat, target.lon), target.zoom))
    }

    fun goToMyLocation() {
        LocationAccess.current(context) { location ->
            viewModel.onUserLocation(location)
            if (location != null) {
                animateTo(MapTarget(location.lat, location.lon, MapHome.MY_LOCATION_ZOOM))
                Analytics.logEvent(context, Analytics.MOVE_TO_CURRENT_LOCATION)
            }
        }
    }

    // The automatic ask leaves the map where it is; asked from the button, a refusal goes to the
    // map home, Taiwan.
    var askedFromButton by remember { mutableStateOf(false) }
    val permissionLauncher =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { results ->
            locationGranted = results.values.any { it } || LocationAccess.isGranted(context)
            when {
                locationGranted && askedFromButton -> goToMyLocation()
                locationGranted -> LocationAccess.current(context, viewModel::onUserLocation)
                askedFromButton -> animateTo(MapHome.defaultLocation(currentState.countries))
            }
            askedFromButton = false
        }

    LaunchedEffect(Unit) {
        if (locationGranted) {
            LocationAccess.current(context, viewModel::onUserLocation)
        } else if (!preferences.askedForLocation) {
            preferences.askedForLocation = true
            permissionLauncher.launch(LocationAccess.permissions)
        }
    }

    LaunchedEffect(cameraPositionState) {
        snapshotFlow { cameraPositionState.isMoving }
            .filter { !it }
            .collect {
                val position = cameraPositionState.position
                viewModel.onCameraIdle(MapTarget(position.target.latitude, position.target.longitude, position.zoom))
            }
    }

    // iOS change_device_orientation: only when the shape flips, not on the first layout.
    val orientation = LocalConfiguration.current.orientation
    var lastOrientation by remember { mutableIntStateOf(orientation) }
    LaunchedEffect(orientation) {
        if (orientation != lastOrientation) {
            lastOrientation = orientation
            val label = if (orientation == Configuration.ORIENTATION_LANDSCAPE) "landscape" else "portrait"
            Analytics.logEvent(context, Analytics.CHANGE_DEVICE_ORIENTATION, mapOf("label" to label))
        }
    }

    Box(modifier.fillMaxSize()) {
        StationMap(
            state = state,
            cameraPositionState = cameraPositionState,
            locationGranted = locationGranted,
            onOpenStation = onOpenStation,
            modifier = Modifier.fillMaxSize()
        )

        Column(
            modifier = Modifier.statusBarsPadding().padding(start = 15.dp, top = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            state.closest?.let { closest ->
                val interactive = state.isInteractive(closest)
                ClosestStationCard(
                    pollutant = closest,
                    type = state.indexType,
                    lastGood = state.isLastGood(closest),
                    onClick = if (interactive) ({ onOpenStation(closest) }) else null
                )
            }
            AirStatusBar()
        }

        Column(
            modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(bottom = 10.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Column(
                modifier = Modifier.align(Alignment.End).padding(end = 15.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                MapRoundButton(
                    icon = R.drawable.ic_map_default_location,
                    contentDescription = stringResource(R.string.map_default_location),
                    onClick = {
                        animateTo(MapHome.defaultLocation(state.countries))
                        Analytics.logEvent(context, Analytics.MOVE_TO_DEFAULT_LOCATION)
                    }
                )
                MapRoundButton(
                    icon = R.drawable.ic_map_my_location,
                    contentDescription = stringResource(R.string.map_my_location),
                    onClick = {
                        if (LocationAccess.isGranted(context)) {
                            goToMyLocation()
                        } else {
                            askedFromButton = true
                            permissionLauncher.launch(LocationAccess.permissions)
                        }
                    }
                )
            }
            IndexSelector(
                selected = state.indexType,
                onSelect = { selectIndex(context, viewModel, it) }
            )
        }
    }
}

/** Google Map with the stations as clustered markers; the dark style follows the app's appearance. */
@OptIn(MapsComposeExperimentalApi::class)
@Composable
private fun StationMap(
    state: MainUiState,
    cameraPositionState: CameraPositionState,
    locationGranted: Boolean,
    onOpenStation: (Pollutant) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val clusterPadding = with(LocalDensity.current) { CLUSTER_PADDING.roundToPx() }
    val chinese = AppLocale.isChinese(context)
    val dark = isSystemInDarkTheme()
    val darkStyle = remember(context) { MapStyleOptions.loadRawResourceStyle(context, R.raw.map_style_dark) }
    val stations =
        remember(state.countryPollutants, state.supportedCountryCode, state.indexType, state.mapMode, chinese) {
            MarkerSource.stations(
                countryPollutants = state.countryPollutants,
                supportedCountryCode = state.supportedCountryCode,
                type = state.indexType,
                chinese = chinese,
                mode = state.mapMode
            )
        }
    val latestStations by rememberUpdatedState(stations)
    val openStation by rememberUpdatedState(onOpenStation)

    GoogleMap(
        modifier = modifier,
        cameraPositionState = cameraPositionState,
        properties = MapProperties(
            isMyLocationEnabled = locationGranted,
            mapStyleOptions = if (dark) darkStyle else null
        ),
        uiSettings = MapUiSettings(
            compassEnabled = true,
            myLocationButtonEnabled = false,
            zoomControlsEnabled = false,
            mapToolbarEnabled = false,
            indoorLevelPickerEnabled = false
        )
    ) {
        var clusterManager by remember { mutableStateOf<ClusterManager<MapStation>?>(null) }
        MapEffect(Unit) { map ->
            val manager = ClusterManager<MapStation>(context, map)
            manager.renderer = StationClusterRenderer(context, map, manager)
            manager.setOnClusterItemClickListener { tapped ->
                // The renderer may hold an older copy; ids decide, the latest reading opens.
                val station = latestStations.firstOrNull { it == tapped } ?: tapped
                // Markers outside the supported country are context only.
                if (station.isInteractive) {
                    Analytics.logEvent(
                        context,
                        Analytics.CHECK_MAIN_DETAILS,
                        mapOf(
                            "name" to station.pollutant.name,
                            "nameLocal" to station.pollutant.nameLocal,
                            "stationId" to station.stationId.toString()
                        )
                    )
                    openStation(station.pollutant)
                }
                true
            }
            manager.setOnClusterClickListener { cluster ->
                val bounds = LatLngBounds.builder().apply { cluster.items.forEach { include(it.position) } }.build()
                map.animateCamera(CameraUpdateFactory.newLatLngBounds(bounds, clusterPadding))
                true
            }
            clusterManager = manager
        }
        clusterManager?.let { Clustering(items = stations, clusterManager = it) }
    }
}

private val CLUSTER_PADDING = 64.dp
