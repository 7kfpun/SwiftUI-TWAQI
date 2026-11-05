package com.kfpun.twaqi.ui.station

import androidx.annotation.StringRes
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.AqiTrend
import com.kfpun.twaqi.data.model.AqiTrendDirection
import com.kfpun.twaqi.data.model.HistoricalPollutant
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * How the 24-hour chart states the trend: getting better, worse or steady (iOS `TrendVerdict`).
 * The judgement itself is [AqiTrend].
 *
 * The icons carry good-or-bad, not up-or-down: falling AQI is good news, so a down arrow beside
 * "Improving" made readers double-take.
 *
 * @property tint band colour (`0xRRGGBB`) for the icon and title; null for the secondary text colour.
 */
data class TrendDisplay(
    val direction: AqiTrendDirection,
    @param:StringRes val title: Int,
    val detail: Detail,
    val tint: Int?
) {
    /** The line under the title. */
    sealed interface Detail {
        data object None : Detail

        /** A localized sentence about whole AQI points: "AQI down %d over the last few hours". */
        data class Points(@param:StringRes val format: Int, val value: Int) : Detail

        /** A value in its own unit, or a share of the reading ("−12%"), the same in every language. */
        data class Text(val text: String) : Detail
    }

    companion object {
        /** [values] oldest first. */
        fun of(values: List<Double>, type: AirIndexType): TrendDisplay {
            val result = AqiTrend.from(values, type)
                ?: return TrendDisplay(AqiTrendDirection.STEADY, R.string.details_trend_steady, Detail.None, null)

            return when (result.direction) {
                AqiTrendDirection.STEADY -> TrendDisplay(
                    AqiTrendDirection.STEADY,
                    R.string.details_trend_steady,
                    steadyDetail(result, type),
                    null
                )

                AqiTrendDirection.IMPROVING -> TrendDisplay(
                    AqiTrendDirection.IMPROVING,
                    R.string.details_trend_improving,
                    changeDetail(R.string.details_trend_improving_detail, result, type),
                    AirStatus.GOOD.color
                )

                AqiTrendDirection.WORSENING -> TrendDisplay(
                    AqiTrendDirection.WORSENING,
                    R.string.details_trend_worsening,
                    changeDetail(R.string.details_trend_worsening_detail, result, type),
                    AirStatus.of(type, result.current).color
                )
            }
        }

        /**
         * The localized sentences are in whole AQI points, so they only fit AQI. A pollutant shows its
         * change as a share of the earlier reading, which needs no baseline to read.
         */
        private fun changeDetail(@StringRes format: Int, result: AqiTrend, type: AirIndexType): Detail {
            if (type == AirIndexType.AQI) return Detail.Points(format, result.change)
            val improving = result.direction == AqiTrendDirection.IMPROVING
            val baseline = if (improving) result.current + result.magnitude else result.current - result.magnitude
            if (baseline <= 0) return Detail.Text("${type.format(result.magnitude)} ${type.unit}")
            val percent = (result.magnitude / baseline * 100).roundToInt()
            return Detail.Text(if (improving) "−$percent%" else "+$percent%")
        }

        private fun steadyDetail(result: AqiTrend, type: AirIndexType): Detail {
            if (type != AirIndexType.AQI) return Detail.Text("${type.format(result.current)} ${type.unit}")
            return Detail.Points(R.string.details_trend_steady_detail, result.current.roundToInt())
        }
    }
}

/** The 24-hour bars (iOS `DetailsHistoryView`): the numbers, apart from drawing them. */
data class HistoryChart(val values: List<Double>, val times: List<String>) {
    val lowest: Double get() = values.minOrNull() ?: 0.0
    val highest: Double get() = values.maxOrNull() ?: 0.0
    val average: Double get() = if (values.isEmpty()) 0.0 else values.sum() / values.size

    /** Two readings at least, or there is no trend to draw. */
    val hasTrend: Boolean get() = values.size >= 2

    /**
     * A bar's height as a share of the tallest, from [MIN_BAR] to 1, scaled to the day's own range
     * and padded a little: a zero-baseline axis draws a 60–89 day as a flat wall of bars. The
     * padding is a share of the range, as CO moves in hundredths of a ppm.
     */
    fun barFraction(value: Double): Double {
        val range = highest - lowest
        val pad = if (range > 0) range * 0.15 else max(highest * 0.05, 0.001)
        val lower = max(0.0, lowest - pad)
        val upper = max(highest + pad, lower + 0.001)
        val fraction = (value - lower) / (upper - lower)
        return MIN_BAR + (1 - MIN_BAR) * min(1.0, max(0.0, fraction))
    }

    companion object {
        const val MAX_POINTS = 24

        /** 10 of iOS's 72 points: every bar stays visible. */
        const val MIN_BAR = 10.0 / 72.0

        /** Newest last, the last [MAX_POINTS] hours. */
        fun of(history: List<HistoricalPollutant>, type: AirIndexType): HistoryChart {
            val points = history.takeLast(MAX_POINTS)
            return HistoryChart(points.map { it.value(type) }, points.map { it.publishTime })
        }
    }
}
