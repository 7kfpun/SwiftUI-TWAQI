package com.kfpun.twaqi.ui.navigation

import androidx.compose.foundation.ScrollState
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.kfpun.twaqi.ui.MainTab
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The selected tab and the station open on each tab (FOX-119). One station per tab, as each iPad
 * tab keeps its own split view: on a phone the selected tab's station covers the tabs; in a wide
 * window it sits beside the map or the list instead. Folding, unfolding or resizing hands it from one
 * to the other (iOS `MainView.handOverStation`), because both read the same [stations].
 */
data class HomeNavigationState(val tab: MainTab = MainTab.MAIN, val stations: Map<MainTab, Int> = emptyMap()) {
    /** The station shown over the tabs: always on a phone; in a wide window only for tabs without a pane. */
    fun fullScreenStation(isWide: Boolean): Int? = stations[tab]?.takeIf { !isWide || tab !in PANE_TABS }

    /** The station beside [tab]'s map or list, in a wide window. */
    fun paneStation(tab: MainTab, isWide: Boolean): Int? = stations[tab]?.takeIf { isWide && tab in PANE_TABS }

    fun selecting(tab: MainTab) = copy(tab = tab)

    /** A tapped station, alert or link opens on the tab in front, replacing what it showed. */
    fun opening(stationId: Int) = copy(stations = stations + (tab to stationId))

    fun closing(tab: MainTab = this.tab) = copy(stations = stations - tab)

    companion object {
        /** Tabs whose station sits beside their content in a wide window (the map, Search, Favourites). */
        val PANE_TABS = setOf(MainTab.MAIN, MainTab.DETAILS_LIST, MainTab.FAVOURITES)
    }
}

/**
 * Holds [HomeNavigationState] across rotation, folding and resizing (the view model) and process
 * death (its [SavedStateHandle]). It also keeps each open station page's view models, so a page
 * handed from the panel to the full screen keeps its data and scroll position instead of reloading.
 */
class HomeNavigationViewModel(private val saved: SavedStateHandle) : ViewModel() {
    private val state = MutableStateFlow(restore(saved))
    val uiState: StateFlow<HomeNavigationState> = state.asStateFlow()

    private val stationStores = mutableMapOf<String, ViewModelStore>()

    fun selectTab(tab: MainTab) = update(state.value.selecting(tab))

    fun openStation(stationId: Int) = update(state.value.opening(stationId))

    fun closeStation(tab: MainTab = state.value.tab) = update(state.value.closing(tab))

    /** View models for the page of [stationId] open on [tab]; cleared once that page closes. */
    fun stationStore(tab: MainTab, stationId: Int): ViewModelStore =
        stationStores.getOrPut(storeKey(tab, stationId)) { ViewModelStore() }

    private fun update(next: HomeNavigationState) {
        state.value = next
        saved[KEY_TAB] = next.tab.name
        MainTab.entries.forEach { saved[stationKey(it)] = next.stations[it] }
        val open = next.stations.map { (tab, id) -> storeKey(tab, id) }.toSet()
        stationStores.keys.filter { it !in open }.forEach { stationStores.remove(it)?.clear() }
    }

    override fun onCleared() {
        stationStores.values.forEach { it.clear() }
        stationStores.clear()
    }

    companion object {
        private const val KEY_TAB = "home.tab"

        private fun stationKey(tab: MainTab) = "home.station.${tab.name}"

        private fun storeKey(tab: MainTab, stationId: Int) = "${tab.name}:$stationId"

        internal fun restore(saved: SavedStateHandle): HomeNavigationState {
            val tab = saved.get<String>(KEY_TAB)?.let { name -> MainTab.entries.firstOrNull { it.name == name } }
            val stations = MainTab.entries.mapNotNull { t -> saved.get<Int>(stationKey(t))?.let { t to it } }.toMap()
            return HomeNavigationState(tab ?: MainTab.MAIN, stations)
        }

        val Factory = viewModelFactory {
            initializer { HomeNavigationViewModel(createSavedStateHandle()) }
        }
    }
}

/** A station page's scroll position, kept with its view models so it follows the page between panel and full screen. */
class StationPageScroll : ViewModel() {
    val scrollState = ScrollState(0)
}
