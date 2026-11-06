package com.kfpun.twaqi.data.model

import kotlin.math.abs
import kotlin.math.roundToInt

enum class AqiTrendDirection { IMPROVING, WORSENING, STEADY }

/**
 * Which way air quality is heading over the recent past (iOS `AqiTrend`).
 *
 * @property magnitude absolute change between the two comparison windows, in the values' unit.
 * @property current mean of the most recent window: what the reader is experiencing now.
 */
data class AqiTrend(val direction: AqiTrendDirection, val magnitude: Double, val current: Double) {
    /** [magnitude] rounded to whole AQI points. Pollutants in ppm round to zero; read [magnitude] for those. */
    val change: Int get() = magnitude.roundToInt()

    companion object {
        /** Movement smaller than this is noise, not a trend. Sized for AQI points. */
        const val STEADY_THRESHOLD = 5.0

        private const val WINDOW_SIZE = 3
        private const val LOOK_BACK = 6

        /**
         * A tenth of the average reading: CO moves in hundredths of a ppm and PM10 in tens of µg/m³,
         * so one absolute cut-off can't fit both. Unreachable when the average isn't positive.
         */
        fun relativeThreshold(values: List<Double>): Double {
            val average = mean(values)
            return if (average > 0) average * 0.10 else Double.MAX_VALUE
        }

        /**
         * Compares the mean of the three most recent readings with the mean of the three from
         * about six hours earlier (or the oldest three with less history). Null with fewer than
         * two readings.
         *
         * @param values readings, oldest first.
         */
        fun from(values: List<Double>, steadyThreshold: Double = STEADY_THRESHOLD): AqiTrend? {
            if (values.size < 2) return null
            val recent = mean(values.takeLast(WINDOW_SIZE))
            val earlier = mean(earlierWindow(values))
            val delta = recent - earlier
            val direction = when {
                abs(delta) < steadyThreshold -> AqiTrendDirection.STEADY
                delta < 0 -> AqiTrendDirection.IMPROVING
                else -> AqiTrendDirection.WORSENING
            }
            return AqiTrend(direction, abs(delta), recent)
        }

        /** [from] with the threshold for [type]: the absolute one for AQI, a relative one otherwise. */
        fun from(values: List<Double>, type: AirIndexType): AqiTrend? =
            from(values, if (type == AirIndexType.AQI) STEADY_THRESHOLD else relativeThreshold(values))

        private fun earlierWindow(values: List<Double>): List<Double> {
            if (values.size < WINDOW_SIZE + LOOK_BACK) return values.take(WINDOW_SIZE)
            val upper = values.size - LOOK_BACK
            return values.subList(upper - WINDOW_SIZE, upper)
        }

        private fun mean(values: List<Double>): Double = if (values.isEmpty()) 0.0 else values.sum() / values.size
    }
}
