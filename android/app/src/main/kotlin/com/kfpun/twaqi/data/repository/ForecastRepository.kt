package com.kfpun.twaqi.data.repository

import com.kfpun.twaqi.data.cache.CacheStore
import com.kfpun.twaqi.data.cache.Saved
import com.kfpun.twaqi.data.model.AqiForecast
import com.kfpun.twaqi.data.model.TaiwanTime
import com.kfpun.twaqi.data.remote.ApiClient
import com.kfpun.twaqi.data.remote.ApiFormatException
import com.kfpun.twaqi.data.remote.ApiParser
import java.io.IOException
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * The 空品區 forecast from Directus `twaqi_aqi_forecast` (iOS `AqiForecastStore`).
 *
 * A copy younger than [TTL] is used without a request. When a refresh fails the last good rows are
 * used; callers drop days before today, so yesterday's copy still shows what is left of it. A
 * response with no rows counts as a failed refresh: it is never saved and doesn't start the TTL.
 * Callers that ask while a request is in flight wait for it rather than starting another.
 */
class ForecastRepository(
    private val api: ApiClient,
    private val store: CacheStore,
    private val now: () -> Instant = Instant::now,
    private val io: CoroutineDispatcher = Dispatchers.IO
) {
    private val mutex = Mutex()
    private var forecasts: Saved<List<AqiForecast>>? = null
    private var loadedFromDisk = false

    suspend fun forecasts(): DataResult<List<AqiForecast>> = mutex.withLock {
        withContext(io) {
            if (!loadedFromDisk) {
                loadedFromDisk = true
                forecasts = forecasts ?: readSaved()
            }
            val current = forecasts
            if (current != null && Duration.between(current.savedAt, now()) < TTL) {
                return@withContext DataResult.Fresh(current.value, current.savedAt)
            }
            try {
                val body = api.forecasts(TaiwanTime.today(now()))
                val rows = ApiParser.forecasts(body)
                if (rows.isEmpty()) throw ApiFormatException("no forecast rows")
                store.write(CacheStore.FORECAST, body)
                val fetched = Saved(rows, now())
                forecasts = fetched
                DataResult.Fresh(rows, fetched.savedAt)
            } catch (e: IOException) {
                fallback(e, current)
            } catch (e: ApiFormatException) {
                fallback(e, current)
            }
        }
    }

    private fun fallback(error: Throwable, saved: Saved<List<AqiForecast>>?): DataResult<List<AqiForecast>> =
        saved?.let { DataResult.Stale(it.value, it.savedAt, error) } ?: DataResult.Failed(error)

    /** A file older than a week isn't used, even as a last good copy. */
    private fun readSaved(): Saved<List<AqiForecast>>? {
        val saved = store.read(CacheStore.FORECAST) ?: return null
        val rows = try {
            ApiParser.forecasts(saved.value)
        } catch (e: ApiFormatException) {
            return null
        }
        return if (rows.isEmpty()) null else Saved(rows, saved.savedAt)
    }

    companion object {
        /** MOENV publishes a few times a day; the Worker syncs hourly. */
        val TTL: Duration = Duration.ofMinutes(30)
    }
}
