package com.kfpun.twaqi.data

import android.content.Context
import com.kfpun.twaqi.data.cache.CacheStore
import com.kfpun.twaqi.data.cache.OfflineCacheRetention
import com.kfpun.twaqi.data.cache.PollutantCache
import com.kfpun.twaqi.data.favourites.FavouritesRepository
import com.kfpun.twaqi.data.favourites.SharedPreferencesFavouritesStore
import com.kfpun.twaqi.data.remote.ApiClient
import com.kfpun.twaqi.data.remote.ApiConfig
import com.kfpun.twaqi.data.repository.AirQualityRepository
import com.kfpun.twaqi.data.repository.ForecastRepository
import com.kfpun.twaqi.push.PushGraph
import java.io.File

/**
 * The app's single instances of the data layer. Every offline cache lives under [cacheRoot]
 * (`filesDir/offline-cache`), the one directory [OfflineCacheRetention.purge] scans.
 */
class AppContainer(context: Context, config: ApiConfig = ApiConfig.fromBuildConfig()) {
    val cacheRoot: File = File(context.filesDir, OfflineCacheRetention.ROOT_DIRECTORY)

    private val store = CacheStore(cacheRoot)
    private val api = ApiClient(config)

    val airQuality = AirQualityRepository(api, store, PollutantCache(store))
    val forecasts = ForecastRepository(api, store)

    /** FOX-55, with its alerts kept in step (FOX-57): unfavouriting turns a station's alerts off. */
    val favourites = FavouritesRepository(SharedPreferencesFavouritesStore(context), PushGraph.favouriteAlerts(context))

    /** Deletes week-old cache files. Blocking: run it off the main thread. */
    fun purgeExpiredCaches(): List<File> = OfflineCacheRetention.purge(cacheRoot)
}
