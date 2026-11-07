package com.kfpun.twaqi.watch.data

import android.content.Context
import com.kfpun.twaqi.watch.BuildConfig
import java.time.Duration
import java.time.Instant

/**
 * The reading the complication and tile follow (iOS `ReadingProvider.timeline`): the station the
 * reader pinned, else the one the app last showed (the app resolves home from the location; the
 * complication can't), else the station nearest the 中正 default. Offline, the cached reading.
 */
class WatchRepository(
    private val api: WatchApi,
    private val store: WatchStore,
    private val clock: () -> Instant = Instant::now
) {
    suspend fun followedReading(): WatchReading? {
        val cached = store.latestReading
        val fetchedAt = store.latestFetchedAt
        // The app has just fetched (and asked the surfaces to redraw): no second round trip.
        if (cached != null && fetchedAt != null && Duration.between(fetchedAt, clock()) < REUSE_WITHIN) return cached

        val fresh = runCatching {
            val stationId = store.pinnedStationId ?: cached?.stationId
            if (stationId != null) {
                api.currentPollutant(stationId)
            } else {
                WatchApi.closest(WatchApi.DEFAULT_LATITUDE, WatchApi.DEFAULT_LONGITUDE, api.currentPollutants())
            }
        }.getOrNull()
        if (fresh != null) store.latestReading = fresh
        return fresh ?: cached
    }

    companion object {
        val REUSE_WITHIN: Duration = Duration.ofMinutes(5)

        @Volatile
        private var shared: WatchRepository? = null

        fun api(): WatchApi = WatchApi(BuildConfig.API_DOMAIN)

        fun get(context: Context): WatchRepository = shared ?: synchronized(this) {
            shared ?: WatchRepository(api(), WatchStore.get(context)).also { shared = it }
        }
    }
}
