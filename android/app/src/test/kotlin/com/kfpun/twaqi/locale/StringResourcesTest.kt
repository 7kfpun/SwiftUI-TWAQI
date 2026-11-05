package com.kfpun.twaqi.locale

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

/**
 * Every string ships in both languages (FOX-56), with the same placeholders, and the
 * languages offered to the system are the ones the app has resources for.
 * Unit tests run from the module directory (android/app).
 */
class StringResourcesTest {
    private val res = File("src/main/res")
    private val english = strings("values")
    private val chinese = strings("values-zh-rTW")

    @Test
    fun bothLanguagesHaveTheSameStrings() {
        val missingInChinese = english.keys - chinese.keys
        val missingInEnglish = chinese.keys - english.keys
        assertTrue("Missing in values-zh-rTW/strings.xml: $missingInChinese", missingInChinese.isEmpty())
        assertTrue("Missing in values/strings.xml: $missingInEnglish", missingInEnglish.isEmpty())
    }

    @Test
    fun noStringIsEmpty() {
        val empty = (english.filterValues { it.isBlank() }.keys.map { "values/$it" }) +
            chinese.filterValues { it.isBlank() }.keys.map { "values-zh-rTW/$it" }
        assertTrue("Empty strings: $empty", empty.isEmpty())
    }

    @Test
    fun translationsKeepThePlaceholders() {
        val mismatched = english.keys.filter {
            placeholders(english.getValue(it)) != placeholders(chinese[it].orEmpty())
        }
        assertTrue("Placeholders differ between en and zh-rTW: $mismatched", mismatched.isEmpty())
    }

    @Test
    fun onlyEnglishAndTraditionalChineseShipStrings() {
        val folders = res.listFiles { file -> File(file, "strings.xml").isFile }.orEmpty().map { it.name }.sorted()
        assertEquals(listOf("values", "values-zh-rTW"), folders)
    }

    @Test
    fun localeConfigListsEveryAppLanguage() {
        val config = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            .newDocumentBuilder().parse(File(res, "xml/locales_config.xml"))
        val locales = config.getElementsByTagName("locale").let { nodes ->
            (0 until nodes.length).map {
                (nodes.item(it) as Element).getAttributeNS("http://schemas.android.com/apk/res/android", "name")
            }
        }
        assertEquals(AppLanguage.entries.mapNotNull { it.localeTag }.sorted(), locales.sorted())
    }

    private fun strings(folder: String): Map<String, String> {
        val file = File(res, "$folder/strings.xml")
        assertTrue("$file not found (working directory ${File("").absolutePath})", file.isFile)
        val nodes = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file).getElementsByTagName("string")
        return (0 until nodes.length).associate {
            val element = nodes.item(it) as Element
            element.getAttribute("name") to element.textContent
        }
    }

    private fun placeholders(text: String): List<String> =
        Regex("""%(\d+\$)?[sd]""").findAll(text).map { it.value }.sorted().toList()
}
