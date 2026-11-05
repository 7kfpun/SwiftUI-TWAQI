package com.kfpun.twaqi.widget

/**
 * The widget sizes (iOS `WidgetFamily`). The air-quality widget is resizable and is drawn as
 * [SMALL], [MEDIUM] or [LARGE] by its size on the home screen; the station detail widget is
 * [STATION_DETAIL] at any size (iOS extra large, FOX-72).
 */
enum class WidgetFamily(val analyticsName: String) {
    SMALL("small"),
    MEDIUM("medium"),
    LARGE("large"),
    STATION_DETAIL("station_detail")
    ;

    companion object {
        /** Smallest size, in dp, at which the air-quality widget is drawn as medium / large. */
        const val MEDIUM_MIN_WIDTH_DP = 250
        const val LARGE_MIN_HEIGHT_DP = 250

        /** The family a resizable air-quality widget of this size draws as. */
        fun forSize(widthDp: Float, heightDp: Float): WidgetFamily = when {
            widthDp < MEDIUM_MIN_WIDTH_DP -> SMALL
            heightDp < LARGE_MIN_HEIGHT_DP -> MEDIUM
            else -> LARGE
        }
    }
}

/**
 * What each widget family does, as a function of the family and Pro alone, so it is tested
 * without a widget host (iOS `WidgetFamilyRules`).
 */
object WidgetFamilyRules {
    /** Small, medium and large list favourites under the leading station; station detail shows one station. */
    fun listsFavourites(family: WidgetFamily): Boolean = family != WidgetFamily.STATION_DETAIL

    /** Medium, large and station detail are Pro sizes; small is free. */
    fun isProFamily(family: WidgetFamily): Boolean = family != WidgetFamily.SMALL

    /**
     * A Pro size placed without Pro: a locked placeholder whose tap opens the Pro screen. The
     * widget picker's preview ([isPreview]) still shows it unlocked, so the reader sees what the
     * size does.
     */
    fun isLocked(family: WidgetFamily, isPro: Boolean, isPreview: Boolean = false): Boolean =
        isProFamily(family) && !isPro && !isPreview

    /** Medium and large page through favourites with ‹ › (FOX-76). */
    fun pagesFavourites(family: WidgetFamily): Boolean = family == WidgetFamily.MEDIUM || family == WidgetFamily.LARGE

    /** Large and station detail show the 空品區 forecast. */
    fun showsForecast(family: WidgetFamily): Boolean =
        family == WidgetFamily.LARGE || family == WidgetFamily.STATION_DETAIL

    /** Only station detail shows the 24-hour history, and only it fetches it. */
    fun showsStationDetail(family: WidgetFamily): Boolean = family == WidgetFamily.STATION_DETAIL

    /** How many favourites a family lists under the station shown. */
    fun favouriteLimit(family: WidgetFamily, showsPager: Boolean): Int = when (family) {
        WidgetFamily.SMALL -> 2
        WidgetFamily.MEDIUM -> if (showsPager) 2 else 3
        WidgetFamily.LARGE -> 4
        WidgetFamily.STATION_DETAIL -> 0
    }

    /**
     * What a large widget [heightDp] tall has room for under its header: the favourite rows, and
     * the row of other indices only when every listed favourite still fits beside it. The
     * forecast ([hasForecast]) always keeps its place, so it is never clipped off the bottom.
     */
    fun largeFit(heightDp: Float, hasForecast: Boolean, favourites: Int): LargeFit {
        val base = LargeFit.PADDING_DP + LargeFit.HEADER_DP + LargeFit.FAVOURITES_TITLE_DP +
            (if (hasForecast) LargeFit.FORECAST_DP else 0f)
        fun rows(space: Float) = (space / LargeFit.ROW_DP).toInt().coerceAtLeast(0)
        val rowsWithIndices = rows(heightDp - base - LargeFit.INDICES_DP)
        val showsIndices = rowsWithIndices >= favourites
        val rows = if (showsIndices) favourites else minOf(favourites, rows(heightDp - base))
        return LargeFit(showsOtherIndices = showsIndices, favouriteRows = rows.coerceAtLeast(minOf(favourites, 1)))
    }
}

/** [WidgetFamilyRules.largeFit]: the space each part of a large widget takes, in dp. */
data class LargeFit(val showsOtherIndices: Boolean, val favouriteRows: Int) {
    companion object {
        const val PADDING_DP = 24f
        const val HEADER_DP = 100f
        const val FAVOURITES_TITLE_DP = 32f
        const val FORECAST_DP = 68f
        const val INDICES_DP = 40f
        const val ROW_DP = 36f
    }
}
