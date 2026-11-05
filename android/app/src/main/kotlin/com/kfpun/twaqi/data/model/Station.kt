package com.kfpun.twaqi.data.model

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
    val stationType: StationType = StationType.UNKNOWN
) {
    /** Name in the reader's language, never blank. */
    fun displayName(chinese: Boolean): String = StationText.displayName(if (chinese) nameLocal else name, code, id)

    /** "信義區, Keelung City": whichever parts the API supplied. [translate] gets the township first. */
    fun displayLocality(chinese: Boolean, translate: (String) -> String = { it }): String? =
        StationText.locality(township?.let(translate), if (chinese) countyLocal else county)

    /** The station's 空品區, used to group the station list. */
    fun displayArea(chinese: Boolean): String? = (if (chinese) areaLocal else area)?.takeIf { it.isNotEmpty() }
}

internal object StationText {
    fun displayName(preferred: String, code: String, id: Int): String = preferred.ifEmpty { code.ifEmpty { "#$id" } }

    fun locality(vararg parts: String?): String? =
        parts.filterNotNull().filter { it.isNotEmpty() }.takeIf { it.isNotEmpty() }?.joinToString(", ")
}
