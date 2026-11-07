package com.kfpun.twaqi.widget

import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.Pollutant
import java.time.Instant

/**
 * What one widget draws (iOS `ReadingEntry`): the station shown, the favourites under it, the
 * index, and whether it is locked or paged.
 *
 * @property reading the station shown: the widget's own, or the favourite paged to.
 * @property favourites saved favourites other than [reading], in the reader's order.
 * @property isLocked a Pro family placed without Pro (FOX-58): a placeholder that opens the Pro screen.
 * @property pageIds the stations ‹ › page through, the widget's own first, and [page] the one shown.
 */
data class WidgetEntry(
    val family: WidgetFamily,
    val reading: Pollutant?,
    val type: AirIndexType,
    val favourites: List<Pollutant> = emptyList(),
    val isLocked: Boolean = false,
    val pageIds: List<Int> = emptyList(),
    val page: Int = 0,
    val showsPager: Boolean = false
) {
    /** The index label cycles on tap, except on a locked widget and on station detail (iOS: not interactive). */
    val cyclesIndex: Boolean get() = !isLocked && family != WidgetFamily.STATION_DETAIL

    /** The favourites listed under the station, as many as the family has room for. */
    val listedFavourites: List<Pollutant>
        get() = favourites.take(WidgetFamilyRules.favouriteLimit(family, showsPager))

    companion object {
        /**
         * The entry for [family] from saved readings (iOS `ReadingProvider.makeEntry`): the page
         * [state] points at ([leading], the widget's own station, by default), the other favourites
         * under it, and the index the label was cycled to. A favourite with no saved reading is left
         * out rather than shown blank.
         *
         * @param readings saved readings by station id; [leading] wins over its own entry.
         */
        fun make(
            family: WidgetFamily,
            leading: Pollutant?,
            config: WidgetConfig,
            favouriteIds: List<Int>,
            readings: Map<Int, Pollutant>,
            isPro: Boolean,
            state: WidgetPageState,
            now: Instant,
            isPreview: Boolean = false
        ): WidgetEntry {
            val isLocked = WidgetFamilyRules.isLocked(family, isPro, isPreview)
            val base = WidgetEntry(family = family, reading = leading, type = config.index, isLocked = isLocked)
            if (!WidgetFamilyRules.listsFavourites(family)) return base

            val type = if (base.cyclesIndex) WidgetPaging.index(state, config.index) else config.index
            val all = readings.toMutableMap()
            val saved = favouriteIds.filter { it in all }
            leading?.let { all[it.stationId] = it }
            val pageIds = WidgetPaging.pageIds(leading?.stationId, saved)
            val showsPager = WidgetFamilyRules.pagesFavourites(family) && base.cyclesIndex && leading != null &&
                WidgetPaging.showsPager(favouriteIds.size, pageIds.size)
            val page = if (showsPager) WidgetPaging.currentPage(state, pageIds, now) else 0
            val shown = if (showsPager) all[pageIds[page]] ?: leading else leading

            // The station shown is never listed again under itself.
            val favourites = saved.distinct().filter { it != shown?.stationId }.mapNotNull { all[it] }
            return base.copy(
                reading = shown,
                type = type,
                favourites = favourites,
                pageIds = pageIds,
                page = page,
                showsPager = showsPager
            )
        }
    }
}
