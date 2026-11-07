package com.kfpun.twaqi.ui.main

import androidx.window.core.layout.WindowSizeClass

/**
 * Where a foldable's inner display folds, so the wide layout can put its divider on it (iOS
 * `FoldLine`). A pane that straddles the fold is bent in half whenever the phone isn't opened
 * flat, so map | station splits there instead of at its usual width.
 */
object FoldLine {
    /** Narrowest a pane may be for the split to follow the fold, in dp. */
    const val MINIMUM_PANE_WIDTH = 320f

    /**
     * Width of a leading pane that ends on the fold, for a container that starts at
     * [containerLeft] and is [containerWidth] wide (all in dp, window coordinates). Null when there
     * is no fold, or when it falls too close to either edge of the container.
     */
    fun leadingWidth(foldX: Float?, containerLeft: Float, containerWidth: Float): Float? {
        if (foldX == null) return null
        val width = foldX - containerLeft
        if (width < MINIMUM_PANE_WIDTH || containerWidth - width < MINIMUM_PANE_WIDTH) return null
        return width
    }
}

/**
 * The wide layout (iOS `horizontalSizeClass == .regular`, FOX-119): the station page in a panel
 * beside the map, and Search, Favourites and Help as a list with the chosen page beside it.
 */
object WideLayout {
    /** Narrowest window, in dp, that is wide (a tablet, an unfolded foldable): window size class medium. */
    const val MIN_WIDTH = WindowSizeClass.WIDTH_DP_MEDIUM_LOWER_BOUND.toFloat()

    /** A landscape phone is wide but too short to share: its height class is compact. */
    const val MIN_HEIGHT = WindowSizeClass.HEIGHT_DP_MEDIUM_LOWER_BOUND.toFloat()

    fun isWide(widthDp: Float, heightDp: Float): Boolean = widthDp >= MIN_WIDTH && heightDp >= MIN_HEIGHT

    /**
     * Medium or expanded width and at least medium height. Phones in either orientation and a flip
     * phone's cover screen are compact and keep the phone layout.
     */
    fun isWide(sizeClass: WindowSizeClass): Boolean =
        sizeClass.isWidthAtLeastBreakpoint(WindowSizeClass.WIDTH_DP_MEDIUM_LOWER_BOUND) &&
            sizeClass.isHeightAtLeastBreakpoint(WindowSizeClass.HEIGHT_DP_MEDIUM_LOWER_BOUND)

    /**
     * Width of the station panel at the trailing edge: on an unfolded foldable it starts on the fold,
     * so the map and the station each get a half; otherwise about two fifths of the window, so the
     * map stays the larger part (iOS `MainView.panelWidth`).
     */
    fun panelWidth(containerWidth: Float, containerLeft: Float = 0f, foldX: Float? = null): Float =
        FoldLine.leadingWidth(foldX, containerLeft, containerWidth)?.let { containerWidth - it }
            ?: (containerWidth * 0.4f).coerceIn(320f, 440f)
}
