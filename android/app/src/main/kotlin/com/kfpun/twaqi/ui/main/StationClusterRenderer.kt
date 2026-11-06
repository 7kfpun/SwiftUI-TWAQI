package com.kfpun.twaqi.ui.main

import android.content.Context
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.model.BitmapDescriptor
import com.google.android.gms.maps.model.Marker
import com.google.android.gms.maps.model.MarkerOptions
import com.google.maps.android.clustering.Cluster
import com.google.maps.android.clustering.ClusterManager
import com.google.maps.android.clustering.view.DefaultClusterRenderer
import com.kfpun.twaqi.data.model.AirStatus

/**
 * Draws each station as its reading's pill and, zoomed out past [CLUSTER_BELOW_ZOOM], groups
 * nearby stations into one bubble. At the map's home zoom every station shows on its own, as on
 * iOS. Markers are kept between redraws and only restyled, so switching the index (or, with
 * FOX-91, stepping through the timeline) doesn't rebuild the map. In wind mode each station is an
 * arrow (or a calm ring) in its band colour.
 */
class StationClusterRenderer(context: Context, private val map: GoogleMap, clusterManager: ClusterManager<MapStation>) :
    DefaultClusterRenderer<MapStation>(context, map, clusterManager) {
    private val icons = MarkerIcons(context)

    init {
        minClusterSize = MIN_CLUSTER_SIZE
        setAnimation(false)
    }

    override fun shouldRenderAsCluster(cluster: Cluster<MapStation>): Boolean =
        cluster.size >= MIN_CLUSTER_SIZE && map.cameraPosition.zoom < CLUSTER_BELOW_ZOOM

    /** Stations are equal by id, so a new index leaves the clusters "unchanged"; restyle anyway. */
    override fun shouldRender(
        oldClusters: MutableSet<out Cluster<MapStation>>,
        newClusters: MutableSet<out Cluster<MapStation>>
    ): Boolean = true

    override fun onBeforeClusterItemRendered(item: MapStation, markerOptions: MarkerOptions) {
        val look = item.appearance
        val style = style(look)
        markerOptions
            .icon(style.icon)
            .alpha(look.alpha)
            .anchor(0.5f, style.anchorY)
            .rotation(style.rotation)
            .flat(style.flat)
            .title(item.title)
            .zIndex(item.zIndex)
    }

    override fun onClusterItemRendered(clusterItem: MapStation, marker: Marker) {
        marker.tag = clusterItem.appearance
    }

    /**
     * Only a marker whose appearance changed is restyled (iOS `StationMapMarker.update`), so a
     * timeline step swaps a handful of icons rather than all of them. The reading and title still
     * follow, so a tap opens the right station.
     */
    override fun onClusterItemUpdated(item: MapStation, marker: Marker) {
        if (marker.title != item.title) marker.title = item.title
        if (marker.zIndex != item.zIndex) marker.zIndex = item.zIndex
        if (marker.position != item.position) marker.position = item.position
        val look = item.appearance
        if (marker.tag == look) return
        marker.tag = look
        val style = style(look)
        marker.setIcon(style.icon)
        marker.alpha = look.alpha
        marker.setAnchor(0.5f, style.anchorY)
        marker.rotation = style.rotation
        marker.isFlat = style.flat
    }

    private class Style(val icon: BitmapDescriptor, val anchorY: Float, val rotation: Float, val flat: Boolean)

    private fun style(look: MarkerAppearance): Style = when (val shape = look.shape) {
        MarkerShape.Pill -> Style(icons.pill(look.text, look.color, look.foregroundColor), 1f, 0f, false)

        // Centred: an arrow rotating about its tail would swing away from its station. Drawn pointing
        // south and flat on the map, so the bearing (where the wind comes from) points it downwind.
        is MarkerShape.Arrow -> Style(icons.arrow(shape.strengthLevel, look.color), 0.5f, shape.bearing, true)

        MarkerShape.Calm -> Style(icons.calm(look.color), 0.5f, 0f, true)
    }

    override fun onBeforeClusterRendered(cluster: Cluster<MapStation>, markerOptions: MarkerOptions) {
        markerOptions.icon(clusterIcon(cluster)).anchor(0.5f, 0.5f)
    }

    override fun onClusterUpdated(cluster: Cluster<MapStation>, marker: Marker) {
        marker.setIcon(clusterIcon(cluster))
    }

    private fun clusterIcon(cluster: Cluster<MapStation>) = clusterStatus(cluster.items).let {
        icons.cluster(cluster.size, it.color, it.foregroundColor)
    }

    companion object {
        /** Below this zoom (Taiwan whole is 7.9) nearby stations group. */
        const val CLUSTER_BELOW_ZOOM = 7f
        const val MIN_CLUSTER_SIZE = 4

        /** The worst band among the stations, so a cluster never hides bad air; grey when none reports. */
        fun clusterStatus(items: Collection<MapStation>): AirStatus = items
            .map { it.appearance.status }
            .filter { it != AirStatus.UNKNOWN }
            .maxByOrNull { it.ordinal } ?: AirStatus.UNKNOWN
    }
}
