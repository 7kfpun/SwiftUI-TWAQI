package com.kfpun.twaqi.data.cams

import java.io.File
import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.runInterruptible
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * The cam URLs on the webcam host (iOS `StationCam.baseURL`). The host comes from
 * `STATION_CAMS_URL` in `secrets.properties`; every URL is null when it isn't a URL, and the
 * station page then has no cam rather than a broken one.
 */
class StationCamEndpoints(baseUrl: String) {
    private val base: HttpUrl? = baseUrl.trim().toHttpUrlOrNull()

    val manifest: HttpUrl? get() = path("manifest.json")

    /**
     * `/stations/001.jpg`, versioned by capture time. The CDN caches each image for hours, so
     * without the version a fresh frame would sit behind a stale one until the edge cache expired.
     */
    fun latest(cam: StationCam): HttpUrl? = base?.newBuilder()
        ?.addPathSegments("stations/${cam.siteId}.jpg")
        ?.apply { cam.time?.let { addQueryParameter("t", it) } }
        ?.build()

    /** `/stations/001/2026-10-30/22.jpg`. Not versioned: an hour's frame never changes once filed. */
    fun hour(hour: StationCamHour): HttpUrl? = path(hour.objectKey)

    private fun path(segments: String): HttpUrl? = base?.newBuilder()?.addPathSegments(segments)?.build()
}

/** Turns downloaded or saved JPEG bytes into something the screen can draw. */
interface CamImageDecoder<T> {
    /** The whole frame; null for anything that isn't an image. */
    fun full(bytes: ByteArray): T?

    /** A downsampled decode, longest edge about [maxPixelSize]; null for anything that isn't an image. */
    fun thumbnail(bytes: ByteArray, maxPixelSize: Int): T?
}

/** The answer to one cam download. */
internal sealed interface CamFetch {
    class Ok(val bytes: ByteArray) : CamFetch

    data class Status(val code: Int) : CamFetch

    /** No answer: offline, timed out, or the body broke off. */
    data object Error : CamFetch
}

internal suspend fun OkHttpClient.fetchBytes(url: HttpUrl, io: CoroutineDispatcher): CamFetch = runInterruptible(io) {
    try {
        newCall(Request.Builder().url(url).build()).execute().use { response ->
            if (response.isSuccessful) {
                response.body?.bytes()?.let(CamFetch::Ok) ?: CamFetch.Error
            } else {
                CamFetch.Status(response.code)
            }
        }
    } catch (e: IOException) {
        CamFetch.Error
    }
}

/**
 * Writes [bytes] through a temporary file renamed into place, so a reader never sees half a frame,
 * and stamps it with [now]: a cache file's age is its modification time. False when it failed.
 */
internal fun writeAtomically(target: File, bytes: ByteArray, now: Instant): Boolean {
    target.parentFile?.mkdirs()
    val temp = File(target.parentFile, "${target.name}.tmp")
    return try {
        temp.writeBytes(bytes)
        if (!temp.renameTo(target)) {
            target.delete()
            if (!temp.renameTo(target)) throw IOException("rename failed")
        }
        target.setLastModified(now.toEpochMilli())
        true
    } catch (e: IOException) {
        temp.delete()
        false
    }
}
