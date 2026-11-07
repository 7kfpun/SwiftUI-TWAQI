package com.kfpun.twaqi.widget

import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType
import java.io.File
import java.util.Locale
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Test
import org.w3c.dom.Element

/**
 * FOX-120: what TalkBack reads for the widget's index label and pager, in both languages (iOS
 * `Widget.show_index`, `Widget.page_position`). Unit tests run from the module directory (android/app).
 */
class WidgetAccessibilityTest {
    private val english = strings("values")
    private val chinese = strings("values-zh-rTW")

    @Test
    fun indexLabelNamesTheIndexATapShows() {
        val described = WidgetAccessibility.showIndex(AirIndexType.AQI)
        assertEquals(R.string.widget_show_index, described.id)
        assertEquals("Show PM2.5", english(described))
        assertEquals("顯示 PM2.5", chinese(described))
        // The last index steps back to the first.
        val last = WidgetPaging.indexCycle.last()
        assertEquals("Show AQI", english(WidgetAccessibility.showIndex(last)))
    }

    @Test
    fun pagerReadsThePositionFromOne() {
        val described = WidgetAccessibility.pagePosition(page = 1, count = 5)
        assertEquals(R.string.widget_page_position, described.id)
        assertEquals("Station 2 of 5", english(described))
        assertEquals("第 2 個測站，共 5 個", chinese(described))
        assertEquals("Station 1 of 4", english(WidgetAccessibility.pagePosition(page = 0, count = 4)))
    }

    private fun english(string: WidgetString) = format(english, string)

    private fun chinese(string: WidgetString) = format(chinese, string)

    /** As `Context.getString(id, args)` formats it. */
    private fun format(strings: Map<String, String>, string: WidgetString): String {
        val name = R.string::class.java.fields.first { it.getInt(null) == string.id }.name
        return String.format(Locale.US, strings.getValue(name), *string.args.toTypedArray())
    }

    private fun strings(folder: String): Map<String, String> {
        val nodes = DocumentBuilderFactory.newInstance().newDocumentBuilder()
            .parse(File("src/main/res/$folder/strings.xml")).getElementsByTagName("string")
        return (0 until nodes.length).associate {
            val element = nodes.item(it) as Element
            element.getAttribute("name") to element.textContent
        }
    }
}
