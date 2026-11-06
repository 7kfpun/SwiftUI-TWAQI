package com.kfpun.twaqi.ui.station

import androidx.annotation.DrawableRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.google.android.gms.maps.GoogleMapOptions
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.rememberCameraPositionState
import com.google.maps.android.compose.rememberUpdatedMarkerState
import com.kfpun.twaqi.R
import com.kfpun.twaqi.ui.common.SectionLabel
import com.kfpun.twaqi.ui.common.secondaryText

/**
 * Where the station physically is: a small map, the address and the coordinates (iOS
 * `StationLocationView`). Fixed metadata, so it sits at the foot of the page.
 *
 * The map is Google Maps in lite mode (a still image, no gestures, cheap inside a scrolling page),
 * keyed by `MAPS_API_KEY`; with the example key it renders blank, the rest still shows.
 *
 * @param address the street address, as the API sends it (Chinese) or translated on the device in
 *   English (FOX-98).
 */
@Composable
fun StationLocation(lat: Double, lon: Double, address: String?, coordinateText: String, modifier: Modifier = Modifier) {
    val hasPosition = !(lat == 0.0 && lon == 0.0)
    Column(modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionLabel(stringResource(R.string.details_location))
        if (hasPosition) StationMiniMap(lat, lon)
        if (!address.isNullOrEmpty()) {
            InfoRow(
                R.drawable.ic_station_place,
                stringResource(R.string.details_address),
                address
            )
        }
        if (coordinateText.isNotEmpty()) {
            InfoRow(R.drawable.ic_station_coordinates, stringResource(R.string.details_coordinates), coordinateText)
        }
    }
}

@Composable
private fun StationMiniMap(lat: Double, lon: Double) {
    val position = LatLng(lat, lon)
    val camera = rememberCameraPositionState(key = "$lat,$lon") {
        this.position = CameraPosition.fromLatLngZoom(position, MAP_ZOOM)
    }
    val description = stringResource(R.string.details_map)
    val options = remember { GoogleMapOptions().liteMode(true) }
    GoogleMap(
        modifier = Modifier
            .fillMaxWidth()
            .height(160.dp)
            .clip(RoundedCornerShape(10.dp))
            .semantics { contentDescription = description },
        cameraPositionState = camera,
        googleMapOptionsFactory = { options },
        uiSettings = MapUiSettings(
            compassEnabled = false,
            mapToolbarEnabled = false,
            myLocationButtonEnabled = false,
            zoomControlsEnabled = false,
            scrollGesturesEnabled = false,
            zoomGesturesEnabled = false,
            tiltGesturesEnabled = false,
            rotationGesturesEnabled = false
        )
    ) {
        Marker(state = rememberUpdatedMarkerState(position = position))
    }
}

@Composable
private fun InfoRow(@DrawableRes icon: Int, title: String, value: String) {
    Row {
        Icon(
            painterResource(icon),
            contentDescription = null,
            tint = secondaryText(),
            modifier = Modifier.padding(top = 2.dp).size(16.dp)
        )
        Column(Modifier.padding(start = 10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                title,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Light,
                color = secondaryText()
            )
            Text(value, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Light)
        }
    }
}

private const val MAP_ZOOM = 14f
