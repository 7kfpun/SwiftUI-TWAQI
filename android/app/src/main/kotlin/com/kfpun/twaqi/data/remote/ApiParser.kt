package com.kfpun.twaqi.data.remote

import com.kfpun.twaqi.data.model.AqiForecast
import com.kfpun.twaqi.data.model.Country
import com.kfpun.twaqi.data.model.HistoricalPollutant
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.model.Station
import com.kfpun.twaqi.data.model.StationHistory
import com.kfpun.twaqi.data.model.StationType
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull

/** The response body wasn't the JSON the endpoint promises (or `success` wasn't true). */
class ApiFormatException(message: String) : Exception(message)

/**
 * Parses the AQI API and Directus responses into models, as tolerantly as iOS does
 * (`StationParsing.swift`, `Pollutants.swift`, `APIManager.swift`, `AqiForecast.swift`).
 *
 * Every nested object (`name`, `address`, `area`, `additional_info`) may be `{}` for micro-sensor
 * stations, so each field degrades to null or a fallback rather than failing the response. A
 * reading missing one of its numbers is dropped, as the iOS decoder does.
 */
object ApiParser {
    private val json = Json { ignoreUnknownKeys = true }

    fun element(body: String): JsonElement = try {
        json.parseToJsonElement(body)
    } catch (e: IllegalArgumentException) {
        throw ApiFormatException("not JSON: ${e.message}")
    }

    /** `{ "success": true, "data": [...] }` → the `data` array; throws on anything else. */
    fun successData(body: String): Pair<JsonObject, List<JsonObject>> {
        val root = element(body) as? JsonObject ?: throw ApiFormatException("not an object")
        if (root.bool("success") != true) throw ApiFormatException("success is not true")
        val data = root["data"] as? JsonArray ?: throw ApiFormatException("no data array")
        return root to data.filterIsInstance<JsonObject>()
    }

    fun countries(body: String): List<Country> = successData(body).second.map(::country)

    fun stations(body: String): List<Station> = successData(body).second.map(::station)

    /** `/v1/current-pollutants`. Throws when the body isn't a success response. */
    fun pollutants(body: String): List<Pollutant> = successData(body).second.mapNotNull(::pollutant)

    fun history(body: String): StationHistory {
        val (root, data) = successData(body)
        val station = (root["station"] as? JsonObject)?.let(::station) ?: station(JsonObject(emptyMap()))
        return StationHistory(station, data.map(::historical))
    }

    /** Directus list response, `{ "data": [...] }`. A row without `area` or `forecast_date` is dropped. */
    fun forecasts(body: String): List<AqiForecast> {
        val root = element(body) as? JsonObject ?: throw ApiFormatException("not an object")
        val data = root["data"] as? JsonArray ?: throw ApiFormatException("no data array")
        return data.filterIsInstance<JsonObject>().mapNotNull(::forecast)
    }

    fun country(o: JsonObject): Country {
        val code = o.string("code") ?: ""
        val names = o.obj("name")
        val en = names?.string("en")
        val zh = names?.string("zh")
        val th = names?.string("th")
        return Country(
            id = o.int("id") ?: 0,
            code = code,
            lat = o.double("lat") ?: 0.0,
            lon = o.double("lon") ?: 0.0,
            zoom = (o.double("zoom") ?: 0.0).toFloat(),
            name = en ?: zh ?: th ?: code.uppercase(),
            nameLocal = zh ?: th ?: en ?: code.uppercase()
        )
    }

    /** `/v1/stations` row, or the `station` object on `/v1/historical-pollutants`. */
    fun station(o: JsonObject): Station {
        val code = o.string("code") ?: ""
        val names = o.obj("name")
        val en = names?.string("en")
        val zh = names?.string("zh")
        val th = names?.string("th")
        val info = o.obj("additional_info")
        return Station(
            id = o.int("id") ?: 0,
            // The stations endpoint has used both cases.
            countryId = o.int("countryId") ?: o.int("country_id") ?: 0,
            countryCode = o.string("countryCode") ?: o.string("country_code") ?: "",
            code = code,
            lat = o.double("lat") ?: 0.0,
            lon = o.double("lon") ?: 0.0,
            imageUrl = o.string("image_url")?.takeIf { it.isNotEmpty() },
            name = en ?: zh ?: th ?: code,
            nameLocal = zh ?: th ?: en ?: code,
            address = o.obj("address")?.string("zh"),
            area = o.obj("area")?.string("en"),
            areaLocal = o.obj("area")?.string("zh"),
            county = info?.obj("county")?.string("en"),
            countyLocal = info?.obj("county")?.string("zh"),
            township = info?.obj("township")?.string("zh"),
            stationType = StationType.fromApi(o.string("station_type"))
        )
    }

