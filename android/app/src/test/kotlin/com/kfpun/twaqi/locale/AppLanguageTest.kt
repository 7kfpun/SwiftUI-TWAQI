package com.kfpun.twaqi.locale

import org.junit.Assert.assertEquals
import org.junit.Test

/** Mirrors iOS `AppLanguageTests` (persistence values, unknown values) plus the Android 13+ split. */
class AppLanguageTest {
    @Test
    fun storedIdsMatchIos() {
        assertEquals(AppLanguage.TRADITIONAL_CHINESE, AppLanguage.fromId("zh-Hant"))
        assertEquals(AppLanguage.ENGLISH, AppLanguage.fromId("en"))
        assertEquals(listOf("system", "zh-Hant", "en"), AppLanguage.entries.map { it.id })
    }

    @Test
    fun nothingOrUnknownStoredFallsBackToSystem() {
        assertEquals(AppLanguage.SYSTEM, AppLanguage.fromId(null))
        assertEquals(AppLanguage.SYSTEM, AppLanguage.fromId("klingon"))
        // "system" is never stored (choosing it removes the key), but reads back the same.
        assertEquals(AppLanguage.SYSTEM, AppLanguage.fromId("system"))
    }

    @Test
    fun systemFollowsThePhoneAndTheOthersPickTheShippedResources() {
        assertEquals(null, AppLanguage.SYSTEM.localeTag)
        assertEquals("zh-TW", AppLanguage.TRADITIONAL_CHINESE.localeTag)
        assertEquals("en", AppLanguage.ENGLISH.localeTag)
    }

    @Test
    fun localeTagsMapToTheirLanguage() {
        assertEquals(AppLanguage.TRADITIONAL_CHINESE, AppLanguage.fromLocaleTag("zh-TW"))
        assertEquals(AppLanguage.TRADITIONAL_CHINESE, AppLanguage.fromLocaleTag("zh-Hant-TW"))
        assertEquals(AppLanguage.TRADITIONAL_CHINESE, AppLanguage.fromLocaleTag("zh_HK"))
        assertEquals(AppLanguage.ENGLISH, AppLanguage.fromLocaleTag("en"))
        assertEquals(AppLanguage.ENGLISH, AppLanguage.fromLocaleTag("en-GB"))
        assertEquals(AppLanguage.SYSTEM, AppLanguage.fromLocaleTag("ja-JP"))
        assertEquals(AppLanguage.SYSTEM, AppLanguage.fromLocaleTag(""))
        assertEquals(AppLanguage.SYSTEM, AppLanguage.fromLocaleTag(null))
    }

    @Test
    fun android13AndLaterReadTheSystemPerAppLocale() {
        // The per-app locale can be changed in the phone's Settings, so it wins over the stored id.
        assertEquals(AppLanguage.ENGLISH, AppLocale.resolve(33, "en", storedId = "zh-Hant"))
        assertEquals(AppLanguage.TRADITIONAL_CHINESE, AppLocale.resolve(36, "zh-TW,en", storedId = null))
        // Cleared in Settings: follow the phone, even if a choice is still stored.
        assertEquals(AppLanguage.SYSTEM, AppLocale.resolve(34, "", storedId = "en"))
        assertEquals(AppLanguage.SYSTEM, AppLocale.resolve(34, null, storedId = "en"))
    }

    @Test
    fun olderVersionsReadTheStoredChoice() {
        // A widget or notification in a cold process has no AppCompat state; the stored id is there.
        assertEquals(AppLanguage.TRADITIONAL_CHINESE, AppLocale.resolve(32, null, storedId = "zh-Hant"))
        assertEquals(AppLanguage.ENGLISH, AppLocale.resolve(26, null, storedId = "en"))
        assertEquals(AppLanguage.SYSTEM, AppLocale.resolve(26, null, storedId = null))
    }

    @Test
    fun storageKeyMatchesIos() {
        assertEquals("appLanguage", AppLocale.KEY)
    }
}
