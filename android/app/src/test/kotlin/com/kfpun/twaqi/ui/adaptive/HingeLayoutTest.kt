package com.kfpun.twaqi.ui.adaptive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** FOX-119: nothing a finger has to hit sits across a half-open foldable's hinge. */
class HingeLayoutTest {
    /** An unfolded book-style foldable, 840 x 700 dp, folded down the middle. */
    private fun book(separating: Boolean = true) = WindowHinge(420f, 0f, 420f, 700f, vertical = true, separating)

    /** The same foldable turned so the fold runs across: the tabletop posture. */
    private val tabletop = WindowHinge(0f, 350f, 840f, 350f, vertical = false, separating = true)

    @Test
    fun noHingeOrAFlatFoldChangesNothing() {
        assertEquals(HingeInsets.NONE, HingeLayout.insets(null, 0f, 0f, 840f, 700f))
        assertEquals(HingeInsets.NONE, HingeLayout.insets(book(separating = false), 0f, 0f, 840f, 700f))
        assertEquals(HingeInsets.NONE, HingeLayout.insets(tabletop.copy(separating = false), 0f, 0f, 840f, 700f, true))
    }

    @Test
    fun bookPostureKeepsControlsOnTheLargerSide() {
        // Hinge in the middle: the leading side.
        assertEquals(HingeInsets(end = 420f), HingeLayout.insets(book(), 0f, 0f, 840f, 700f))
        // A box starting at 100 dp: 320 dp before the hinge, 420 after it.
        assertEquals(HingeInsets(start = 320f), HingeLayout.insets(book(), 100f, 0f, 740f, 700f))
        // A box that ends on the hinge (the map beside the station panel) is already clear of it.
        assertEquals(HingeInsets.NONE, HingeLayout.insets(book(), 0f, 0f, 420f, 700f))
    }

    @Test
    fun tabletopPutsTheMapAboveAndTheControlsBelow() {
        // The tab content starts under a 24 dp status bar and is 600 dp tall.
        assertEquals(
            HingeInsets(mapHeight = 326f, controlsTop = 326f),
            HingeLayout.insets(tabletop, 0f, 24f, 840f, 600f, splitTabletop = true)
        )
        // Only the map splits; elsewhere a horizontal hinge changes nothing.
        assertEquals(HingeInsets.NONE, HingeLayout.insets(tabletop, 0f, 24f, 840f, 600f))
        // A hinge below the box misses it.
        assertEquals(HingeInsets.NONE, HingeLayout.insets(tabletop, 0f, 0f, 840f, 300f, splitTabletop = true))
    }

    @Test
    fun windowContentKeepsOffTheHingeInBothPostures() {
        // No hinge, or a flat fold: nothing.
        assertEquals(HingePadding.NONE, HingeLayout.windowPadding(null, 840f, 700f))
        assertEquals(HingePadding.NONE, HingeLayout.windowPadding(book(separating = false), 840f, 700f))
        // Book: the larger side, here the leading half.
        assertEquals(HingePadding(end = 420f), HingeLayout.windowPadding(book(), 840f, 700f))
        // Tabletop: above the hinge, so a scrolling station page never stops a switch on the fold.
        assertEquals(HingePadding(bottom = 350f), HingeLayout.windowPadding(tabletop, 840f, 700f))
        // A layout that splits on a book hinge itself (list-detail) asks only for the tabletop.
        assertEquals(HingePadding.NONE, HingeLayout.windowPadding(book(), 840f, 700f, book = false))
        assertEquals(HingePadding(bottom = 350f), HingeLayout.windowPadding(tabletop, 840f, 700f, book = false))
        // The ad banner under the tabs asks only for the book posture.
        assertEquals(HingePadding.NONE, HingeLayout.windowPadding(tabletop, 840f, 700f, tabletop = false))
    }

    @Test
    fun tabBarSplitsAtTheHinge() {
        assertNull(HingeLayout.tabsBeforeHinge(5, 840f, null))
        assertNull(HingeLayout.tabsBeforeHinge(5, 840f, book(separating = false)))
        assertNull(HingeLayout.tabsBeforeHinge(5, 840f, tabletop))
        // Five tabs, hinge in the middle: three before it, two after.
        assertEquals(3, HingeLayout.tabsBeforeHinge(5, 840f, book()))
        // A hinge near an edge still leaves a tab on each side.
        assertEquals(1, HingeLayout.tabsBeforeHinge(5, 840f, WindowHinge(40f, 0f, 40f, 700f, true, true)))
        assertEquals(4, HingeLayout.tabsBeforeHinge(5, 840f, WindowHinge(800f, 0f, 800f, 700f, true, true)))
    }
}
