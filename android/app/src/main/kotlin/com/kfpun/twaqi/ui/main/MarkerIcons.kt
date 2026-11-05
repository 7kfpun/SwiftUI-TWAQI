package com.kfpun.twaqi.ui.main

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.util.LruCache
import androidx.core.graphics.createBitmap
import com.google.android.gms.maps.model.BitmapDescriptor
import com.google.android.gms.maps.model.BitmapDescriptorFactory

/**
 * Marker images, drawn once per look and reused (iOS `MarkerIcons`). The map uploads each distinct
 * image once, so every station on the same reading and band shares one bitmap.
 */
class MarkerIcons(context: Context) {
    private val density = context.resources.displayMetrics.density
    private val scaledDensity = density * context.resources.configuration.fontScale
    private val cache = LruCache<String, BitmapDescriptor>(600)

    /** The reading in a rounded pill, 40 × 30 dp, on the band colour with a white hairline. */
    fun pill(text: String, color: Int, foregroundColor: Int): BitmapDescriptor =
        cached("pill|$text|$color|$foregroundColor") {
            val width = 40 * density
            val height = 30 * density
            val bitmap = createBitmap(width.toInt(), height.toInt())
            val canvas = Canvas(bitmap)
            val border = 0.6f * density
            val rect = RectF(border / 2, border / 2, width - border / 2, height - border / 2)
            val radius = 8 * density
            canvas.drawRoundRect(rect, radius, radius, fill(color))
            canvas.drawRoundRect(rect, radius, radius, stroke(WHITE, border))
            val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color = opaque(foregroundColor)
                textSize = 15 * scaledDensity.coerceAtMost(density * 1.15f)
                typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
                textAlign = Paint.Align.CENTER
            }
            val baseline = height / 2 - (textPaint.descent() + textPaint.ascent()) / 2
            canvas.drawText(text, width / 2, baseline, textPaint)
            BitmapDescriptorFactory.fromBitmap(bitmap)
        }

    /** A cluster: its station count in a circle on the worst band's colour. */
    fun cluster(count: Int, color: Int, foregroundColor: Int): BitmapDescriptor =
        cached("cluster|$count|$color|$foregroundColor") {
            val size = 40 * density
            val bitmap = createBitmap(size.toInt(), size.toInt())
            val canvas = Canvas(bitmap)
            val border = 2 * density
            val radius = size / 2 - border / 2
            canvas.drawCircle(size / 2, size / 2, radius, fill(color))
            canvas.drawCircle(size / 2, size / 2, radius, stroke(WHITE, border))
            val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color = opaque(foregroundColor)
                textSize = 14 * density
                typeface = Typeface.DEFAULT_BOLD
                textAlign = Paint.Align.CENTER
            }
            val baseline = size / 2 - (textPaint.descent() + textPaint.ascent()) / 2
            canvas.drawText(if (count > 99) "99+" else count.toString(), size / 2, baseline, textPaint)
            BitmapDescriptorFactory.fromBitmap(bitmap)
        }

    private fun cached(key: String, draw: () -> BitmapDescriptor): BitmapDescriptor =
        cache.get(key) ?: draw().also { cache.put(key, it) }

    private fun fill(color: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = opaque(color)
        style = Paint.Style.FILL
    }

    private fun stroke(color: Int, width: Float) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = opaque(color)
        style = Paint.Style.STROKE
        strokeWidth = width
    }

    private fun opaque(rgb: Int): Int = rgb or OPAQUE

    private companion object {
        const val WHITE = 0xFFFFFF
        const val OPAQUE = 0xFF000000.toInt()
    }
}
