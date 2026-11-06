package com.kfpun.twaqi.ui.favourites

import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.lazy.LazyListItemInfo
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** The list order while a row is dragged, kept apart from Compose so it can be tested. */
internal object FavouriteDragOrder {
    /** [order] with [id] moved into [target]'s place, as a row dragged over another takes its slot. */
    fun moveOnto(order: List<Int>, id: Int, target: Int): List<Int> {
        val from = order.indexOf(id)
        val to = order.indexOf(target)
        if (from < 0 || to < 0 || from == to) return order
        return order.toMutableList().apply { add(to, removeAt(from)) }
    }

    /**
     * The station ids to save on drop, [after]; null when [id] is back where it started. Ids, not
     * indices: a refresh that adds or drops a row while the finger is down can't move another station.
     */
    fun drop(before: List<Int>, after: List<Int>, id: Int): List<Int>? {
        val from = before.indexOf(id)
        val to = after.indexOf(id)
        return if (from < 0 || to < 0 || from == to) null else after
    }
}

/**
 * Long-press drag to reorder Favourites (iOS `List.onMove`). The rows on screen follow [order]
 * while a row is held; the new order is saved once, on drop, so it is one reorder (and one
 * `favourite_station_reordered`) however far the row travels. Alerts are never touched here.
 *
 * Rows are found by their LazyColumn key, the station id; other items (the offline notice) are
 * never a target.
 */
@Stable
internal class FavouriteDragState(private val listState: LazyListState, private val scope: CoroutineScope) {
    /** The station being dragged, or null. */
    var draggedId by mutableStateOf<Int?>(null)
        private set

    /** The order on screen while a row is held; null otherwise. */
    var order by mutableStateOf<List<Int>?>(null)
        private set

    private var startOrder: List<Int> = emptyList()
    private var dragged by mutableFloatStateOf(0f)
    private var startOffset by mutableIntStateOf(0)
    private var autoScroll: Job? = null

    private val draggedInfo: LazyListItemInfo?
        get() = listState.layoutInfo.visibleItemsInfo.firstOrNull { it.key == draggedId }

    /** How far the held row is drawn from its slot, so it stays under the finger. */
    val draggedOffset: Float
        get() = draggedInfo?.let { startOffset + dragged - it.offset } ?: 0f

    fun start(id: Int, ids: List<Int>) {
        val info = listState.layoutInfo.visibleItemsInfo.firstOrNull { it.key == id } ?: return
        draggedId = id
        startOrder = ids
        order = ids
        startOffset = info.offset
        dragged = 0f
    }

    fun drag(dy: Float) {
        if (draggedId == null) return
        dragged += dy
        swapIfOver()
        if (autoScroll?.isActive != true && overscroll() != 0f) {
            autoScroll = scope.launch {
                while (isActive && draggedId != null) {
                    val by = overscroll()
                    if (by == 0f) break
                    listState.scrollBy(by)
                    swapIfOver()
                    delay(AUTO_SCROLL_FRAME_MS)
                }
            }
        }
    }

    /** Ends the drag: the station ids in their new order, or null when the row is back where it started. */
    fun end(): List<Int>? {
        val id = draggedId
        val result = id?.let { FavouriteDragOrder.drop(startOrder, order.orEmpty(), it) }
        cancel()
        return result
    }

    /** Ends the drag without saving: the rows go back to the saved order. */
    fun cancel() {
        autoScroll?.cancel()
        autoScroll = null
        draggedId = null
        order = null
        dragged = 0f
    }

    /** Takes the slot of the row under the held row's middle. */
    private fun swapIfOver() {
        val id = draggedId ?: return
        val current = order ?: return
        val info = draggedInfo ?: return
        // Wait for the last swap to be laid out, or the stale layout would swap it straight back.
        val laidOut = listState.layoutInfo.visibleItemsInfo.filter { it.key is Int }.map { it.key as Int }
        if (laidOut != current.filter { it in laidOut }) return

        val middle = (info.offset + draggedOffset + info.size / 2f).toInt()
        val target = listState.layoutInfo.visibleItemsInfo.firstOrNull {
            it.key is Int && it.key != id && middle in it.offset until it.offset + it.size
        } ?: return
        // Keeps the list still when the first visible row moves; it would otherwise scroll with it.
        if (info.index == listState.firstVisibleItemIndex || target.index == listState.firstVisibleItemIndex) {
            listState.requestScrollToItem(listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset)
        }
        order = FavouriteDragOrder.moveOnto(current, id, target.key as Int)
    }

    /** How far to scroll when the held row is past the top or bottom edge; 0 inside. */
    private fun overscroll(): Float {
        val info = draggedInfo ?: return 0f
        val top = info.offset + draggedOffset
        val bottom = top + info.size
        val layout = listState.layoutInfo
        return when {
            top < layout.viewportStartOffset && listState.canScrollBackward ->
                (top - layout.viewportStartOffset).coerceAtLeast(-AUTO_SCROLL_STEP)

            bottom > layout.viewportEndOffset && listState.canScrollForward ->
                (bottom - layout.viewportEndOffset).coerceAtMost(AUTO_SCROLL_STEP)

            else -> 0f
        }
    }

    private companion object {
        const val AUTO_SCROLL_STEP = 24f
        const val AUTO_SCROLL_FRAME_MS = 16L
    }
}

@Composable
internal fun rememberFavouriteDragState(listState: LazyListState): FavouriteDragState {
    val scope = rememberCoroutineScope()
    return remember(listState) { FavouriteDragState(listState, scope) }
}
