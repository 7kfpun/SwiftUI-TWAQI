package com.kfpun.twaqi.ui

import com.kfpun.twaqi.ui.favourites.FavouriteDragOrder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** FOX-121: the order on screen while a favourite is dragged, and the one move saved on drop. */
class FavouriteDragOrderTest {
    @Test
    fun aRowDraggedOverAnotherTakesItsPlace() {
        assertEquals(listOf(2, 1, 3), FavouriteDragOrder.moveOnto(listOf(1, 2, 3), id = 1, target = 2))
        assertEquals(listOf(3, 1, 2), FavouriteDragOrder.moveOnto(listOf(1, 2, 3), id = 3, target = 1))
    }

    @Test
    fun unknownIdsLeaveTheOrderAlone() {
        val order = listOf(1, 2, 3)
        assertEquals(order, FavouriteDragOrder.moveOnto(order, id = 9, target = 2))
        assertEquals(order, FavouriteDragOrder.moveOnto(order, id = 1, target = 9))
        assertEquals(order, FavouriteDragOrder.moveOnto(order, id = 1, target = 1))
    }

    @Test
    fun dragOverSeveralRowsIsOneMoveOnDrop() {
        val before = listOf(1, 2, 3, 4)
        var order = before
        // Held at the top, dragged past each row in turn.
        for (target in listOf(2, 3, 4)) order = FavouriteDragOrder.moveOnto(order, id = 1, target = target)
        assertEquals(listOf(2, 3, 4, 1), order)
        assertEquals(0 to 3, FavouriteDragOrder.drop(before, order, id = 1))
    }

    @Test
    fun droppedBackInPlaceIsNoMove() {
        val before = listOf(1, 2, 3)
        val there = FavouriteDragOrder.moveOnto(before, id = 1, target = 3)
        assertEquals(listOf(2, 3, 1), there)
        // And back up past 3, then 2.
        val back = FavouriteDragOrder.moveOnto(
            FavouriteDragOrder.moveOnto(there, id = 1, target = 3),
            id = 1,
            target = 2
        )
        assertEquals(before, back)
        assertNull(FavouriteDragOrder.drop(before, back, id = 1))
    }
}
