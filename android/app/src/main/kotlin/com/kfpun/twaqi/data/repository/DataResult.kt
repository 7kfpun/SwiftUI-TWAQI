package com.kfpun.twaqi.data.repository

import java.time.Instant

/**
 * What a repository read gives a screen: fresh data, the last saved copy after a failed refresh
 * (stale: say so, with its age), or nothing at all.
 */
sealed interface DataResult<out T> {
    /** Fetched just now. */
    data class Fresh<T>(val value: T, val fetchedAt: Instant) : DataResult<T>

    /** The request failed; this is the last good copy, saved at [savedAt]. */
    data class Stale<T>(val value: T, val savedAt: Instant, val error: Throwable) : DataResult<T>

    /** The request failed and there was nothing saved to show. */
    data class Failed(val error: Throwable) : DataResult<Nothing>

    val valueOrNull: T? get() = when (this) {
        is Fresh -> value
        is Stale -> value
        is Failed -> null
    }
}
