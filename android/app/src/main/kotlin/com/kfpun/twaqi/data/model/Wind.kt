package com.kfpun.twaqi.data.model

import androidx.annotation.StringRes
import com.kfpun.twaqi.R
import kotlin.math.roundToInt

/**
 * Wind helpers shared by the map markers and the station page (iOS `Wind`, `WindExtensions.swift`).
 *
 * [direction] is meteorological: the direction the wind blows *from*, in degrees clockwise from
 * north. [speed] is in m/s.
 */
data class Wind(val direction: Double, val speed: Double) {
    /**
     * The API reports `0 / 0` both for genuinely calm air and for stations with no anemometer.
     * Either way there is no direction worth drawing.
     */
    val isCalm: Boolean get() = speed <= 0

    /** 16-point compass abbreviation, e.g. `297°` → `WNW`; "—" when calm. */
    val compassPoint: String
        get() {
            if (isCalm) return "—"
            val normalised = direction % 360
            val positive = if (normalised < 0) normalised + 360 else normalised
            // Swift's `.rounded()` rounds half away from zero; for positives that is half up.
            val index = Math.floor(positive / 22.5 + 0.5).toInt() % 16
            return COMPASS_POINTS[index]
        }

    /** Beaufort-flavoured descriptor for the speed alone; each band is half-open. */
    @get:StringRes
    val descriptor: Int
        get() = when {
            speed < 0.3 -> R.string.wind_calm
            speed < 1.6 -> R.string.wind_light_air
            speed < 3.4 -> R.string.wind_light_breeze
            speed < 5.5 -> R.string.wind_gentle_breeze
            speed < STRONG_BREEZE_THRESHOLD -> R.string.wind_moderate_breeze
            else -> R.string.wind_strong_breeze
        }

    /**
     * Rotation in degrees for an arrow drawn pointing south: rotated by where the wind comes *from*,
     * it points the way the wind is *going*.
     */
    val arrowRotation: Double get() = direction

    /**
     * Where this speed sits in the range the app names, 0 at calm through 1 at strong breeze and
     * above. Drives how long an arrow is drawn, so a glance reads strength without the number.
     * Clamped at the top: past a strong breeze the arrow would outgrow its marker.
     */
    val strengthFraction: Double
        get() = if (speed <= 0) 0.0 else minOf(speed / STRONG_BREEZE_THRESHOLD, 1.0)

    /**
     * [strengthFraction] snapped to one of [STRENGTH_STEPS] + 1 levels, so the map draws at most
     * that many arrow lengths per colour and every bitmap is reused (FOX-91). One step is 0.4 m/s
     * at the top of the range: finer than the eye reads off an arrow's length.
     */
    val strengthLevel: Int get() = (strengthFraction * STRENGTH_STEPS).roundToInt()

    companion object {
        /** Bottom of the strong-breeze band: the top of the named range. */
        const val STRONG_BREEZE_THRESHOLD = 8.0

        const val STRENGTH_STEPS = 20

        private val COMPASS_POINTS = listOf(
            "N", "NNE", "NE", "ENE",
            "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW",
            "W", "WNW", "NW", "NNW"
        )
    }
}

val Pollutant.wind: Wind get() = Wind(windDirection, windSpeed)

val HistoricalPollutant.wind: Wind get() = Wind(windDirection, windSpeed)
