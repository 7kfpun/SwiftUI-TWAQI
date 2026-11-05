package com.kfpun.twaqi.ui.main

import org.junit.Assert.assertEquals
import org.junit.Test

class StationSearchTest {
    private val stations = listOf(
        pollutant(
            1,
            name = "Keelung",
            nameLocal = "基隆",
            county = "Keelung City",
            countyLocal = "基隆市",
            township = "信義區"
        ),
        pollutant(
            2,
            name = "Songshan",
            nameLocal = "松山",
            county = "Taipei City",
            countyLocal = "臺北市",
            township = "松山區"
        ),
        pollutant(3, name = "Taichung Boulevard", nameLocal = "臺灣大道")
    )

    private fun ids(query: String) = StationSearch.filter(stations, query).map { it.stationId }

    @Test
    fun blankQueryKeepsEveryStation() {
        assertEquals(listOf(1, 2, 3), ids(""))
        assertEquals(listOf(1, 2, 3), ids("   "))
    }

    @Test
    fun matchesEitherNameIgnoringCase() {
        assertEquals(listOf(1), ids("keel"))
        assertEquals(listOf(2), ids("SONG"))
        assertEquals(listOf(1), ids("基隆"))
    }

    @Test
    fun matchesTownshipAndCountyInEitherLanguage() {
        assertEquals(listOf(1), ids("信義"))
        assertEquals(listOf(2), ids("taipei"))
        assertEquals(listOf(2), ids("台北市"))
    }

    @Test
    fun foldsTaiVariants() {
        assertEquals(listOf(3), ids("台灣"))
        assertEquals(listOf(3), ids("臺灣大道"))
    }

    @Test
    fun noMatchIsEmpty() {
        assertEquals(emptyList<Int>(), ids("Hualien"))
    }
}
