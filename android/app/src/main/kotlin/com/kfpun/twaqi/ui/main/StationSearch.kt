package com.kfpun.twaqi.ui.main

import com.kfpun.twaqi.data.model.Pollutant
import java.util.Locale

/**
 * The station list's search (iOS `DetailsListView.groupedStations`): a station matches when its
 * English or Chinese name, or its township or county in either language, contains the query,
 * ignoring case and 臺/台.
 */
object StationSearch {
    fun filter(pollutants: List<Pollutant>, query: String): List<Pollutant> {
        val needle = normalize(query)
        if (needle.isEmpty()) return pollutants
        return pollutants.filter { matches(it, needle) }
    }

    fun matches(pollutant: Pollutant, query: String): Boolean {
        val needle = normalize(query)
        if (needle.isEmpty()) return true
        return listOf(
            pollutant.name,
            pollutant.nameLocal,
            pollutant.township,
            pollutant.county,
            pollutant.countyLocal
        ).any { it != null && normalize(it).contains(needle) }
    }

    private fun normalize(text: String): String = text.trim().replace('臺', '台').lowercase(Locale.ROOT)
}
