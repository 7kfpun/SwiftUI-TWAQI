package com.kfpun.twaqi.watch

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

/**
 * The Wear OS app shares the phone's Play listing and Data Layer (FOX-62): same application id,
 * its own versionCode range (android/README.md), and every string in both languages.
 * Unit tests run from the module directory (android/wear).
 */
class WearIdentityTest {
    @Test
    fun applicationIdMatchesThePhoneApp() {
        assertEquals("com.kfpun.twaqi", BuildConfig.APPLICATION_ID)
    }

    @Test
    fun versionCodeStaysInTheWearRange() {
        assertTrue(
            "Wear OS versionCode ${BuildConfig.VERSION_CODE} must be in 203000000..299999999",
            BuildConfig.VERSION_CODE in 203_000_000..299_999_999
        )
    }

    @Test
    fun bothLanguagesHaveTheSameStrings() {
        val english = strings("values")
        val chinese = strings("values-zh-rTW")
        assertEquals(emptySet<String>(), english.keys - chinese.keys)
        assertEquals(emptySet<String>(), chinese.keys - english.keys)
        val placeholders = Regex("%\\d\\$[sd]")
        english.forEach { (key, value) ->
            assertEquals(
                key,
                placeholders.findAll(value).map {
                    it.value
                }.toList(),
                placeholders.findAll(chinese.getValue(key)).map { it.value }.toList()
            )
        }
    }

    private fun strings(folder: String): Map<String, String> {
        val document = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(
            File("src/main/res/$folder/strings.xml")
        )
        val nodes = document.getElementsByTagName("string")
        return (0 until nodes.length).map { nodes.item(it) as Element }
            .filter { it.getAttribute("translatable") != "false" }
            .associate { it.getAttribute("name") to it.textContent }
    }
}
