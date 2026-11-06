package com.kfpun.twaqi.data.cams

import com.kfpun.twaqi.data.cache.CacheStore
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient

/**
 * Fetches and caches the cam manifest (iOS `StationCamStore`).
 *
 * The last good manifest is kept under the offline cache root, so a station page opened offline
 * still knows which cam it has. A copy younger than [TTL] is used as is; an older one is
 * refreshed, and kept if the refresh fails. One request at a time: a page opened twice fetches
 * once.
 */
class StationCamStore(
    private val endpoints: StationCamEndpoints,
    private val store: CacheStore,
    private val http: OkHttpClient,
    private val now: () -> Instant = Instant::now,
    private val io: CoroutineDispatcher = Dispatchers.IO
) {
    private val mutex = Mutex()
    private var cams: List<StationCam>? = null
    private var fetchedAt: Instant? = null

    /** All known cams; empty if there has never been a manifest to read. */
    suspend fun cams(): List<StationCam> = mutex.withLock {
        if (cams == null) loadFromDisk()

        val known = cams
        val at = fetchedAt
        if (known != null && at != null && Duration.between(at, now()) < TTL) return known

        val url = endpoints.manifest
        val fetched = url?.let { http.fetchBytes(it, io) }
        if (fetched is CamFetch.Ok) {
            val text = fetched.bytes.decodeToString()
            StationCamManifest.parse(text)?.let { parsed ->
                cams = parsed
                fetchedAt = now()
                withContext(io) { store.write(FILE_NAME, text) }
            }
        }
        cams.orEmpty()
    }

    /** A copy older than a week is not used, even as a last good one ([CacheStore.read]). */
    private suspend fun loadFromDisk() {
        val saved = withContext(io) { store.read(FILE_NAME) } ?: return
        val parsed = StationCamManifest.parse(saved.value) ?: return
        cams = parsed
        fetchedAt = saved.savedAt
    }

    companion object {
        /**
         * Cams are re-synced about hourly, and each frame's URL is versioned by the capture time in
         * the manifest, so this is also how stale a frame can be.
         */
        val TTL: Duration = Duration.ofHours(1)

        const val FILE_NAME = "station-cams-manifest.json"
    }
}
