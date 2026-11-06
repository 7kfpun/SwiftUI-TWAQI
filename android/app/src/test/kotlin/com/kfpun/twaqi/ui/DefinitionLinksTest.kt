package com.kfpun.twaqi.ui

import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.ui.station.DefinitionLinks
import org.junit.Assert.assertEquals
import org.junit.Test

/** iOS `DefinitionPages.url`. */
class DefinitionLinksTest {
    @Test
    fun englishArticles() {
        assertEquals(
            "https://en.wikipedia.org/wiki/Air_quality_index",
            DefinitionLinks.url(AirIndexType.AQI, chinese = false)
        )
        assertEquals(
            "https://en.wikipedia.org/wiki/Particulates",
            DefinitionLinks.url(AirIndexType.PM10, chinese = false)
        )
    }

    @Test
    fun chineseArticlesArePercentEncoded() {
        assertEquals(
            "https://zh.wikipedia.org/wiki/%E8%87%AD%E6%B0%A7",
            DefinitionLinks.url(AirIndexType.O3, chinese = true)
        )
    }
}
