package com.kfpun.twaqi.data.cache

import java.io.File
import java.io.IOException
import java.time.Instant

/** A saved response body and when it was written. */
data class Saved<T>(val value: T, val savedAt: Instant)

/**
 * Whole-file text caches under the offline cache root (iOS keeps these in Application Support:
 * Android's `filesDir`, not `cacheDir`, so the system doesn't clear them under storage pressure).
 *
 * Writes go to a temporary file and are renamed into place, so a reader never sees half a file.
 * Reads skip anything older than [OfflineCacheRetention.maxAge].
 */
class CacheStore(val root: File, private val now: () -> Instant = Instant::now) {

    fun file(name: String): File = File(root, name)

    @Synchronized
    fun write(name: String, text: String) {
        val target = file(name)
        target.parentFile?.mkdirs()
        val temp = File(target.parentFile, "${target.name}.tmp")
        try {
            temp.writeText(text)
            if (!temp.renameTo(target)) {
                target.delete()
                if (!temp.renameTo(target)) throw IOException("rename failed")
            }
            // The age of a cache file is its modification time; keep it on the injected clock.
            target.setLastModified(now().toEpochMilli())
        } catch (e: IOException) {
            temp.delete()
        }
    }

    /** The file's text, or null when missing or older than a week. */
    @Synchronized
    fun read(name: String): Saved<String>? {
        val target = file(name)
        val savedAt = OfflineCacheRetention.modificationDate(target) ?: return null
        if (OfflineCacheRetention.isExpired(savedAt, now())) return null
        val text = try {
            target.readText()
        } catch (e: IOException) {
            return null
        }
        return Saved(text, savedAt)
    }

    companion object {
        const val COUNTRIES = "countries.json"
        const val FORECAST = "aqi-forecast.json"

        fun stations(countryCode: String) = "stations-$countryCode.json"
    }
}
