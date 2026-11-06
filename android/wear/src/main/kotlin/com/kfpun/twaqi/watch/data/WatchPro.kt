package com.kfpun.twaqi.watch.data

import com.kfpun.twaqi.watch.BuildConfig

/**
 * Whether the reader has Pro, which unlocks the complication's number and other styles and the
 * tile (iOS `WatchPro`). The app and the free face complication need nothing.
 *
 * The answer is the phone's (FOX-58 `ProRepository.isPro`), relayed over the Data Layer and kept
 * in [WatchStore.isProUnlocked], so nothing flashes a lock while the phone is out of reach.
 */
object WatchPro {
    /** The developer section's override (debug builds only; iOS: Debug and TestFlight). */
    enum class Override(val id: String) {
        PHONE("phone"),
        FORCE_PRO("forcePro"),
        FORCE_FREE("forceFree");

        companion object {
            fun fromId(id: String?): Override = entries.firstOrNull { it.id == id } ?: PHONE
        }
    }

    /** Whether the override can be used in this build. */
    val overrideAvailable: Boolean get() = BuildConfig.DEBUG

    fun isUnlocked(store: WatchStore): Boolean = resolve(store.isProUnlocked, store.proOverride, overrideAvailable)

    internal fun resolve(phoneSaysPro: Boolean, overrideId: String?, overrideAvailable: Boolean): Boolean {
        if (!overrideAvailable) return phoneSaysPro
        return when (Override.fromId(overrideId)) {
            Override.PHONE -> phoneSaysPro
            Override.FORCE_PRO -> true
            Override.FORCE_FREE -> false
        }
    }
}
