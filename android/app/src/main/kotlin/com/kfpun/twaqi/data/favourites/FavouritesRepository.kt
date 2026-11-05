package com.kfpun.twaqi.data.favourites

import android.content.Context
import androidx.core.content.edit
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Where the favourites list is kept. Null from [read] means nothing was ever saved (a new install),
 * which is not the same as an empty list the reader left behind.
 */
interface FavouritesStore {
    fun read(): List<Int>?
    fun write(stationIds: List<Int>)
}

/**
 * Shared preferences, which Android backup carries to a new phone (`allowBackup`), as iOS keeps
 * the list in its defaults. Same key as iOS `SettingsStore.Keys.savedFavouriteStations`; stored as
 * `"126,85"`.
 */
class SharedPreferencesFavouritesStore(context: Context) : FavouritesStore {
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    override fun read(): List<Int>? = prefs.getString(KEY, null)?.let(::decode)

    override fun write(stationIds: List<Int>) {
        prefs.edit { putString(KEY, encode(stationIds)) }
    }

    companion object {
        const val PREFS = "favourites"
        const val KEY = "savedFavouriteStations"

        fun encode(stationIds: List<Int>): String = stationIds.joinToString(",")

        /** Anything that isn't a number is dropped rather than failing the whole list (iOS reads a bad value as empty). */
        fun decode(text: String): List<Int> = text.split(',').mapNotNull { it.trim().toIntOrNull() }.distinct()
    }
}

/**
 * The alerts side of Favourites (iOS `FavouriteAlerts`), which FOX-57 implements with FCM.
 * A station with an alert on is always a favourite; leaving Favourites turns its alerts off.
 * Reordering never touches alerts.
 */
interface FavouriteAlertsGateway {
    /** Stations with an alert on. */
    val alertedStationIds: StateFlow<Set<Int>>

    /** Turns both of a station's alerts off as it leaves Favourites; nothing to do when they are off. */
    fun clear(stationId: Int)
}

/** Until FOX-57: no station has alerts, so nothing needs confirming or clearing. */
object NoFavouriteAlerts : FavouriteAlertsGateway {
    override val alertedStationIds: StateFlow<Set<Int>> = MutableStateFlow(emptySet())

    override fun clear(stationId: Int) = Unit
}

/**
 * The reader's favourite stations, in their order (iOS `SettingsStore.savedFavouriteStations`).
 * The order is the reader's: the Favourites list and (FOX-59) the widget follow it.
 *
 * Saved on every change. Call from the main thread.
 */
class FavouritesRepository(private val store: FavouritesStore, val alerts: FavouriteAlertsGateway = NoFavouriteAlerts) {
    private val state = MutableStateFlow(store.read() ?: DEFAULT_FAVOURITES)

    /** Station ids, the reader's order. */
    val favourites: StateFlow<List<Int>> = state.asStateFlow()

    fun contains(stationId: Int): Boolean = stationId in state.value

    /** Adds [stationId] at the end; nothing when it is already a favourite. Returns whether it was added. */
    fun add(stationId: Int): Boolean {
        if (contains(stationId)) return false
        save(state.value + stationId)
        return true
    }

    /** Stations among [stationIds] with an alert on, which the reader confirms before removing. */
    fun needsConfirmation(stationIds: Collection<Int>): Boolean =
        stationIds.any { it in alerts.alertedStationIds.value }

    /**
     * Takes [stationIds] out of Favourites, turning off the alerts of any that have them (iOS
     * `FavouriteListViewModel.remove`). Ask first, through [needsConfirmation].
     * Returns the ids that were favourites.
     */
    fun remove(stationIds: Collection<Int>): List<Int> {
        val removed = state.value.filter { it in stationIds }
        if (removed.isEmpty()) return removed
        removed.forEach(alerts::clear)
        save(state.value.filterNot { it in stationIds })
        return removed
    }

    fun remove(stationId: Int): Boolean = remove(listOf(stationId)).isNotEmpty()

    /**
     * Saves the order of [listed], the stations the list shows. Saved stations the list doesn't
     * show (no reading yet) keep their place after the rest, as on iOS. Ids that aren't favourites
     * are ignored. Alerts are left as they are.
     */
    fun reorder(listed: List<Int>) {
        val current = state.value
        val shown = listed.filter { it in current }.distinct()
        val order = shown + current.filterNot { it in shown }
        if (order != current) save(order)
    }

    /** Moves the favourite at [from] to [to] in the full list. */
    fun move(from: Int, to: Int) {
        val list = state.value.toMutableList()
        if (from !in list.indices || to !in list.indices || from == to) return
        list.add(to, list.removeAt(from))
        save(list)
    }

    private fun save(list: List<Int>) {
        store.write(list)
        state.value = list
    }

    companion object {
        /**
         * A new install starts with one favourite, as on iOS (`SettingsStore` registers `[126]`), so the
         * Favourites tab isn't empty on first open. Only when nothing was ever saved.
         */
        val DEFAULT_FAVOURITES: List<Int> = listOf(126)
    }
}
