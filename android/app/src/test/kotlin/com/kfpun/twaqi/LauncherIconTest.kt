package com.kfpun.twaqi

import java.io.DataInputStream
import java.io.File
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * FOX-108: the launcher and Play icon are the iOS icon, drawn by
 * tools/DrawAndroidAppIcon.swift. Guards the wiring the generator doesn't:
 * both modules use the adaptive icon with all three layers, the watch gets the
 * phone's art, and the Play icon is 512x512 in every listing.
 */
class LauncherIconTest {
    private val layers = listOf("ic_launcher_background", "ic_launcher_foreground", "ic_launcher_monochrome")

    @Test
    fun manifestsUseTheAdaptiveIcon() {
        for (module in listOf(".", "../wear")) {
            val manifest = File("$module/src/main/AndroidManifest.xml").readText()
            assertTrue(module, manifest.contains("android:icon=\"@mipmap/ic_launcher\""))
            assertTrue(module, manifest.contains("android:roundIcon=\"@mipmap/ic_launcher_round\""))
        }
    }

    @Test
    fun adaptiveIconsHaveAllThreeLayers() {
        for (module in listOf(".", "../wear")) {
            for (icon in listOf("ic_launcher", "ic_launcher_round")) {
                val xml = File("$module/src/main/res/mipmap-anydpi/$icon.xml").readText()
                assertTrue(xml.contains("<background android:drawable=\"@drawable/ic_launcher_background\" />"))
                assertTrue(xml.contains("<foreground android:drawable=\"@drawable/ic_launcher_foreground\" />"))
                // Themed icons (Android 13+) need their own one-colour layer, not the full-colour art.
                assertTrue(xml.contains("<monochrome android:drawable=\"@drawable/ic_launcher_monochrome\" />"))
            }
        }
    }

    @Test
    fun watchUsesThePhonesArt() {
        for (layer in layers) {
            assertArrayEquals(
                layer,
                File("src/main/res/drawable/$layer.xml").readBytes(),
                File("../wear/src/main/res/drawable/$layer.xml").readBytes()
            )
        }
    }

    @Test
    fun playIconIs512SquareInEveryListing() {
        val listings = File("src/main/play/listings").listFiles { file -> file.isDirectory }.orEmpty()
        assertTrue(listings.map { it.name }.containsAll(listOf("en-US", "zh-TW")))
        for (listing in listings) {
            DataInputStream(File(listing, "graphics/icon/1.png").inputStream()).use { png ->
                val signature = ByteArray(8).also { png.readFully(it) }
                assertArrayEquals(byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10), signature)
                png.readInt() // IHDR length
                assertEquals(0x49484452, png.readInt()) // "IHDR"
                assertEquals(listing.name, 512, png.readInt())
                assertEquals(listing.name, 512, png.readInt())
            }
        }
    }
}
