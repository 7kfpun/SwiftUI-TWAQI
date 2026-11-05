package com.kfpun.twaqi.data

import android.content.Context
import com.kfpun.twaqi.BuildConfig
import com.kfpun.twaqi.data.cache.CacheStore
import com.kfpun.twaqi.data.cache.OfflineCacheRetention
import com.kfpun.twaqi.data.cache.PollutantCache
import com.kfpun.twaqi.data.cams.BitmapCamImageDecoder
import com.kfpun.twaqi.data.cams.StationCamEndpoints
import com.kfpun.twaqi.data.cams.StationCamFrameCache
import com.kfpun.twaqi.data.cams.StationCamHistoryCache
import com.kfpun.twaqi.data.cams.StationCamStore
import com.kfpun.twaqi.data.favourites.FavouritesRepository
import com.kfpun.twaqi.data.favourites.SharedPreferencesFavouritesStore
import com.kfpun.twaqi.data.remote.ApiClient
import com.kfpun.twaqi.data.remote.ApiConfig
import com.kfpun.twaqi.data.repository.AirQualityRepository
import com.kfpun.twaqi.data.repository.ForecastRepository
import com.kfpun.twaqi.data.weather.StationWeatherStore
import com.kfpun.twaqi.push.PushGraph
import com.kfpun.twaqi.translation.MlKitTranslator
import com.kfpun.twaqi.translation.OnDeviceTranslation
import com.kfpun.twaqi.translation.TranslationDiskCache
import com.kfpun.twaqi.widget.WidgetHistoryCache
import java.io.File

/**
 * The app's single instances of the data layer. Every offline cache lives under [cacheRoot]
 * (`filesDir/offline-cache`), the one directory [OfflineCacheRetention.purge] scans.
 */
class AppContainer(
    context: Context,
    config: ApiConfig = ApiConfig.fromBuildConfig(),
    stationCamsUrl: String = BuildConfig.STATION_CAMS_URL
) {
    val cacheRoot: File = File(context.filesDir, OfflineCacheRetention.ROOT_DIRECTORY)

    private val store = CacheStore(cacheRoot)
    private val http = ApiClient.defaultHttpClient()
    private val api = ApiClient(config, http)

    val airQuality = AirQualityRepository(api, store, PollutantCache(store))
    val forecasts = ForecastRepository(api, store)

    /** FOX-59: the station detail widget's last 24 hours. */
    val widgetHistory = WidgetHistoryCache(store)

    /** FOX-55, with its alerts kept in step (FOX-57): unfavouriting turns a station's alerts off. */
    val favourites = FavouritesRepository(SharedPreferencesFavouritesStore(context), PushGraph.favouriteAlerts(context))

    /** FOX-92: the station cams on the webcam host, their frames and hourly history under [cacheRoot]. */
    private val camEndpoints = StationCamEndpoints(stationCamsUrl)
    private val camDirectory = File(cacheRoot, StationCamFrameCache.DIRECTORY_NAME)
    val camManifest = StationCamStore(camEndpoints, store, http)
    val camFrames = StationCamFrameCache(camDirectory, camEndpoints, http, BitmapCamImageDecoder)
    val camHistory = StationCamHistoryCache(
        File(camDirectory, StationCamHistoryCache.DIRECTORY_NAME),
        camEndpoints,
        http,
        BitmapCamImageDecoder
    )

    /** FOX-93: the CWA weather file on the webcam host, its last good copy under [cacheRoot]. */
    val weather = StationWeatherStore(stationCamsUrl, store)

    /**
     * FOX-98: Chinese-only API text (forecast text, township, address) in English on the device,
     * with ML Kit; its translations kept under [cacheRoot] for a week.
     */
    val translation = OnDeviceTranslation(
        MlKitTranslator(MlKitTranslator.unmeteredNetwork(context)),
        TranslationDiskCache(store)
    )

    /** Deletes week-old cache files. Blocking: run it off the main thread. */
    fun purgeExpiredCaches(): List<File> = OfflineCacheRetention.purge(cacheRoot)
}
