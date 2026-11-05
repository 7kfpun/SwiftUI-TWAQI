package com.kfpun.twaqi.watch.data

import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request

/** The request couldn't be made, or came back without a success body. */
class WatchApiException(message: String, cause: Throwable? = null) : IOException(message, cause)

/**
 * The pollutant endpoints the watch needs (iOS `WatchAPI`): two GETs, so its own small client
 * rather than the phone's repositories. [apiDomain] comes from `secrets.properties`
 * (`API_DOMAIN`), as in the phone app.
 */
class WatchApi(private val apiDomain: String, private val http: OkHttpClient = defaultHttpClient()) {

    /** Every station in the country, in the API's order (roughly north to south). */
    suspend fun currentPollutants(countryCode: String = COUNTRY_CODE): List<WatchReading> =
        WatchApiParser.readings(get(CURRENT_POLLUTANTS, mapOf("country" to countryCode)))

    suspend fun currentPollutant(stationId: Int): WatchReading? =
        WatchApiParser.readings(get(CURRENT_POLLUTANTS, mapOf("station_id" to stationId.toString()))).firstOrNull()

    /** Several stations in one request, as the phone's Favourites asks: `station_id=126,85`. */
    suspend fun currentPollutants(stationIds: List<Int>): List<WatchReading> {
        if (stationIds.isEmpty()) return emptyList()
        return WatchApiParser.readings(get(CURRENT_POLLUTANTS, mapOf("station_id" to stationIds.joinToString(","))))
    }

    /** Hourly readings, oldest first. */
    suspend fun history(stationId: Int, limit: Int): List<HistoryPoint> = WatchApiParser.history(
        get(HISTORICAL_POLLUTANTS, mapOf("station_id" to stationId.toString(), "limit" to limit.toString()))
    )

    private suspend fun get(path: String, query: Map<String, String>): String = withContext(Dispatchers.IO) {
        val base = apiDomain.trim().toHttpUrlOrNull() ?: throw WatchApiException("API_DOMAIN is not a URL")
        val url = base.newBuilder().addPathSegments(path).apply {
            query.forEach { (key, value) -> addQueryParameter(key, value) }
        }.build()
        val request = Request.Builder().url(url).header("Accept", "application/json").build()
        try {
            http.newCall(request).execute().use { response ->
                if (!response.isSuccessful) throw WatchApiException("HTTP ${response.code}")
                response.body?.string() ?: throw WatchApiException("no body")
            }
        } catch (e: WatchApiException) {
            throw e
        } catch (e: IOException) {
            throw WatchApiException("request failed: ${e.message}", e)
        }
    }

    companion object {
        /** The app is scoped to one supported country, like the phone app. */
        const val COUNTRY_CODE = "twn"

        const val CURRENT_POLLUTANTS = "v1/current-pollutants"
        const val HISTORICAL_POLLUTANTS = "v1/historical-pollutants"

        /**
         * Home when the reader shares no location: 中正區, Taipei (district office). No station
         * sits in the district, so the one nearest this point stands in for it (iOS `defaultLocation`).
         */
        const val DEFAULT_LATITUDE = 25.0326
        const val DEFAULT_LONGITUDE = 121.5199

        /**
         * 20 s per read, as iOS: longer than a complication update is given, so it falls back to
         * the cached reading instead.
         */
        fun defaultHttpClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .callTimeout(25, TimeUnit.SECONDS)
            .build()

        /** The station nearest the point, or null for an empty list. Stations without a position are skipped. */
        fun closest(latitude: Double, longitude: Double, stations: List<WatchReading>): WatchReading? =
            stations.filter { it.latitude != null && it.longitude != null }
                .minByOrNull { distanceMeters(latitude, longitude, it.latitude!!, it.longitude!!) }

        /** Great-circle distance in metres. */
        fun distanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
            val dLat = Math.toRadians(lat2 - lat1)
            val dLon = Math.toRadians(lon2 - lon1)
            val a = sin(dLat / 2).pow(2) + cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLon / 2).pow(2)
            return 2 * EARTH_RADIUS_METERS * asin(sqrt(a))
        }

        private const val EARTH_RADIUS_METERS = 6_371_000.0
    }
}

/**
 * Reads the API's JSON leniently, as the phone's `ApiParser`: a reading missing one of its numbers
 * is dropped, and a history hour missing one counts it as 0 (iOS `HistoryResponse`).
 */
object WatchApiParser {
    /** `{ "success": true, "data": [...] }` → the readings; throws on anything else. */
    fun readings(body: String): List<WatchReading> = successData(body).mapNotNull(::reading)

    fun history(body: String): List<HistoryPoint> = successData(body).map { o ->
        HistoryPoint(
            aqi = o.double("aqi") ?: 0.0,
            pm25 = o.double("pm25") ?: 0.0,
            pm10 = o.double("pm10") ?: 0.0,
            o3 = o.double("o3") ?: 0.0,
            co = o.double("co") ?: 0.0,
            so2 = o.double("so2") ?: 0.0,
            no2 = o.double("no2") ?: 0.0,
            publishTime = o.string("publish_time") ?: ""
        )
    }

    fun reading(o: JsonObject): WatchReading? {
        val names = o.obj("name")
        val en = names?.string("en")
        val zh = names?.string("zh")
        val info = o.obj("additional_info")
        return WatchReading(
            stationId = o.int("station_id") ?: return null,
            code = o.string("code") ?: "",
            name = en ?: zh ?: "",
            nameLocal = zh ?: en ?: "",
            aqi = o.double("aqi") ?: return null,
            pm25 = o.double("pm25") ?: return null,
            pm10 = o.double("pm10") ?: return null,
            o3 = o.double("o3") ?: return null,
            co = o.double("co") ?: return null,
            so2 = o.double("so2") ?: return null,
            no2 = o.double("no2") ?: return null,
            windDirection = o.double("wind_direction") ?: return null,
            windSpeed = o.double("wind_speed") ?: return null,
            publishTime = o.string("publish_time") ?: return null,
            latitude = o.double("lat"),
            longitude = o.double("lon"),
            county = info?.obj("county")?.string("en"),
            countyLocal = info?.obj("county")?.string("zh"),
            township = info?.obj("township")?.string("zh")
        )
    }

    private fun successData(body: String): List<JsonObject> {
        val root = WatchJson.parse(body) as? JsonObject ?: throw WatchApiException("not an object")
        if (root.primitive("success")?.booleanOrNull != true) throw WatchApiException("success is not true")
        val data = root["data"] as? JsonArray ?: throw WatchApiException("no data array")
        return data.filterIsInstance<JsonObject>()
    }
}

internal object WatchJson {
    private val json = Json { ignoreUnknownKeys = true }

    fun parse(text: String?): JsonElement? = text?.let { runCatching { json.parseToJsonElement(it) }.getOrNull() }
}
