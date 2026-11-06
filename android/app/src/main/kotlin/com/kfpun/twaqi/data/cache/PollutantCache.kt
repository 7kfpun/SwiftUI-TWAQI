package com.kfpun.twaqi.data.cache

import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.remote.ApiFormatException
import com.kfpun.twaqi.data.remote.ApiParser
import java.time.Instant
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.put

/**
 * Last good current readings, for when the AQI API can't be reached (iOS `PollutantCache`).
 *
 * Two files under the cache root:
 * - `pollutants-{country}.json`: the country response as the API sent it, for the map.
 * - `pollutants-stations.json`: the newest reading seen for each station, from either endpoint, so
 *   a station the map has shown can be opened offline even if its own screen never loaded.
 *
 * Nothing older than [OfflineCacheRetention.maxAge] is returned. Each reading carries its own
 * `publish_time`, so a stale one says how old it is.
 */
class PollutantCache(private val store: CacheStore, private val now: () -> Instant = Instant::now) {

    private class Stored(val savedAt: Instant, val json: JsonObject, val pollutant: Pollutant)

    /** Station id → newest reading. Loaded from disk on first use. */
    private var stations: MutableMap<Int, Stored>? = null

    /** A successful `current-pollutants?country=` body. Ignored when it doesn't parse. */
    @Synchronized
    fun save(countryCode: String, body: String) {
        if (!parses(body)) return
        store.write(countryFileName(countryCode), body)
        merge(body)
    }

    /** A successful `current-pollutants?station_id=` body. */
    @Synchronized
    fun saveStations(body: String) {
        if (parses(body)) merge(body)
    }

    /** The last country response younger than a week, or null. */
    @Synchronized
    fun pollutants(countryCode: String): Saved<List<Pollutant>>? {
        val saved = store.read(countryFileName(countryCode)) ?: return null
        val pollutants = try {
            ApiParser.pollutants(saved.value)
        } catch (e: ApiFormatException) {
            return null
        }
        return if (pollutants.isEmpty()) null else Saved(pollutants, saved.savedAt)
    }

    /** The last reading of each of [stationIds] that has one younger than a week, in the order asked. */
    @Synchronized
    fun pollutants(stationIds: List<Int>): List<Saved<Pollutant>> {
        val loaded = loadStations()
        val date = now()
        return stationIds.mapNotNull { id ->
            loaded[id]?.takeIf {
                !OfflineCacheRetention.isExpired(it.savedAt, date)
            }?.let { Saved(it.pollutant, it.savedAt) }
        }
    }

    fun pollutant(stationId: Int): Saved<Pollutant>? = pollutants(listOf(stationId)).firstOrNull()

    private fun parses(body: String): Boolean = try {
        ApiParser.successData(body)
        true
    } catch (e: ApiFormatException) {
        false
    }

    private fun merge(body: String) {
        val objects = try {
            ApiParser.successData(body).second
        } catch (e: ApiFormatException) {
            return
        }
        val merged = loadStations()
        val savedAt = now()
        for (json in objects) {
            val pollutant = ApiParser.pollutant(json) ?: continue
            merged[pollutant.stationId] = Stored(savedAt, json, pollutant)
        }
        merged.entries.removeAll { OfflineCacheRetention.isExpired(it.value.savedAt, savedAt) }

        val file = buildJsonObject {
            put(
                "stations",
                JsonObject(
                    merged.mapKeys { it.key.toString() }.mapValues { (_, stored) ->
                        buildJsonObject {
                            put("saved_at", stored.savedAt.epochSecond.toDouble() + stored.savedAt.nano / 1e9)
                            put("pollutant", stored.json)
                        }
                    }
                )
            )
        }
        store.write(STATIONS_FILE_NAME, file.toString())
    }

    private fun loadStations(): MutableMap<Int, Stored> {
        stations?.let { return it }
        val loaded = HashMap<Int, Stored>()
        stations = loaded

        val text = store.read(STATIONS_FILE_NAME)?.value ?: return loaded
        val entries = try {
            (ApiParser.element(text) as? JsonObject)?.get("stations") as? JsonObject
        } catch (e: ApiFormatException) {
            null
        } ?: return loaded

        val date = now()
        for (entry in entries.values) {
            val obj = entry as? JsonObject ?: continue
            val seconds = (obj["saved_at"] as? JsonPrimitive)?.doubleOrNull ?: continue
            val savedAt = Instant.ofEpochMilli((seconds * 1000).toLong())
            if (OfflineCacheRetention.isExpired(savedAt, date)) continue
            val json = obj["pollutant"] as? JsonObject ?: continue
            // A file an older build wrote may no longer parse; skip it.
            val pollutant = ApiParser.pollutant(json) ?: continue
            loaded[pollutant.stationId] = Stored(savedAt, json, pollutant)
        }
        return loaded
    }

    companion object {
        const val STATIONS_FILE_NAME = "pollutants-stations.json"

        fun countryFileName(countryCode: String) = "pollutants-$countryCode.json"
    }
}