    /** A current reading; null when a required number is missing, as iOS's decoder fails it. */
    fun pollutant(o: JsonObject): Pollutant? {
        val names = o.obj("name")
        val en = names?.string("en")
        val zh = names?.string("zh")
        val th = names?.string("th")
        val info = o.obj("additional_info")
        return Pollutant(
            stationId = o.int("station_id") ?: return null,
            code = o.string("code") ?: "",
            lat = o.double("lat") ?: return null,
            lon = o.double("lon") ?: return null,
            aqi = o.double("aqi") ?: return null,
            pm25 = o.double("pm25") ?: return null,
            pm10 = o.double("pm10") ?: return null,
            no2 = o.double("no2") ?: return null,
            so2 = o.double("so2") ?: return null,
            co = o.double("co") ?: return null,
            o3 = o.double("o3") ?: return null,
            windDirection = o.double("wind_direction") ?: return null,
            windSpeed = o.double("wind_speed") ?: return null,
            publishTime = o.string("publish_time") ?: return null,
            name = en ?: zh ?: th ?: "",
            nameLocal = zh ?: th ?: en ?: "",
            address = o.obj("address")?.string("zh"),
            area = o.obj("area")?.string("en"),
            areaLocal = o.obj("area")?.string("zh"),
            county = info?.obj("county")?.string("en"),
            countyLocal = info?.obj("county")?.string("zh"),
            township = info?.obj("township")?.string("zh"),
            stationType = StationType.fromApi(o.string("station_type")),
            imageUrl = o.string("image_url")?.takeIf { it.isNotEmpty() }
        )
    }

    fun historical(o: JsonObject): HistoricalPollutant = HistoricalPollutant(
        aqi = o.double("aqi") ?: 0.0,
        pm25 = o.double("pm25") ?: 0.0,
        pm10 = o.double("pm10") ?: 0.0,
        no2 = o.double("no2") ?: 0.0,
        so2 = o.double("so2") ?: 0.0,
        co = o.double("co") ?: 0.0,
        o3 = o.double("o3") ?: 0.0,
        windDirection = o.double("wind_direction") ?: 0.0,
        windSpeed = o.double("wind_speed") ?: 0.0,
        publishTime = o.string("publish_time") ?: ""
    )

    fun forecast(o: JsonObject): AqiForecast? = AqiForecast(
        area = o.string("area") ?: return null,
        forecastDate = o.string("forecast_date") ?: return null,
        aqi = o.int("aqi"),
        majorPollutant = o.string("major_pollutant"),
        minorPollutant = o.string("minor_pollutant"),
        minorPollutantAqi = o.int("minor_pollutant_aqi"),
        content = o.string("content"),
        publishTime = o.string("publish_time"),
        // Optional extra: a malformed map costs the translation, never the row.
        contentI18n = o.obj("content_i18n")?.let { map ->
            val strings = map.mapValues { (_, value) -> (value as? JsonPrimitive)?.takeIf { it.isString }?.content }
            if (strings.values.any { it == null }) null else strings.mapValues { it.value!! }
        }
    )
}

private fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject

private fun JsonObject.primitive(key: String): JsonPrimitive? = (this[key] as? JsonPrimitive)?.takeIf {
    it !is JsonNull
}

private fun JsonObject.string(key: String): String? = primitive(key)?.takeIf { it.isString }?.content

private fun JsonObject.double(key: String): Double? = primitive(key)?.takeIf { !it.isString }?.doubleOrNull

private fun JsonObject.int(key: String): Int? = primitive(key)?.takeIf { !it.isString }?.let { p ->
    p.intOrNull ?: p.doubleOrNull?.takeIf { it % 1.0 == 0.0 }?.toInt()
}

private fun JsonObject.bool(key: String): Boolean? = primitive(key)?.booleanOrNull
