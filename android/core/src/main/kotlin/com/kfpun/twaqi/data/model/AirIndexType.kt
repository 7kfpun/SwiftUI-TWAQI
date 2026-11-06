package com.kfpun.twaqi.data.model

/**
 * The indices a reading carries (iOS `AirIndexTypes`). Order is the order the app lists them in.
 *
 * [label] and [unit] are the same in every language, as on iOS. [decimals] is how many decimal
 * places a value is shown with.
 */
enum class AirIndexType(val key: String, val label: String, val unit: String, val decimals: Int) {
    AQI("aqi", "AQI", "", 0),
    PM25("pm25", "PM2.5", "μg/m3", 0),
    PM10("pm10", "PM10", "μg/m3", 0),
    O3("o3", "O3", "ppb", 1),
    CO("co", "CO", "ppm", 2),
    SO2("so2", "SO2", "ppb", 1),
    NO2("no2", "NO2", "ppb", 1)
    ;

    /** `value` with this index's decimal places, e.g. `"0.33"` for CO. */
    fun format(value: Double): String = String.format(java.util.Locale.US, "%.${decimals}f", value)

    companion object {
        fun fromKey(key: String?): AirIndexType? = entries.firstOrNull { it.key == key }
    }
}
