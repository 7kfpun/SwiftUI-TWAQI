package com.kfpun.twaqi.data.repository

import com.kfpun.twaqi.data.cache.CacheStore
import com.kfpun.twaqi.data.cache.PollutantCache
import com.kfpun.twaqi.data.cache.Saved
import com.kfpun.twaqi.data.model.Country
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.model.Station
import com.kfpun.twaqi.data.model.StationHistory
import com.kfpun.twaqi.data.remote.ApiClient
import com.kfpun.twaqi.data.remote.ApiFormatException
import com.kfpun.twaqi.data.remote.ApiParser
import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Countries, stations and readings from the AQI API, each falling back to its last good copy.
 *
 * Only a response that parses is saved, and an empty country or station list never replaces a
 * saved one (iOS `DetailsListViewModel`, `APIManager`). The `saved…` reads are for showing the
 * last copy at once while the refresh runs.
 */
class AirQualityRepository(
    private val api: ApiClient,
    private val store: CacheStore,
    private val pollutantCache: PollutantCache,
    private val now: () -> Instant = Instant::now,
    private val io: CoroutineDispatcher = Dispatchers.IO
) {
    suspend fun countries(): DataResult<List<Country>> = fetch(
        request = { api.countries() },
        parse = ApiParser::countries,
        save = { body, list -> if (list.isNotEmpty()) store.write(CacheStore.COUNTRIES, body) },
        saved = ::savedCountries
    )

    suspend fun stations(countryCode: String = Country.SUPPORTED_CODE): DataResult<List<Station>> = fetch(
        request = { api.stations(countryCode) },
        parse = ApiParser::stations,
        save = { body, list -> if (list.isNotEmpty()) store.write(CacheStore.stations(countryCode), body) },
        saved = { savedStations(countryCode) }
    )

    /** Current readings for a whole country, for the map and list. */
    suspend fun currentPollutants(countryCode: String = Country.SUPPORTED_CODE): DataResult<List<Pollutant>> = fetch(
        request = { api.currentPollutants(countryCode) },
        parse = ApiParser::pollutants,
        save = { body, list -> if (list.isNotEmpty()) pollutantCache.save(countryCode, body) },
        saved = { savedPollutants(countryCode) }
    )

    /**
     * One station's current reading, for its own screen. Falls back to the newest reading seen from
     * either endpoint. When the API answers with no reading for the station (retired, or offline for
     * maintenance), the error is [NoCurrentReadingException]: not an outage.
     */
    suspend fun currentPollutant(stationId: Int): DataResult<Pollutant> = withContext(io) {
        try {
            val body = api.currentPollutants(stationId)
            val list = ApiParser.pollutants(body)
            pollutantCache.saveStations(body)
            val reading = list.firstOrNull { it.stationId == stationId } ?: list.firstOrNull()
            if (reading != null) {
                DataResult.Fresh(reading, now())
            } else {
                fallback(NoCurrentReadingException(stationId), pollutantCache.pollutant(stationId))
            }
        } catch (e: IOException) {
            fallback(e, pollutantCache.pollutant(stationId))
        } catch (e: ApiFormatException) {
            fallback(e, pollutantCache.pollutant(stationId))
        }
    }

    /**
     * Current readings for [stationIds] (Favourites), in the API's order; each is saved for the
     * station page and the next offline open. A failure carries no fallback: the caller shows
     * [savedPollutants] for the ids it has.
     */
    suspend fun currentPollutants(stationIds: List<Int>): DataResult<List<Pollutant>> = withContext(io) {
        try {
            val body = api.currentPollutants(stationIds)
            val list = ApiParser.pollutants(body)
            pollutantCache.saveStations(body)
            DataResult.Fresh(list, now())
        } catch (e: IOException) {
            DataResult.Failed(e)
        } catch (e: ApiFormatException) {
            DataResult.Failed(e)
        }
    }

    /** Last saved readings for [stationIds] (Favourites), in that order. */
    suspend fun savedPollutants(stationIds: List<Int>): List<Saved<Pollutant>> =
        withContext(io) { pollutantCache.pollutants(stationIds) }

    /** The last 24 hours, oldest first. Not cached, as on iOS. */
    suspend fun history(stationId: Int, limit: Int = 24): DataResult<StationHistory> = withContext(io) {
        try {
            DataResult.Fresh(ApiParser.history(api.historicalPollutants(stationId, limit)), now())
        } catch (e: IOException) {
            DataResult.Failed(e)
        } catch (e: ApiFormatException) {
            DataResult.Failed(e)
        }
    }

    suspend fun savedCountries(): Saved<List<Country>>? = withContext(io) {
        readSaved(CacheStore.COUNTRIES, ApiParser::countries)
    }

    suspend fun savedStations(countryCode: String = Country.SUPPORTED_CODE): Saved<List<Station>>? =
        withContext(io) { readSaved(CacheStore.stations(countryCode), ApiParser::stations) }

    suspend fun savedPollutants(countryCode: String = Country.SUPPORTED_CODE): Saved<List<Pollutant>>? =
        withContext(io) { pollutantCache.pollutants(countryCode) }

    private fun <T> readSaved(name: String, parse: (String) -> List<T>): Saved<List<T>>? {
        val saved = store.read(name) ?: return null
        // A file an older build wrote may no longer parse; refetch instead.
        val list = try {
            parse(saved.value)
        } catch (e: ApiFormatException) {
            return null
        }
        return if (list.isEmpty()) null else Saved(list, saved.savedAt)
    }

    private suspend fun <T> fetch(
        request: suspend () -> String,
        parse: (String) -> List<T>,
        save: (String, List<T>) -> Unit,
        saved: suspend () -> Saved<List<T>>?
    ): DataResult<List<T>> = withContext(io) {
        try {
            val body = request()
            val list = parse(body)
            save(body, list)
            if (list.isEmpty()) {
                // An empty list is no better than a failure when there is a saved one.
                saved()?.let { DataResult.Stale(it.value, it.savedAt, ApiFormatException("empty response")) }
                    ?: DataResult.Fresh(list, now())
            } else {
                DataResult.Fresh(list, now())
            }
        } catch (e: IOException) {
            fallback(e, saved())
        } catch (e: ApiFormatException) {
            fallback(e, saved())
        }
    }

    private fun <T> fallback(error: Throwable, saved: Saved<T>?): DataResult<T> =
        saved?.let { DataResult.Stale(it.value, it.savedAt, error) } ?: DataResult.Failed(error)
}

/** The API answered and has no current reading for [stationId] (iOS `DetailsViewModel.isNotReporting`). */
class NoCurrentReadingException(val stationId: Int) : Exception("no reading for $stationId")
