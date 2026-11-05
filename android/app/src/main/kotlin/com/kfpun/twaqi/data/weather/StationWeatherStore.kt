package com.kfpun.twaqi.data.weather

import com.kfpun.twaqi.data.cache.CacheStore
import com.kfpun.twaqi.data.cache.Saved
import java.io.IOException
import java.time.Duration
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Fetches and caches the CWA weather file ([WeatherFile]; iOS `StationWeatherStore`).
 *
 * The last good file is kept under the offline cache root ([CACHE_FILE]), so a station opened
 * offline still has its weather; [StationWeatherMatcher] then drops readings and periods that have
 * aged out. A copy younger than [TTL] is used as is; an older one is refreshed, and kept if the
 * refresh fails. A file older than a week is never read ([CacheStore.read]) and is purged.
 *
 * Callers that ask while a request is in flight wait for it rather than starting another.
 *
 * @param baseUrl the webcam host (`STATION_CAMS_URL`); blank or not a URL means no request, only
 *   the saved file.
 */
class StationWeatherStore(
    baseUrl: String,
    private val store: CacheStore,
    private val http: OkHttpClient = defaultHttpClient(),
    private val now: () -> Instant = Instant::now,
    private val io: CoroutineDispatcher = Dispatchers.IO
) {
    private val url: HttpUrl? = fileUrl(baseUrl)
    private val mutex = Mutex()
    private var file: Saved<WeatherFile>? = null

    /** The latest file, or null if there has never been one to read (offline first launch). */
    suspend fun weather(): WeatherFile? = mutex.withLock {
        withContext(io) {
            val current = file ?: readSaved()?.also { file = it }
            if (current != null && Duration.between(current.savedAt, now()) < TTL) {
                return@withContext current.value
            }
            // A failed refresh keeps the last good file and leaves its time alone, so the next
            // open asks again.
            fetch()?.let { (body, parsed) ->
                store.write(CACHE_FILE, body)
                file = Saved(parsed, now())
            }
            file?.value
        }
    }

    /** The body and its parse, or null when the request failed or the body isn't the file. */
    private fun fetch(): Pair<String, WeatherFile>? {
        val url = url ?: return null
        val request = Request.Builder().url(url).header("Accept", "application/json").build()
        return try {
            http.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return null
                val body = response.body?.string() ?: return null
                body to WeatherFile.parse(body)
            }
        } catch (e: IOException) {
            null
        } catch (e: WeatherFormatException) {
            null
        }
    }

    private fun readSaved(): Saved<WeatherFile>? {
        val saved = store.read(CACHE_FILE) ?: return null
        return try {
            Saved(WeatherFile.parse(saved.value), saved.savedAt)
        } catch (e: WeatherFormatException) {
            null
        }
    }

    companion object {
        /** The Worker syncs hourly; observations change every 10 minutes at CWA. */
        val TTL: Duration = Duration.ofMinutes(30)

        /** Under the offline cache root, so the week-old purge covers it (iOS `cwa-weather.json`). */
        const val CACHE_FILE = "cwa-weather.json"

        /** `<base>/weather/latest.json`; null when the base isn't configured. */
        fun fileUrl(baseUrl: String): HttpUrl? = baseUrl.trim().takeIf { it.isNotEmpty() }?.toHttpUrlOrNull()
            ?.newBuilder()?.addPathSegments(WeatherFile.PATH)?.build()

        /** 20 s, as iOS: without it the card could wait a long time before using the saved file. */
        fun defaultHttpClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .callTimeout(20, TimeUnit.SECONDS)
            .build()
    }
}
