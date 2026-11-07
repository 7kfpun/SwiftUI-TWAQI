package com.kfpun.twaqi.ui.navigation

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.CreationExtras
import com.kfpun.twaqi.ui.MainTab
import kotlin.reflect.KClass
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * FOX-119: which station shows where on phones and in wide windows, and that the tab and the open
 * stations survive a configuration change (the view model) and process death (its SavedStateHandle).
 */
class HomeNavigationTest {
    @Test
    fun phonesShowTheStationOverTheTabs() {
        val state = HomeNavigationState().opening(101)
        assertEquals(101, state.fullScreenStation(isWide = false))
        assertNull(state.paneStation(MainTab.MAIN, isWide = false))
    }

    @Test
    fun wideWindowsShowItBesideTheMapOrList() {
        listOf(MainTab.MAIN, MainTab.DETAILS_LIST, MainTab.FAVOURITES).forEach { tab ->
            val state = HomeNavigationState(tab = tab).opening(7)
            assertNull(tab.name, state.fullScreenStation(isWide = true))
            assertEquals(tab.name, 7, state.paneStation(tab, isWide = true))
        }
    }

    /** An alert or link that arrives on Forecast or Help, which have no station pane, covers the tabs. */
    @Test
    fun tabsWithoutAPaneShowItOverTheTabsEvenWhenWide() {
        listOf(MainTab.FORECAST, MainTab.HELP).forEach { tab ->
            val state = HomeNavigationState(tab = tab).opening(7)
            assertEquals(tab.name, 7, state.fullScreenStation(isWide = true))
            assertNull(tab.name, state.paneStation(tab, isWide = true))
        }
    }

    /** Folding hands the panel's station to the full screen and unfolding hands it back (iOS `handOverStation`). */
    @Test
    fun foldingAndUnfoldingKeepTheStation() {
        val unfolded = HomeNavigationState(tab = MainTab.DETAILS_LIST).opening(42)
        assertEquals(42, unfolded.paneStation(MainTab.DETAILS_LIST, isWide = true))
        assertEquals(42, unfolded.fullScreenStation(isWide = false))
        assertEquals(42, unfolded.closing().opening(42).paneStation(MainTab.DETAILS_LIST, isWide = true))
    }

    /** Each tab keeps its own station, as each iPad tab keeps its own split view. */
    @Test
    fun eachTabKeepsItsOwnStation() {
        val state = HomeNavigationState()
            .opening(1)
            .selecting(MainTab.FAVOURITES)
            .opening(2)
            .selecting(MainTab.MAIN)
        assertEquals(1, state.paneStation(MainTab.MAIN, isWide = true))
        assertEquals(2, state.paneStation(MainTab.FAVOURITES, isWide = true))
        assertEquals(mapOf(MainTab.FAVOURITES to 2), state.closing().stations)
    }

    @Test
    fun aRecreatedViewModelRestoresFromTheSavedState() {
        val handle = SavedStateHandle()
        HomeNavigationViewModel(handle).apply {
            selectTab(MainTab.FAVOURITES)
            openStation(42)
            selectTab(MainTab.MAIN)
            openStation(7)
            selectTab(MainTab.DETAILS_LIST)
        }
        // Process death: only what the handle saved comes back.
        val restored = HomeNavigationViewModel(SavedStateHandle(handle.keys().associateWith { handle.get<Any>(it) }))
        assertEquals(
            HomeNavigationState(MainTab.DETAILS_LIST, mapOf(MainTab.FAVOURITES to 42, MainTab.MAIN to 7)),
            restored.uiState.value
        )
    }

    @Test
    fun aClosedStationIsNotRestored() {
        val handle = SavedStateHandle()
        HomeNavigationViewModel(handle).apply {
            openStation(7)
            closeStation()
        }
        assertEquals(HomeNavigationState(), HomeNavigationViewModel(handle).uiState.value)
    }

    @Test
    fun emptyOrUnknownSavedStateStartsOnTheMap() {
        assertEquals(HomeNavigationState(), HomeNavigationViewModel(SavedStateHandle()).uiState.value)
        val unknown = SavedStateHandle(mapOf("home.tab" to "GONE"))
        assertEquals(MainTab.MAIN, HomeNavigationViewModel(unknown).uiState.value.tab)
    }

    /** The page's view models outlive the move between panel and full screen, and go when it closes. */
    @Test
    fun stationViewModelsLiveUntilThePageCloses() {
        val navigation = HomeNavigationViewModel(SavedStateHandle())
        navigation.openStation(7)
        val store = navigation.stationStore(MainTab.MAIN, 7)
        val page = ViewModelProvider.create(store, Probe.Factory)[Probe::class]
        assertSame(store, navigation.stationStore(MainTab.MAIN, 7))
        assertFalse(page.cleared)

        // Another station on the same tab replaces it.
        navigation.openStation(8)
        assertTrue(page.cleared)
        assertNotSame(store, navigation.stationStore(MainTab.MAIN, 7))

        val next = ViewModelProvider.create(navigation.stationStore(MainTab.MAIN, 8), Probe.Factory)[Probe::class]
        navigation.closeStation()
        assertTrue(next.cleared)
    }

    class Probe : ViewModel() {
        var cleared = false

        override fun onCleared() {
            cleared = true
        }

        object Factory : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: KClass<T>, extras: CreationExtras): T = Probe() as T
        }
    }
}
