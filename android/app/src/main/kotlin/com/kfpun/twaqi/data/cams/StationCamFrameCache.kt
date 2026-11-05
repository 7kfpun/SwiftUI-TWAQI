package com.kfpun.twaqi.data.cams

import com.kfpun.twaqi.data.cache.OfflineCacheRetention
import java.io.File
import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import okhttp3.OkHttpClient

/**
 * A cam frame ready to draw.
 *
 * @property time the manifest's capture time for this frame, e.g. `"2026-10-30T22:30:00+08:00"`.
 */
data class CamFrame<T>(val image: T, val time: String?)

/** What the live frame loader reads, so it can be tested without disk or network. */
interface CamFrameSource<T> {
    /** The saved frame for [siteId]; null when there is none younger than a week. */
    suspend fun savedFrame(siteId: String): CamFrame<T>?

    /** [cam]'s current frame, downloaded and saved over the last one; null when that failed. */
    suspend fun fetch(cam: StationCam): CamFrame<T>?
}

/**
 * The last good frame of each cam, on disk (iOS `StationCamFrameCache`).
 *
 * The station page shows the saved frame at once and swaps in the new one when it arrives
 * (stale-while-revalidate), so the cam never drops back to a spinner, and offline it still shows
 * the last view from the station.
 *
 * One frame per cam, the latest, in `offline-cache/station-cams/`: `{siteId}.jpg` and
 * `{siteId}.json` holding its capture time. Frames older than a week are not returned, and
 * [OfflineCacheRetention.purge] deletes them.
 */
class StationCamFrameCache<T>(
    private val directory: File,
    private val endpoints: StationCamEndpoints,
    private val http: OkHttpClient,
    private val decoder: CamImageDecoder<T>,
    private val now: () -> Instant = Instant::now,
    private val io: CoroutineDispatcher = Dispatchers.IO
) : CamFrameSource<T> {

    override suspend fun savedFrame(siteId: String): CamFrame<T>? = withContext(io) { readFrame(siteId) }

    override suspend fun fetch(cam: StationCam): CamFrame<T>? {
        val url = endpoints.latest(cam) ?: return null
        val fetched = http.fetchBytes(url, io) as? CamFetch.Ok ?: return null
        return withContext(io) {
            val image = decoder.full(fetched.bytes) ?: return@withContext null
            write(fetched.bytes, cam.time, cam.siteId)
            CamFrame(image, cam.time)
        }
    }

    fun imageFile(siteId: String): File = File(directory, "$siteId.jpg")

    fun metaFile(siteId: String): File = File(directory, "$siteId.json")

    private fun readFrame(siteId: String): CamFrame<T>? {
        val file = imageFile(siteId)
        if (OfflineCacheRetention.isExpired(OfflineCacheRetention.modificationDate(file), now())) return null
        val bytes = try {
            file.readBytes()
        } catch (e: IOException) {
            return null
        }
        val image = decoder.full(bytes) ?: return null
        val time = runCatching {
            (Json.parseToJsonElement(metaFile(siteId).readText()).jsonObject["time"] as? JsonPrimitive)
                ?.takeIf { it.isString }?.content
        }.getOrNull()
        return CamFrame(image, time)
    }

    private fun write(bytes: ByteArray, time: String?, siteId: String) {
        // Old meta out, frame in, new meta in. Interrupted anywhere, a frame is left with no time
        // (shown without one, and downloaded again) rather than with another frame's time.
        metaFile(siteId).delete()
        if (!writeAtomically(imageFile(siteId), bytes, now())) return
        val meta: JsonObject = buildJsonObject { time?.let { put("time", it) } }
        writeAtomically(metaFile(siteId), meta.toString().encodeToByteArray(), now())
    }

    companion object {
        /** Inside the offline cache root, which [OfflineCacheRetention.purge] scans at any depth. */
        const val DIRECTORY_NAME = "station-cams"
    }
}
