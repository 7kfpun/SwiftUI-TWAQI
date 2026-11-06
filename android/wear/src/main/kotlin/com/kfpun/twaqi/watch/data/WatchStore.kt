package com.kfpun.twaqi.watch.data

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import com.kfpun.twaqi.wearable.PhoneState
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Where [WatchStore] keeps its values: shared preferences on the watch, a map in tests. */
interface KeyValueStore {
    fun get(key: String): String?

    /** Removes [key] when [value] is null. */
    fun set(key: String, value: String?)
}

class SharedPreferencesKeyValueStore(private val prefs: SharedPreferences) : KeyValueStore {
    override fun get(key: String): String? = prefs.getString(key, null)

    override fun set(key: String, value: String?) = prefs.edit {
        if (value ==
            null
        ) {
            remove(key)
        } else {
            putString(key, value)
        }
    }
}

/**
 * State the watch app shares with its complication and tile (iOS `WatchStore`), and what the phone
 * relays (favourites, Pro, language). One process on Wear OS, so plain preferences are enough;
 * [changes] ticks on every write for the screens to follow.
 */
class WatchStore(private val values: KeyValueStore, private val clock: () -> Instant = Instant::now) {
    private val version = MutableStateFlow(0L)

    /** Ticks on every change, so the app can re-read what it shows. */
    val changes: StateFlow<Long> = version.asStateFlow()

    /** A station the reader picked by hand. Null means home: the closest station, or the 中正 default. */
    var pinnedStationId: Int?
        get() = values.get(PINNED)?.toIntOrNull()
        set(value) = write(PINNED, value?.toString())

    /**
     * Last reading fetched, so the app, complication and tile have something to show before (or
     * without) a network round trip. Its station is the one the complication and tile follow,
     * since they can't locate the reader.
     */
    var latestReading: WatchReading?
        get() = reading(LATEST)
        set(value) {
            write(LATEST, value?.toJson()?.toString())
            write(LATEST_FETCHED_AT, value?.let { clock().toEpochMilli().toString() })
        }

    /** When [latestReading] was last fetched, so a complication update right after the app's own fetch reuses it. */
    val latestFetchedAt: Instant?
        get() = values.get(LATEST_FETCHED_AT)?.toLongOrNull()?.let(Instant::ofEpochMilli)

    /** The station home last resolved to, so the picker can name it while another station is pinned. */
    var homeReading: WatchReading?
        get() = reading(HOME)
        set(value) = write(HOME, value?.toJson()?.toString())

    /** Whether [homeReading] came from the reader's location, not the 中正 default. */
    var homeIsLocated: Boolean
        get() = values.get(HOME_LOCATED) == "true"
        set(value) = write(HOME_LOCATED, value.toString())

    /** Asked for location once already (the app doesn't nag on every start). */
    var askedForLocation: Boolean
        get() = values.get(ASKED_LOCATION) == "true"
        set(value) = write(ASKED_LOCATION, value.toString())

    /** The phone's favourites, in the reader's order (relayed; the phone is the source of truth). */
    val favouriteStationIds: List<Int>
        get() = values.get(FAVOURITES)?.split(',')?.mapNotNull { it.trim().toIntOrNull() }.orEmpty()

    /** Last reading fetched for each favourite, so they list offline. Week-old readings are left out. */
    val favouriteReadings: List<WatchReading>
        get() = storedList(FAVOURITE_READINGS).filterNot(::isExpired)

    /** Merges fresh favourite readings in, replacing older readings of the same stations. */
    fun cacheFavouriteReadings(fresh: List<WatchReading>) {
        if (fresh.isEmpty()) return
        val ids = fresh.map { it.stationId }.toSet()
        write(FAVOURITE_READINGS, WatchReading.listToJson(favouriteReadings.filterNot { it.stationId in ids } + fresh))
    }

    /** The complication's record of each station's last two publishes (`WidgetRelevance.recording`). */
    var relevanceHistory: List<WatchReading>
        get() = storedList(RELEVANCE).filterNot(::isExpired)
        set(value) = write(RELEVANCE, WatchReading.listToJson(value))

    /** Adds [reading] to [relevanceHistory] and returns the station's reading from the publish before it. */
    fun recordForRelevance(reading: WatchReading): WatchReading? {
        val history = WidgetRelevance.recording(reading, relevanceHistory)
        relevanceHistory = history
        return WidgetRelevance.previous(reading, history)
    }

    /** The phone's Pro (FOX-58 `isPro`), last relayed. The phone's Play Billing is the source of truth. */
    var isProUnlocked: Boolean
        get() = values.get(PRO) == "true"
        set(value) = write(PRO, value.toString())

