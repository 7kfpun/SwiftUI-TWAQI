package com.kfpun.twaqi.ui.adaptive

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

/**
 * FOX-119: a flip phone's cover screen (about 376 x 391 dp) and split screen only run apps that
 * resize; a minimum size, a fixed orientation or an aspect ratio limit would hide or letterbox the app.
 */
class ResizeableManifestTest {
    private val manifest = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
        .newDocumentBuilder().parse(File("src/main/AndroidManifest.xml"))

    private fun tags(name: String): List<Element> =
        manifest.getElementsByTagName(name).let { nodes -> (0 until nodes.length).map { nodes.item(it) as Element } }

    @Test
    fun appIsResizeable() {
        assertEquals("true", tags("application").single().getAttributeNS(ANDROID, "resizeableActivity"))
        tags("activity").forEach { activity ->
            val name = activity.getAttributeNS(ANDROID, "name")
            assertTrue(name, activity.getAttributeNS(ANDROID, "resizeableActivity") != "false")
            assertTrue(name, activity.getAttributeNS(ANDROID, "screenOrientation").isEmpty())
            assertTrue(name, activity.getAttributeNS(ANDROID, "maxAspectRatio").isEmpty())
            assertTrue(name, activity.getAttributeNS(ANDROID, "minAspectRatio").isEmpty())
        }
    }

    @Test
    fun noMinimumWindowSize() {
        tags("layout").forEach { layout ->
            assertTrue(layout.getAttributeNS(ANDROID, "minWidth").isEmpty())
            assertTrue(layout.getAttributeNS(ANDROID, "minHeight").isEmpty())
        }
    }

    private companion object {
        const val ANDROID = "http://schemas.android.com/apk/res/android"
    }
}
