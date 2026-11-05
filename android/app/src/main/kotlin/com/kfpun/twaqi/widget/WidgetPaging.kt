package com.kfpun.twaqi.widget

import com.kfpun.twaqi.data.model.AirIndexType
import java.time.Duration
import java.time.Instant

/**
 * What a home screen widget's buttons changed (iOS `WidgetPageState`, FOX-76): the station a medium
 * or large widget pages to with ‹ ›, and the index its label was tapped to. Kept per widget id in
 * the widget's Glance state ([WidgetStateKeys]).
 *
 * @property stationId the station paged to; null is the default page, the widget's own station.
 * @property index [AirIndexType.key] the label was cycled to; null is the configured index.
 * @property tappedAt the last tap on a button, for the 30-minute reset.
 * @property refreshedAt the last refresh that fetched readings.
 */
data class WidgetPageState(
    val stationId: Int? = null,
    val index: String? = null,
    val tappedAt: Instant? = null,
    val refreshedAt: Instant? = null
)

/**
 * Paging through favourites and cycling the index on a home screen widget (iOS `WidgetPaging`).
 * Pure, so the rules are unit tested; the widget's action callbacks and refresh worker apply them.
 */
object WidgetPaging {
    /** A paged widget goes back to its own station after this long without a tap. */
    val resetInterval: Duration = Duration.ofMinutes(30)

    /** The order the index label steps through, as the configuration lists them. */
    val indexCycle: List<AirIndexType> = listOf(
        AirIndexType.AQI,
        AirIndexType.PM25,
        AirIndexType.PM10,
        AirIndexType.O3,
        AirIndexType.CO,
        AirIndexType.SO2,
        AirIndexType.NO2
    )

    /**
     * The stations to page through: the widget's own station first, then the favourites in the
     * reader's order, each once. [favouriteIds] should hold only favourites with a saved reading,
     * since a tap never fetches.
     */
    fun pageIds(defaultId: Int?, favouriteIds: List<Int>): List<Int> =
        (listOfNotNull(defaultId) + favouriteIds).distinct()

    /** The ‹ › buttons need at least two saved favourites and two stations to show. */
    fun showsPager(favouriteCount: Int, pageCount: Int): Boolean = favouriteCount >= 2 && pageCount >= 2

    /**
     * The page shown: the stored station's place in [pageIds], or 0 (the default page) when nothing
     * is stored, the last tap is [resetInterval] old, or the station is no longer there.
     */
    fun currentPage(state: WidgetPageState, pageIds: List<Int>, now: Instant): Int {
        val stationId = state.stationId ?: return 0
        val tappedAt = state.tappedAt ?: return 0
        if (Duration.between(tappedAt, now) >= resetInterval) return 0
        return pageIds.indexOf(stationId).takeIf { it >= 0 } ?: 0
    }

    /** The page [step] away from [page], wrapping at both ends. */
    fun page(from: Int, step: Int, count: Int): Int {
        if (count <= 0) return 0
        return ((from + step) % count + count) % count
    }

    /** What a button stores to show [page]: null for the default page. */
    fun target(page: Int, pageIds: List<Int>): Int? = if (page > 0 && page in pageIds.indices) pageIds[page] else null

    /** When a paged widget goes back to its default page, or null when it is on the default page. */
    fun resetAt(state: WidgetPageState, pageIds: List<Int>, now: Instant): Instant? {
        if (currentPage(state, pageIds, now) <= 0) return null
        return state.tappedAt?.plus(resetInterval)
    }

    /** The index after [index] in [indexCycle], wrapping. */
    fun nextIndex(index: AirIndexType): AirIndexType {
        val position = indexCycle.indexOf(index)
        if (position < 0) return indexCycle.first()
        return indexCycle[(position + 1) % indexCycle.size]
    }

    /** The index to draw: the cycled one, or [configured] from the widget's settings. */
    fun index(state: WidgetPageState, configured: AirIndexType): AirIndexType =
        AirIndexType.fromKey(state.index) ?: configured

    /** After a ‹ › tap: show [stationId] (null for the default page). */
    fun paged(state: WidgetPageState, stationId: Int?, now: Instant): WidgetPageState =
        state.copy(stationId = stationId, tappedAt = now)

    /** True when the page stored in [state] is [resetInterval] past its last tap. */
    fun isExpired(state: WidgetPageState, now: Instant): Boolean {
        val tappedAt = state.tappedAt ?: return true
        return Duration.between(tappedAt, now) >= resetInterval
    }

    /** After a tap on the index label: show [index]. A page that already went back stays there. */
    fun cycled(state: WidgetPageState, index: AirIndexType, now: Instant): WidgetPageState = state.copy(
        stationId = if (isExpired(state, now)) null else state.stationId,
        index = index.key,
        tappedAt = now
    )

    /**
     * After a scheduled refresh: with new readings ([hasNewData]), back to the default page.
     * Offline, or when the request failed, the page stays and only the 30-minute rule sends it
     * back; an expired page is cleared. The cycled index stays.
     */
    fun refreshed(state: WidgetPageState, hasNewData: Boolean, now: Instant): WidgetPageState = state.copy(
        stationId = if (hasNewData || isExpired(state, now)) null else state.stationId,
        refreshedAt = now
    )

    /**
     * What a refresh saves after its fetch. [current] is the state read again after the fetch,
     * [readBefore] the one read before it. A tap in between (a different `tappedAt`) is newer than
     * the readings, so its page and index stay; otherwise [refreshed].
     */
    fun afterFetch(
        current: WidgetPageState,
        readBefore: WidgetPageState,
        hasNewData: Boolean,
        now: Instant
    ): WidgetPageState {
        if (current.tappedAt != readBefore.tappedAt) return current.copy(refreshedAt = now)
        return refreshed(current, hasNewData, now)
    }
}
