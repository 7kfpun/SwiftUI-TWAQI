package com.kfpun.twaqi.data.model

/**
 * A country from `/v1/countries` (iOS `Country`). Only [SUPPORTED_ID] (Taiwan) works end to end:
 * search, 24 h history and alerts. Other countries' stations are context only on the map.
 */
data class Country(
    val id: Int,
    val code: String,
    val lat: Double,
    val lon: Double,
    val zoom: Float,
    val name: String,
    val nameLocal: String
) {
    val isSupported: Boolean get() = id == SUPPORTED_ID

    /** Placeholder rows come with null-island coordinates; they never take part in nearest-country search. */
    val hasValidLocation: Boolean get() = !(lat == 0.0 && lon == 0.0)

    /** Never blank: falls back through the other language, then the code. */
    fun displayName(chinese: Boolean = AppLocale.isChinese()): String {
        val preferred = if (chinese) nameLocal else name
        if (preferred.isNotEmpty()) return preferred
        val alternate = if (chinese) name else nameLocal
        if (alternate.isNotEmpty()) return alternate
        return code.uppercase()
    }

    companion object {
        const val SUPPORTED_ID = 3

        /** The supported country's code, used until the countries list has loaded. */
        const val SUPPORTED_CODE = "twn"
    }
}
