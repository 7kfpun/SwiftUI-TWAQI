package com.kfpun.twaqi.data.remote

import com.kfpun.twaqi.BuildConfig
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response

/**
 * Where the app reads from. Real values come from `secrets.properties` through [BuildConfig];
 * tests point it at a local server.
 *
 * @property directusToken the app's Directus static token, read-only on `twaqi_aqi_forecast`
 *   (iOS reads the forecast with `DirectusFeedbackToken` too).
 */
data class ApiConfig(val apiDomain: String, val directusUrl: String, val directusToken: String) {
    companion object {
        fun fromBuildConfig(): ApiConfig = ApiConfig(
            apiDomain = BuildConfig.API_DOMAIN,
            directusUrl = BuildConfig.DIRECTUS_URL,
            directusToken = BuildConfig.DIRECTUS_FEEDBACK_TOKEN
        )
    }
}

/** The request couldn't be made, timed out, or came back without a 2xx JSON body. */
class ApiException(message: String, cause: Throwable? = null) : IOException(message, cause)

/**
 * The AQI API (`API_DOMAIN/v1/…`) and the Directus forecast read (iOS `APIManager`,
 * `AqiForecastRequest`). Returns response bodies as text so the repositories can save exactly what
 * the API sent, once it has parsed.
 */
class ApiClient(private val config: ApiConfig, private val http: OkHttpClient = defaultHttpClient()) {

    suspend fun countries(): String = get(api(COUNTRIES))

    suspend fun stations(countryCode: String): String = get(api(STATIONS) { addQueryParameter("country", countryCode) })

    suspend fun currentPollutants(countryCode: String): String =
        get(api(CURRENT_POLLUTANTS) { addQueryParameter("country", countryCode) })

    suspend fun currentPollutants(stationId: Int): String =
        get(api(CURRENT_POLLUTANTS) { addQueryParameter("station_id", stationId.toString()) })

    suspend fun historicalPollutants(stationId: Int, limit: Int = 24): String = get(
        api(HISTORICAL_POLLUTANTS) {
            addQueryParameter("station_id", stationId.toString())
            addQueryParameter("limit", limit.toString())
        }
    )

    /** `twaqi_aqi_forecast` from [today] (Taiwan day) on, archived rows left out. */
    suspend fun forecasts(today: String): String = get(
        forecastRequest(config, today) ?: throw ApiException("Directus is not configured")
    )

    private fun api(path: String, query: HttpUrl.Builder.() -> Unit = {}): Request {
        val base = config.apiDomain.trim().toHttpUrlOrNull() ?: throw ApiException("API_DOMAIN is not a URL")
        val url = base.newBuilder().addPathSegments(path).apply(query).build()
        return Request.Builder().url(url).header("Accept", "application/json").build()
    }

    private suspend fun get(request: Request): String {
        val response = try {
            http.newCall(request).await()
        } catch (e: IOException) {
            throw ApiException("request failed: ${e.message}", e)
        }
        return response.use {
            if (!it.isSuccessful) throw ApiException("HTTP ${it.code}")
            // iOS validates the content type, so an HTML error page from a proxy never parses.
            val body = it.body ?: throw ApiException("no body")
            val type = body.contentType()
            if (type != null && type.subtype != "json") throw ApiException("not JSON: $type")
            try {
                body.string()
            } catch (e: IOException) {
                throw ApiException("body failed: ${e.message}", e)
            }
        }
    }

    companion object {
        const val COUNTRIES = "v1/countries"
        const val STATIONS = "v1/stations"
        const val CURRENT_POLLUTANTS = "v1/current-pollutants"
        const val HISTORICAL_POLLUTANTS = "v1/historical-pollutants"
        const val FORECAST_COLLECTION = "items/twaqi_aqi_forecast"

        /**
         * 20 s per read, 30 s for the whole call, as iOS: on a flaky connection a screen falls back
         * to its saved copy instead of sitting on a spinner.
         */
        fun defaultHttpClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .callTimeout(30, TimeUnit.SECONDS)
            .build()

        /**
         * `GET /items/twaqi_aqi_forecast` for today onwards; null when Directus isn't configured.
         * `fields=*`, not a list: naming `content_i18n` before the token may read it fails the read.
         */
        fun forecastRequest(config: ApiConfig, today: String): Request? {
            val token = config.directusToken.trim().takeIf { it.isNotEmpty() } ?: return null
            val base = config.directusUrl.trim().takeIf { it.isNotEmpty() }?.toHttpUrlOrNull() ?: return null
            val url = base.newBuilder()
                .addPathSegments(FORECAST_COLLECTION)
                .addQueryParameter("filter[archived][_neq]", "true")
                .addQueryParameter("filter[forecast_date][_gte]", today)
                .addQueryParameter("fields", "*")
                .addQueryParameter("sort", "forecast_date,area")
                .addQueryParameter("limit", "200")
                .build()
            return Request.Builder()
                .url(url)
                .header("Authorization", "Bearer $token")
                .header("Accept", "application/json")
                .build()
        }
    }
}

private suspend fun Call.await(): Response = suspendCancellableCoroutine { continuation ->
    continuation.invokeOnCancellation { cancel() }
    enqueue(
        object : Callback {
            override fun onResponse(call: Call, response: Response) {
                continuation.resume(response) { _, value, _ -> value.close() }
            }

            override fun onFailure(call: Call, e: IOException) {
                continuation.resumeWithException(e)
            }
        }
    )
}
