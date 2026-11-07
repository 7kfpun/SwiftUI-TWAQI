package com.kfpun.twaqi.data.model

import com.kfpun.twaqi.data.places.TaiwanPlaceNames

/**
 * A station from `/v1/stations`, or the `station` object on `/v1/historical-pollutants`
 * (iOS `Station`). Names and places are kept in both languages; the `display…` helpers pick one,
 * given `chinese = AppLocale.isChinese(context)` (iOS `Locale.isChinese`).
 *
 * Micro-sensor stations have no address, area, county or township, so those are nullable.
 */
data class Station(
    val id: Int,
    val countryId: Int,
    val countryCode: String,
    val code: String,
    val lat: Double,
    val lon: Double,
    val imageUrl: String?,
    val name: String,
    val nameLocal: String,
    val address: String? = null,
    val area: String? = null,
    val areaLocal: String? = null,
    val county: String? = null,
    val countyLocal: String? = null,
    val township: String? = null,
    val stationType: StationType = StationType.UNKNOWN,
    /** The township in English, if the API ever sends one (today it sends Chinese only). */
    val townshipEn: String? = null
) {
    /** Name in the reader's language, never blank. */
    fun displayName(chinese: Boolean): String = StationText.displayName(if (chinese) nameLocal else name, code, id)

    /**
     * "Xinyi District, Keelung City" (信義區, 基隆市 in Chinese): whichever parts the API supplied,
     * with English names from [places] (FOX-114), never machine-translated.
     */
    fun displayLocality(chinese: Boolean, places: TaiwanPlaceNames = TaiwanPlaceNames.EMPTY): String? =
        StationText.locality(chinese, township, townshipEn, county, countyLocal, places)

    /** The station's 空品區, used to group the station list. */
    fun displayArea(chinese: Boolean): String? = (if (chinese) areaLocal else area)?.takeIf { it.isNotEmpty() }
}

internal object StationText {
    fun displayName(preferred: String, code: String, id: Int): String = preferred.ifEmpty { code.ifEmpty { "#$id" } }

    fun locality(vararg parts: String?): String? =
        parts.filterNotNull().filter { it.isNotEmpty() }.takeIf { it.isNotEmpty() }?.joinToString(", ")

    /**
     * Township, then county (FOX-114). Chinese shows the API's Chinese names. Otherwise each part
     * is the API's English name, else the official one from [places], else the Chinese as written:
     * place names are never machine-translated (ML Kit made 新店區 "New store area").
     */
    fun locality(
        chinese: Boolean,
        township: String?,
        townshipEn: String?,
        county: String?,
        countyLocal: String?,
        places: TaiwanPlaceNames
    ): String? = if (chinese) {
        locality(township, countyLocal)
    } else {
        locality(
            townshipEn?.takeIf { it.isNotBlank() } ?: places.township(township, countyLocal) ?: township,
            county?.takeIf { it.isNotBlank() } ?: places.county(countyLocal) ?: countyLocal
        )
    }
}
