package com.kfpun.twaqi.data.cams

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap

/** Cam JPEGs as Compose images. Runs on the caches' IO dispatcher, never the main thread. */
object BitmapCamImageDecoder : CamImageDecoder<ImageBitmap> {
    override fun full(bytes: ByteArray): ImageBitmap? = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.prepared()

    /** JPEG scales down by powers of two while decoding, far cheaper than the full frame. */
    override fun thumbnail(bytes: ByteArray, maxPixelSize: Int): ImageBitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val longest = maxOf(bounds.outWidth, bounds.outHeight)
        if (longest <= 0) return null
        var sample = 1
        while (longest / (sample * 2) >= maxPixelSize) sample *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)?.prepared()
    }

    /** Uploads the pixels ahead of the first draw (iOS `preparingForDisplay`). */
    private fun Bitmap.prepared(): ImageBitmap = apply { prepareToDraw() }.asImageBitmap()
}
