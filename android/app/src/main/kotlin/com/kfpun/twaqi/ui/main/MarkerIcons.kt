package com.kfpun.twaqi.ui.main

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.util.LruCache
import androidx.core.graphics.createBitmap
import com.google.android.gms.maps.model.BitmapDescriptor
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.kfpun.twaqi.data.model.Wind
import kotlin.math.ceil
import kotlin.math.sqrt

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
            BitmapDescriptorFactory.fromBitmap(pillBitmap(text, color, foregroundColor))
        }

    /** The bitmap behind [pill]. */
    fun pillBitmap(text: String, color: Int, foregroundColor: Int): Bitmap {
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
        return bitmap
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

    /**
     * Wind mode's arrow (iOS `MarkerIcons.arrow`): shaft and chevron, cased in white so it stays
     * legible over green terrain, drawn pointing south. The marker rotates it by the bearing, so one
     * bitmap per strength level and colour serves every direction: at most
     * ([Wind.STRENGTH_STEPS] + 1) × 7 arrows, all reused while scrubbing.
     *
     * Square-rooted, not linear: Taiwan's stations mostly report 1–4 m/s, which a linear scale
     * squeezes into the bottom third. Head and stroke grow with the length, so a long arrow reads as
     * strong rather than thin.
     */
    fun arrow(strengthLevel: Int, color: Int): BitmapDescriptor = cached("arrow|$strengthLevel|$color") {
        BitmapDescriptorFactory.fromBitmap(arrowBitmap(strengthLevel, color))
    }

    /** The bitmap behind [arrow]. */
    fun arrowBitmap(strengthLevel: Int, color: Int): Bitmap {
        val strength = sqrt(strengthLevel.coerceIn(0, Wind.STRENGTH_STEPS).toFloat() / Wind.STRENGTH_STEPS)
        val length = (12 + 58 * strength) * density
        val head = (5 + 5 * strength) * density
        val stroke = (1.8f + 1.8f * strength) * density
        val inset = stroke + 1.5f * density
        val width = head * 2 + inset * 2
        val height = length + inset * 2
        val bitmap = createBitmap(ceil(width).toInt(), ceil(height).toInt())
        val canvas = Canvas(bitmap)
        val midX = width / 2
        val tip = height - inset
        val path = Path().apply {
            moveTo(midX, inset)
            lineTo(midX, tip)
            moveTo(midX - head, tip - head)
            lineTo(midX, tip)
            lineTo(midX + head, tip - head)
        }
        canvas.drawPath(path, line(CASING, stroke + 2 * density))
        canvas.drawPath(path, line(opaque(color), stroke))
        return bitmap
    }

    /** Wind mode, no wind (iOS `MarkerIcons.calm`): a ring, so still air doesn't read as missing data. */
    fun calm(color: Int): BitmapDescriptor = cached("calm|$color") {
        BitmapDescriptorFactory.fromBitmap(calmBitmap(color))
    }

    /** The bitmap behind [calm]. */
    fun calmBitmap(color: Int): Bitmap {
        val diameter = 9 * density
        val inset = 2.5f * density
        val size = diameter + inset * 2
        val bitmap = createBitmap(ceil(size).toInt(), ceil(size).toInt())
        val canvas = Canvas(bitmap)
        canvas.drawCircle(size / 2, size / 2, diameter / 2, line(CASING, 3.5f * density))
        canvas.drawCircle(size / 2, size / 2, diameter / 2, line(opaque(color), 2 * density))
        return bitmap
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

    private fun line(argb: Int, width: Float) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = argb
        style = Paint.Style.STROKE
        strokeWidth = width
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private fun opaque(rgb: Int): Int = rgb or OPAQUE

    private companion object {
        const val WHITE = 0xFFFFFF
        const val OPAQUE = 0xFF000000.toInt()

        /** White at 85 %, under the coloured stroke. */
        const val CASING = 0xD9FFFFFF.toInt()
    }
}
