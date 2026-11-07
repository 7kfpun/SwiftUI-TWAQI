package com.kfpun.twaqi.ui.main

import org.junit.Assert.assertEquals
import org.junit.Test

class TimelineLabelsTest {
    @Test
    fun `wide bar keeps every label`() {
        val kept = visibleLabelLefts(listOf(0f, 100f, 200f, 300f), listOf(40f, 40f, 40f, 40f), gap = 6f)
        assertEquals(setOf(0, 1, 2, 3), kept)
    }

    @Test
    fun `narrow bar drops the label that touches Now and keeps Now`() {
        // The label at 90 runs into Now (120), as beside the station panel; 60 clears it.
        val kept = visibleLabelLefts(listOf(0f, 60f, 90f, 120f), listOf(40f, 40f, 40f, 40f), gap = 6f)
        assertEquals(setOf(0, 1, 3), kept)
    }

    @Test
    fun `the last label always shows`() {
        assertEquals(setOf(0), visibleLabelLefts(listOf(0f), listOf(500f), gap = 6f))
    }
}
