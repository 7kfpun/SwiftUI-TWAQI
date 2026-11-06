package com.kfpun.twaqi.data.weather

import androidx.annotation.StringRes
import com.kfpun.twaqi.R

/**
 * CWA's forecast weather codes (預報產品天氣描述代碼表): 1–42, no 40 (iOS `WeatherCode`). Many
 * descriptions share a code, so each code's string is a summary of its group; in Chinese the card
 * shows CWA's own text when the file has it.
 */
object WeatherCode {
    val all: List<Int> = (1..39).toList() + listOf(41, 42)

    /** `weather_wx_<code>` (iOS `Weather.wx.<code>`), or null for a code this build doesn't know. */
    @StringRes
    fun stringRes(code: Int?): Int? = when (code) {
        1 -> R.string.weather_wx_1
        2 -> R.string.weather_wx_2
        3 -> R.string.weather_wx_3
        4 -> R.string.weather_wx_4
        5 -> R.string.weather_wx_5
        6 -> R.string.weather_wx_6
        7 -> R.string.weather_wx_7
        8 -> R.string.weather_wx_8
        9 -> R.string.weather_wx_9
        10 -> R.string.weather_wx_10
        11 -> R.string.weather_wx_11
        12 -> R.string.weather_wx_12
        13 -> R.string.weather_wx_13
        14 -> R.string.weather_wx_14
        15 -> R.string.weather_wx_15
        16 -> R.string.weather_wx_16
        17 -> R.string.weather_wx_17
        18 -> R.string.weather_wx_18
        19 -> R.string.weather_wx_19
        20 -> R.string.weather_wx_20
        21 -> R.string.weather_wx_21
        22 -> R.string.weather_wx_22
        23 -> R.string.weather_wx_23
        24 -> R.string.weather_wx_24
        25 -> R.string.weather_wx_25
        26 -> R.string.weather_wx_26
        27 -> R.string.weather_wx_27
        28 -> R.string.weather_wx_28
        29 -> R.string.weather_wx_29
        30 -> R.string.weather_wx_30
        31 -> R.string.weather_wx_31
        32 -> R.string.weather_wx_32
        33 -> R.string.weather_wx_33
        34 -> R.string.weather_wx_34
        35 -> R.string.weather_wx_35
        36 -> R.string.weather_wx_36
        37 -> R.string.weather_wx_37
        38 -> R.string.weather_wx_38
        39 -> R.string.weather_wx_39
        41 -> R.string.weather_wx_41
        42 -> R.string.weather_wx_42
        else -> null
    }

    /**
     * The line under a period's icon. Chinese: CWA's own text, else the code's. English: the
     * code's, or null for a code this build doesn't know — free Chinese text is never shown in
     * English. [getString] is the app-language `Context.getString`.
     */
    fun text(code: Int?, cwaText: String?, chinese: Boolean, getString: (Int) -> String): String? {
        if (chinese && !cwaText.isNullOrEmpty()) return cwaText
        return stringRes(code)?.let(getString)?.takeIf { it.isNotEmpty() }
    }

    /**
     * The icon for a code, named after the iOS SF Symbol it stands in for. Clear and partly cloudy
     * codes get a moon at night; an unknown code gets a plain cloud.
     */
    fun icon(code: Int?, night: Boolean): WeatherIcon = when (code) {
        1 -> if (night) WeatherIcon.MOON_STARS else WeatherIcon.SUN_MAX
        2, 3, 4 -> if (night) WeatherIcon.CLOUD_MOON else WeatherIcon.CLOUD_SUN
        5, 6, 7 -> WeatherIcon.CLOUD
        8, 9, 10, 11, 30, 31, 32, 38 -> WeatherIcon.CLOUD_DRIZZLE
        12, 13, 14, 39 -> WeatherIcon.CLOUD_RAIN
        15, 16, 17, 18, 34, 35, 36, 41 -> WeatherIcon.CLOUD_BOLT_RAIN
        19, 20, 29 -> if (night) WeatherIcon.CLOUD_MOON_RAIN else WeatherIcon.CLOUD_SUN_RAIN
        21, 22, 33 -> if (night) WeatherIcon.CLOUD_MOON_BOLT else WeatherIcon.CLOUD_SUN_BOLT
        23, 37 -> WeatherIcon.CLOUD_SLEET
        24, 25 -> if (night) WeatherIcon.CLOUD_FOG else WeatherIcon.SUN_HAZE
        26, 27, 28 -> WeatherIcon.CLOUD_FOG
        42 -> WeatherIcon.SNOWFLAKE
        else -> WeatherIcon.CLOUD
    }
}

/** The forecast icons, one per SF Symbol iOS uses (`moon.stars.fill` → [MOON_STARS]). */
enum class WeatherIcon {
    SUN_MAX,
    MOON_STARS,
    CLOUD_SUN,
    CLOUD_MOON,
    CLOUD,
    CLOUD_DRIZZLE,
    CLOUD_RAIN,
    CLOUD_BOLT_RAIN,
    CLOUD_SUN_RAIN,
    CLOUD_MOON_RAIN,
    CLOUD_SUN_BOLT,
    CLOUD_MOON_BOLT,
    CLOUD_SLEET,
    SUN_HAZE,
    CLOUD_FOG,
    SNOWFLAKE
}
