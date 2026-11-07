package com.kfpun.twaqi.data.cams

import com.kfpun.twaqi.data.cache.OfflineCacheRetention
import java.io.File
import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient

/** One hour of a cam's history, as the scrubber gets it. */
sealed interface CamHourResult<out T> {
    /** The hour's frame, downsampled for scrubbing. */
    data class Thumbnail<T>(val image: T) : CamHourResult<T>

    /** No frame filed for this hour (a plain 404): the cam was down, or the hour isn't in yet. */
    data object Missing : CamHourResult<Nothing>

    /** Network or server trouble; worth trying again later. */
    data object Failed : CamHourResult<Nothing>
}

/** What the history loader reads, so it can be tested without disk or network. */
interface CamHistorySource<T> {
    /** The saved thumbnail for [hour]; null when it isn't on disk (or is over a week old). No network. */
    suspend fun savedThumbnail(hour: StationCamHour): T?

    /** The saved frame for [hour] at full resolution. No network. */
    suspend fun savedFullImage(hour: StationCamHour): T?

    /** [hour]'s thumbnail from disk, or else downloaded and saved. */
    suspend fun load(hour: StationCamHour): CamHourResult<T>
}

/**
 * Hourly cam frames for the station page's 24-hour scrubber, on disk (iOS
 * `StationCamHistoryCache`).
 *
 * Sits beside [StationCamFrameCache] (the latest frame of each cam) and leaves it alone: one file
 * per (cam, hour) in `offline-cache/station-cams/history/`, named by
 * [StationCamHour.cacheFileName]. An hour's frame never changes once filed, so a saved one is
 * shown as is and never fetched again. Files older than a week are not returned, and
 * [OfflineCacheRetention.purge] deletes them.
 *
 * Nothing here prefetches: the loader asks for one hour at a time.
 */
class StationCamHistoryCache<T>(
    private val directory: File,
    private val endpoints: StationCamEndpoints,
    private val http: OkHttpClient,
    private val decoder: CamImageDecoder<T>,
    private val now: () -> Instant = Instant::now,
    private val io: CoroutineDispatcher = Dispatchers.IO
) : CamHistorySource<T> {

    fun file(hour: StationCamHour): File = File(directory, hour.cacheFileName)

    override suspend fun savedThumbnail(hour: StationCamHour): T? = withContext(io) {
        savedBytes(hour)?.let { decoder.thumbnail(it, THUMBNAIL_PIXEL_SIZE) }
    }

    override suspend fun savedFullImage(hour: StationCamHour): T? = withContext(io) {
        savedBytes(hour)?.let(decoder::full)
    }

    override suspend fun load(hour: StationCamHour): CamHourResult<T> =
        savedThumbnail(hour)?.let { CamHourResult.Thumbnail(it) } ?: fetch(hour)

    /** Downloads [hour]'s frame and saves it. A failure leaves the disk as it was. */
    suspend fun fetch(hour: StationCamHour): CamHourResult<T> {
        val url = endpoints.hour(hour) ?: return CamHourResult.Failed
        return when (val fetched = http.fetchBytes(url, io)) {
            // The bucket answers 404 for a key that isn't there: an hour with no frame, not an error.
            CamFetch.Status(404) -> CamHourResult.Missing

            is CamFetch.Ok -> withContext(io) {
                val thumbnail = decoder.thumbnail(fetched.bytes, THUMBNAIL_PIXEL_SIZE)
                    ?: return@withContext CamHourResult.Failed
                writeAtomically(file(hour), fetched.bytes, now())
                CamHourResult.Thumbnail(thumbnail)
            }

            else -> CamHourResult.Failed
        }
    }

    private fun savedBytes(hour: StationCamHour): ByteArray? {
        val file = file(hour)
        if (OfflineCacheRetention.isExpired(OfflineCacheRetention.modificationDate(file), now())) return null
        return try {
            file.readBytes()
        } catch (e: IOException) {
            null
        }
    }

    companion object {
        /** Subdirectory of [StationCamFrameCache.DIRECTORY_NAME]. */
        const val DIRECTORY_NAME = "history"

        /**
         * Longest edge of a scrubbing thumbnail, in pixels: sharp enough for the frame while the
         * finger moves, a fraction of the 1920×1080 decode.
         */
        const val THUMBNAIL_PIXEL_SIZE = 640
    }
}
