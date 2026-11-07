package com.kfpun.twaqi.watch.data

import org.junit.Assert.assertEquals
import org.junit.Test

/** Pro on the watch is the phone's (FOX-58), with a developer override only in debug builds. */
class WatchProTest {
    @Test
    fun followsThePhone() {
        assertEquals(true, WatchPro.resolve(phoneSaysPro = true, overrideId = null, overrideAvailable = true))
        assertEquals(false, WatchPro.resolve(phoneSaysPro = false, overrideId = "phone", overrideAvailable = true))
    }

    @Test
    fun theOverrideWinsOnlyWhereItIsAvailable() {
        assertEquals(true, WatchPro.resolve(phoneSaysPro = false, overrideId = "forcePro", overrideAvailable = true))
        assertEquals(false, WatchPro.resolve(phoneSaysPro = true, overrideId = "forceFree", overrideAvailable = true))
        assertEquals(false, WatchPro.resolve(phoneSaysPro = false, overrideId = "forcePro", overrideAvailable = false))
    }

    @Test
    fun relayedLanguagesMapToTheWatchLocales() {
        assertEquals("zh-TW", WatchLocale.localeTag("zh-Hant"))
        assertEquals("en", WatchLocale.localeTag("en"))
        assertEquals(null, WatchLocale.localeTag("system"))
    }
}
