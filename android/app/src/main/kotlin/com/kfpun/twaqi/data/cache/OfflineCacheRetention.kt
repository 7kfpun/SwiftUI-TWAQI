package com.kfpun.twaqi.data.cache

import java.io.File
import java.time.Duration
import java.time.Instant

/**
 * The hard ceiling on how old offline data may be and still be shown (iOS `OfflineCacheRetention`).
 *
 * Each store has its own soft TTL for refreshing (30 min for the forecast) and falls back to its
 * last good copy when a refresh fails. Past a week that copy says more about the last time the app
 * was online than about the air, so it is never returned, and [purge] deletes it.
 */
object OfflineCacheRetention {
    val maxAge: Duration = Duration.ofDays(7)

    /** Name of the one directory, inside `filesDir`, every offline cache lives under. */
    const val ROOT_DIRECTORY = "offline-cache"

    /** True when [date] is more than [maxAge] before [now]. A missing date counts as expired. */
    fun isExpired(date: Instant?, now: Instant = Instant.now()): Boolean =
        date == null || Duration.between(date, now) > maxAge

    /** When a cache file was last written; null when it doesn't exist. */
    fun modificationDate(file: File): Instant? =
        file.takeIf { it.isFile }?.lastModified()?.takeIf { it > 0 }?.let(Instant::ofEpochMilli)

    /**
     * Deletes every file under [root], at any depth, last written more than [maxAge] before [now].
     * Everything under the root is a cache, so nothing is matched by name; anything that is not a
     * cache must not be stored there. Returns the files removed.
     *
     * Each store also ignores an expired file when it reads one, so this is housekeeping rather
     * than what keeps old data off screen.
     */
    fun purge(root: File, now: Instant = Instant.now()): List<File> = root.walkTopDown()
        .filter { it.isFile && isExpired(modificationDate(it), now) }
        .filter { it.delete() }
        .toList()
}
