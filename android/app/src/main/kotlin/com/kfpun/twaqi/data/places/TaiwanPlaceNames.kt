package com.kfpun.twaqi.data.places

import android.content.Context
import android.util.Log
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Taiwan's 22 counties and cities and 368 townships and districts with their official romanised
 * names (FOX-114): 新店區 Xindian District, 大安區 Da'an District, 新北市 New Taipei City.
 *
 * The API gives a station's township in Chinese only. Machine translation garbles place names
 * (新店區 came out as "New store area"), so they are looked up here and never sent to the
 * translator. The table is the asset [ASSET], made by `tools/make_taiwan_place_names.py` from the
 * open data county and township Chinese-English file; regenerate it there, never by hand.
 */
class TaiwanPlaceNames internal constructor(
    private val counties: Map<String, String>,
    private val townships: Map<String, Map<String, String>>
) {
    /**
     * Townships by name alone, for a name with no county or a county the table doesn't know. A
     * name that two counties romanise differently is left out; today every name has one English
     * form (大安區 is Da'an District in Taipei and in Taichung).
     */
    private val townshipsByName: Map<String, String> = townships.values
        .flatMap { it.entries }
        .groupBy({ it.key }, { it.value })
        .mapNotNull { (name, english) -> english.distinct().singleOrNull()?.let { name to it } }
        .toMap()

    val countyCount: Int get() = counties.size
    val townshipCount: Int get() = townships.values.sumOf { it.size }

    /** "新北市" → "New Taipei City"; null for a name the table doesn't have. */
    fun county(chinese: String?): String? = chinese?.let { counties[normalise(it)] }

    /**
     * "新店區" → "Xindian District"; [county] (Chinese) picks between namesakes. Null for a name the
     * table doesn't have.
     */
    fun township(chinese: String?, county: String? = null): String? {
        val name = chinese?.let(::normalise)?.takeIf { it.isNotEmpty() } ?: return null
        return county?.let { townships[normalise(it)]?.get(name) } ?: townshipsByName[name]
    }

    companion object {
        const val ASSET = "place_names/taiwan_place_names.json"

        private const val TAG = "TWAQIPlaces"

        /** An empty table: every lookup misses, so the Chinese names show. */
        val EMPTY = TaiwanPlaceNames(emptyMap(), emptyMap())

        @Volatile
        private var bundled: TaiwanPlaceNames? = null

        /** The bundled table, read once per process. Empty if the asset can't be read. */
        fun get(context: Context): TaiwanPlaceNames = bundled ?: synchronized(this) {
            bundled ?: load(context).also { bundled = it }
        }

        private fun load(context: Context): TaiwanPlaceNames = try {
            context.applicationContext.assets.open(ASSET).bufferedReader(Charsets.UTF_8).use { parse(it.readText()) }
        } catch (e: Exception) {
            Log.w(TAG, "Place names: ${e.message}")
            EMPTY
        }

        /** The generator's JSON: `{"counties": {zh: en}, "townships": {county zh: {zh: en}}}`. */
        fun parse(json: String): TaiwanPlaceNames {
            val root = Json.parseToJsonElement(json).jsonObject
            fun JsonObject.strings(): Map<String, String> =
                mapNotNull { (key, value) -> value.jsonPrimitive.contentOrNull?.let { key to it } }.toMap()
            val counties = root["counties"]?.jsonObject?.strings().orEmpty()
            val townships = root["townships"]?.jsonObject
                ?.mapValues { (_, names) -> names.jsonObject.strings() }
                .orEmpty()
            return TaiwanPlaceNames(counties, townships)
        }

        /** The API and MOENV write both 台 and 臺 (台北市, 臺北市); the table uses 臺. */
        internal fun normalise(name: String): String = name.trim().replace('台', '臺')
    }
}