    /** The phone's app language id (`system`, `zh-Hant`, `en`), last relayed (FOX-56). */
    val languageId: String
        get() = values.get(LANGUAGE) ?: PhoneState.SYSTEM_LANGUAGE

    /** Debug builds only: the developer section's Pro override (`WatchPro`). */
    var proOverride: String?
        get() = values.get(PRO_OVERRIDE)
        set(value) = write(PRO_OVERRIDE, value)

    /** Revealed by tapping the version 7 times, as on the phone. */
    var developerMode: Boolean
        get() = values.get(DEVELOPER) == "true"
        set(value) = write(DEVELOPER, value.toString())

    /** What changed when the phone's state was applied. */
    data class PhoneStateChange(val favourites: Boolean, val pro: Boolean, val language: Boolean) {
        val any: Boolean get() = favourites || pro || language
    }

    /** Saves what the phone sent. Pro the phone hasn't read yet leaves the watch's last answer. */
    fun apply(state: PhoneState): PhoneStateChange {
        val favourites = state.favouriteStationIds != favouriteStationIds
        val pro = state.isPro != null && state.isPro != isProUnlocked
        val language = state.languageId != languageId
        if (favourites) write(FAVOURITES, state.favouriteStationIds.joinToString(","))
        if (pro) isProUnlocked = state.isPro == true
        if (language) write(LANGUAGE, state.languageId)
        return PhoneStateChange(favourites, pro, language)
    }

    /** The index and style a complication was set up with, or the defaults (AQI, labelled, as iOS). */
    fun complicationConfig(id: Int): Pair<String?, String?> =
        values.get("$COMPLICATION$id.index") to values.get("$COMPLICATION$id.style")

    fun setComplicationConfig(id: Int, index: String, style: String) {
        write("$COMPLICATION$id.index", index)
        write("$COMPLICATION$id.style", style)
    }

    fun removeComplicationConfig(id: Int) {
        write("$COMPLICATION$id.index", null)
        write("$COMPLICATION$id.style", null)
    }

    /** Raw access for `LockedComplicationLog`, which keeps its own queue here. */
    internal fun raw(key: String): String? = values.get(key)

    internal fun setRaw(key: String, value: String?) = write(key, value)

    /** True when [reading] was published more than [MAX_READING_AGE] ago. A publish time that doesn't parse is kept. */
    fun isExpired(reading: WatchReading, now: Instant = clock()): Boolean {
        val published = reading.publishedAt ?: return false
        return Duration.between(published, now) > MAX_READING_AGE
    }

    /** Deletes cached readings older than [MAX_READING_AGE]; reads already skip them (iOS `purgeExpiredReadings`). */
    fun purgeExpiredReadings(now: Instant = clock()) {
        for (key in listOf(LATEST, HOME)) {
            val stored = WatchReading.fromJson(WatchJson.parse(values.get(key)))
            if (stored != null && isExpired(stored, now)) write(key, null)
        }
        for (key in listOf(FAVOURITE_READINGS, RELEVANCE)) {
            val stored = storedList(key)
            val kept = stored.filterNot { isExpired(it, now) }
            if (kept.size != stored.size) write(key, WatchReading.listToJson(kept))
        }
    }

    private fun reading(key: String): WatchReading? =
        WatchReading.fromJson(WatchJson.parse(values.get(key)))?.takeUnless(::isExpired)

    private fun storedList(key: String): List<WatchReading> = WatchReading.listFromJson(values.get(key))

    private fun write(key: String, value: String?) {
        values.set(key, value)
        version.value++
    }

    companion object {
        /**
         * Readings older than this are not shown and are purged: past a week a cached reading says
         * more about when the watch was last online than about the air. The phone's
         * `OfflineCacheRetention` ceiling too.
         */
        val MAX_READING_AGE: Duration = Duration.ofDays(7)

        private const val PINNED = "pinnedStationId"
        private const val LATEST = "latestReading"
        private const val LATEST_FETCHED_AT = "latestFetchedAt"
        private const val HOME = "homeReading"
        private const val HOME_LOCATED = "homeIsLocated"
        private const val ASKED_LOCATION = "askedForLocation"
        private const val FAVOURITES = "favouriteStationIds"
        private const val FAVOURITE_READINGS = "favouriteReadings"
        private const val RELEVANCE = "relevanceHistory"
        private const val PRO = "isProUnlocked"
        private const val LANGUAGE = "appLanguage"
        private const val PRO_OVERRIDE = "proOverride"
        private const val DEVELOPER = "developerMode"
        private const val COMPLICATION = "complication."

        const val PREFS = "watch"

        @Volatile
        private var shared: WatchStore? = null

        fun get(context: Context): WatchStore = shared ?: synchronized(this) {
            shared ?: WatchStore(
                SharedPreferencesKeyValueStore(
                    context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                )
            ).also { shared = it }
        }
    }
}
