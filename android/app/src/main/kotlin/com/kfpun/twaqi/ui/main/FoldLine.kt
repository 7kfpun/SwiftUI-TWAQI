package com.kfpun.twaqi.ui.main

/**
 * Where a foldable's inner display folds, so the wide layout can put its divider on it (iOS
 * `FoldLine`). A pane that straddles the fold is bent in half whenever the phone isn't opened
 * flat, so list | map splits there instead of at its usual width.
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

/** The map tab's wide layout: the station list beside the map. */
object WideLayout {
    /** Narrowest window, in dp, that shows the list beside the map (a tablet, an unfolded foldable). */
    const val MIN_WIDTH = 600f

    /** A landscape phone is wide but too short to share. */
    const val MIN_HEIGHT = 480f

    fun isWide(widthDp: Float, heightDp: Float): Boolean = widthDp >= MIN_WIDTH && heightDp >= MIN_HEIGHT

    /**
     * Width of the list pane: on an unfolded foldable it ends on the fold, so the list and the map
     * each get a half; otherwise about two fifths of the window, so the map stays the larger part
     * (iOS `MainView.panelWidth`).
     */
    fun listWidth(containerWidth: Float, containerLeft: Float = 0f, foldX: Float? = null): Float =
        FoldLine.leadingWidth(foldX, containerLeft, containerWidth)
            ?: (containerWidth * 0.4f).coerceIn(320f, 440f)
}
