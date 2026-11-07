@file:OptIn(ExperimentalMaterial3AdaptiveApi::class)

package com.kfpun.twaqi.ui.adaptive

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.currentWindowDpSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

/**
 * A foldable's fold or hinge, in window dp (Jetpack WindowManager's `FoldingFeature`, through
 * material3-adaptive's `HingeInfo`). [separating]: the device is half open (tabletop or book) or has
 * two screens, so nothing a finger has to hit may sit across it. A flat fold is not separating.
 */
data class WindowHinge(
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
    val vertical: Boolean,
    val separating: Boolean
)

/**
 * Space to leave on each side of a layer of controls, in dp, so that none sits across a hinge
 * (FOX-119). [mapHeight] and [controlsTop] are for the tabletop posture: the map above the hinge,
 * its controls below.
 */
data class HingeInsets(
    val start: Float = 0f,
    val end: Float = 0f,
    val mapHeight: Float? = null,
    val controlsTop: Float? = null
) {
    val isTabletop: Boolean get() = mapHeight != null

    companion object {
        val NONE = HingeInsets()
    }
}

/** Padding, in dp, that keeps content as large as the window clear of a half-open hinge (FOX-119). */
data class HingePadding(val start: Float = 0f, val end: Float = 0f, val bottom: Float = 0f) {
    companion object {
        val NONE = HingePadding()
    }
}

object HingeLayout {
    /**
     * For a box at [left], [top] ([width] x [height], window dp): keep its controls on the larger
     * side of a separating vertical hinge (book posture). A horizontal one (tabletop) gives the map
     * the part above the hinge and the controls the part below when [splitTabletop]; otherwise it
     * changes nothing. A hinge that misses the box, or a flat fold, changes nothing either.
     */
    fun insets(
        hinge: WindowHinge?,
        left: Float,
        top: Float,
        width: Float,
        height: Float,
        splitTabletop: Boolean = false
    ): HingeInsets {
        if (hinge == null || !hinge.separating) return HingeInsets.NONE
        return if (hinge.vertical) {
            val leading = hinge.left - left
            val trailing = left + width - hinge.right
            when {
                leading <= 0f || trailing <= 0f -> HingeInsets.NONE
                leading >= trailing -> HingeInsets(end = width - leading)
                else -> HingeInsets(start = width - trailing)
            }
        } else {
            val above = hinge.top - top
            val below = top + height - hinge.bottom
            if (!splitTabletop || above <= 0f || below <= 0f) {
                HingeInsets.NONE
            } else {
                HingeInsets(mapHeight = above, controlsTop = hinge.bottom - top)
            }
        }
    }

    /**
     * For content as large as the window ([width] x [height] dp): in the book posture, the larger
     * side of the hinge ([book]); in the tabletop posture, the part above the hinge ([tabletop]), so
     * that no row, switch or scrubber of a scrolling page stops on the fold. A flat fold, or no
     * hinge, changes nothing.
     */
    fun windowPadding(
        hinge: WindowHinge?,
        width: Float,
        height: Float,
        book: Boolean = true,
        tabletop: Boolean = true
    ): HingePadding {
        if (hinge == null || !hinge.separating) return HingePadding.NONE
        if (hinge.vertical && !book) return HingePadding.NONE
        if (!hinge.vertical && !tabletop) return HingePadding.NONE
        val insets = insets(hinge, 0f, 0f, width, height, splitTabletop = true)
        val mapHeight = insets.mapHeight
        return if (mapHeight != null) {
            HingePadding(bottom = height - mapHeight)
        } else {
            HingePadding(start = insets.start, end = insets.end)
        }
    }

    /**
     * How many of [count] tab bar items go before a separating vertical hinge in a bar [width] wide
     * that starts at the window's left edge, so that no item straddles it; null when the bar needs
     * no split. Each side gets at least one.
     */
    fun tabsBeforeHinge(count: Int, width: Float, hinge: WindowHinge?): Int? {
        if (hinge == null || !hinge.separating || !hinge.vertical || count < 2) return null
        val leading = hinge.left
        val trailing = width - hinge.right
        if (leading <= 0f || trailing <= 0f) return null
        return (count * leading / (leading + trailing)).roundToInt().coerceIn(1, count - 1)
    }
}

/** The window's first fold or hinge, in window dp, or null on a device without one. */
@Composable
fun rememberWindowHinge(): WindowHinge? {
    // The same calls on every frame, with a hinge or without: material3-adaptive reports none at
    // first and the hinge a frame later.
    val hinge = currentWindowAdaptiveInfo().windowPosture.hingeList.firstOrNull()
    val density = LocalDensity.current
    return remember(hinge, density) {
        if (hinge == null) return@remember null
        with(density) {
            WindowHinge(
                left = hinge.bounds.left.toDp().value,
                top = hinge.bounds.top.toDp().value,
                right = hinge.bounds.right.toDp().value,
                bottom = hinge.bounds.bottom.toDp().value,
                vertical = hinge.isVertical,
                separating = hinge.isSeparating
            )
        }
    }
}

/**
 * For content as large as the window (FOX-119): in the book posture keeps it on the larger side of
 * the hinge ([book]), in the tabletop posture above it ([tabletop]). Changes nothing on other
 * devices and postures. See [HingeLayout.windowPadding].
 */
@Composable
fun Modifier.offHinge(book: Boolean = true, tabletop: Boolean = true): Modifier {
    val hinge = rememberWindowHinge()
    val size = currentWindowDpSize()
    val padding = HingeLayout.windowPadding(hinge, size.width.value, size.height.value, book, tabletop)
    if (padding == HingePadding.NONE) return this
    return padding(start = padding.start.dp, end = padding.end.dp, bottom = padding.bottom.dp)
}
