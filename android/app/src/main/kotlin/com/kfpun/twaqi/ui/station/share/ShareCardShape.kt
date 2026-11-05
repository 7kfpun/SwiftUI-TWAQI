package com.kfpun.twaqi.ui.station.share

import androidx.annotation.StringRes
import com.kfpun.twaqi.R

/**
 * Where the card is going decides its shape (iOS `ShareCardShape`, FOX-73). Every shape is 360 dp
 * wide and rendered at [RENDER_SCALE] pixels per dp, so 1080 px wide, whatever the phone's density.
 *
 * @property raw the value analytics and the saved choice use, as on iOS.
 */
enum class ShareCardShape(val raw: String, val heightDp: Int, @param:StringRes val label: Int) {
    /** 4:5, a feed post (Instagram, Threads, Facebook): 1080 × 1350. */
    FEED("4x5", 450, R.string.share_shape_feed),

    /** 9:16, a story (Instagram Stories, LINE VOOM): 1080 × 1920. */
    STORY("9x16", 640, R.string.share_shape_story),

    /** 1:1, a LINE chat: 1080 × 1080. */
    SQUARE("1x1", 360, R.string.share_shape_square)
    ;

    val widthDp: Int get() = WIDTH_DP

    /** The rendered image's size in pixels. */
    val pixelWidth: Int get() = (WIDTH_DP * RENDER_SCALE).toInt()
    val pixelHeight: Int get() = (heightDp * RENDER_SCALE).toInt()

    companion object {
        const val WIDTH_DP = 360

        /** Pixels per dp when rendered (iOS `renderScale`, 3x). */
        const val RENDER_SCALE = 3f

        /** The last shape chosen in the preview, under iOS's defaults key. */
        const val PREFERENCE_KEY = "shareCardShape"

        /** The saved [raw] value, or [FEED] for anything else (iOS's default). */
        fun fromRaw(raw: String?): ShareCardShape = entries.firstOrNull { it.raw == raw } ?: FEED
    }
}
