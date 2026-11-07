package com.kfpun.twaqi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Guards the Play listing rules from FOX-51: same package id as the old app, versionCode above it. */
class AppIdentityTest {
    @Test
    fun applicationIdUpdatesTheExistingPlayListing() {
        assertEquals("com.kfpun.twaqi", BuildConfig.APPLICATION_ID)
    }

    @Test
    fun versionCodeStaysAboveEveryCodeTheOldAppShipped() {
        assertTrue(
            "versionCode ${BuildConfig.VERSION_CODE} must be at least 3000000",
            BuildConfig.VERSION_CODE >= 3_000_000
        )
    }

    @Test
    fun versionNameIsAboveTheOldApp() {
        val major = BuildConfig.VERSION_NAME.substringBefore('.').toInt()
        assertTrue("versionName ${BuildConfig.VERSION_NAME} must be 2.x or later", major >= 2)
    }
}
