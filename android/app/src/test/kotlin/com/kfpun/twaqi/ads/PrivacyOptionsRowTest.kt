package com.kfpun.twaqi.ads

import com.google.android.ump.ConsentInformation.PrivacyOptionsRequirementStatus
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** FOX-116: Help's "Privacy settings" row shows only where UMP requires a privacy options entry point. */
class PrivacyOptionsRowTest {
    @Test
    fun showsOnlyWhenRequired() {
        assertTrue(AdConsent.showsPrivacyOptions(PrivacyOptionsRequirementStatus.REQUIRED))
        assertFalse(AdConsent.showsPrivacyOptions(PrivacyOptionsRequirementStatus.NOT_REQUIRED))
        // UMP hasn't answered yet (offline, or a Pro user who never asked).
        assertFalse(AdConsent.showsPrivacyOptions(PrivacyOptionsRequirementStatus.UNKNOWN))
        assertFalse(AdConsent.showsPrivacyOptions(null))
    }

    @Test
    fun hiddenUntilUmpAnswers() {
        assertFalse(AdConsent.privacyOptionsRequired.value)
    }

    @Test
    fun bothLanguagesNameTheRow() {
        assertEquals("Privacy settings", string("values"))
        assertEquals("廣告隱私設定", string("values-zh-rTW"))
    }

    private fun string(folder: String): String? = Regex("""<string name="help_privacy_settings">([^<]*)</string>""")
        .find(File("src/main/res/$folder/strings.xml").readText())?.groupValues?.get(1)
}
