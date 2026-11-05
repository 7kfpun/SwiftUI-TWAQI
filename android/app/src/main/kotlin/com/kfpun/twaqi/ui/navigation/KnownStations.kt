package com.kfpun.twaqi.ui.navigation

import android.content.Context
import com.kfpun.twaqi.widget.WidgetDataSource

/**
 * Stations the app has seen, for checking a `twaqi://` link (iOS `KnownStations`): in the saved
 * readings or the saved station list. An id in neither is dropped rather than opening a page for
 * nothing ([DeepLink.route]).
 */
object KnownStations {
    suspend fun contains(context: Context, stationId: Int): Boolean {
        val airQuality = WidgetDataSource.containerOf(context).airQuality
        return airQuality.savedPollutants(listOf(stationId)).isNotEmpty() ||
            airQuality.savedStations()?.value?.any { it.id == stationId } == true
    }
}
