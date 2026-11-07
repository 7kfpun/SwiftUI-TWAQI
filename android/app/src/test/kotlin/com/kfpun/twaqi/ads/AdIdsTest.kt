package com.kfpun.twaqi.ads

import com.kfpun.twaqi.BuildConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * FOX-61: debug builds serve only Google's test ads, whatever secrets.properties holds, so a debug
 * build on a real phone never shows a real ad. AGP unit-tests only the debug build type; release
 * builds are guarded at packaging time by `verifyReleaseAdIds` (app/build.gradle.kts), which
 * refuses Google's test ids, the example placeholders and malformed ids.
 */
class AdIdsTest {
    @Test
    fun debugBuildsUseGoogleTestIds() {
        assertTrue("these tests run against the debug build", BuildConfig.DEBUG)
        assertEquals(TEST_APP_ID, BuildConfig.ADMOB_APP_ID)
        AdPlacement.entries.forEach { assertEquals(it.name, TEST_BANNER_UNIT_ID, it.adUnitId) }
    }

    private companion object {
        /** Google's published test ids: developers.google.com/admob/android/test-ads */
        const val TEST_APP_ID = "ca-app-pub-3940256099942544~3347511713"
        const val TEST_BANNER_UNIT_ID = "ca-app-pub-3940256099942544/6300978111"
    }
}
