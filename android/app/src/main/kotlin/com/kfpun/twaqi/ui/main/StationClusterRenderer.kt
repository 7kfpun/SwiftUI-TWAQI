package com.kfpun.twaqi.ui.main

import android.content.Context
import com.google.android.gms.maps.GoogleMap
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
 * FOX-91, stepping through the timeline) doesn't rebuild the map.
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
        markerOptions
            .icon(icons.pill(look.text, look.color, look.foregroundColor))
            .alpha(look.alpha)
            .anchor(0.5f, 1f)
            .title(item.title)
            .zIndex(item.zIndex)
    }

    override fun onClusterItemUpdated(item: MapStation, marker: Marker) {
        val look = item.appearance
        marker.setIcon(icons.pill(look.text, look.color, look.foregroundColor))
        marker.alpha = look.alpha
        marker.title = item.title
        marker.zIndex = item.zIndex
        if (marker.position != item.position) marker.position = item.position
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
