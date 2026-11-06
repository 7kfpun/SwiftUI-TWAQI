package com.kfpun.twaqi.ui.station.share

import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.model.Station
import com.kfpun.twaqi.data.places.TaiwanPlaceNames
import java.io.File
import java.nio.file.Files
import java.time.Duration
import java.time.Instant
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

/** Port of iOS `ShareCardTests` (FOX-73), plus Android's file names and storage permission. */
class ShareCardTest {
    // region Shapes

    /** 4:5 for a feed post, 9:16 for a story, 1:1 for a chat, all 1080 px wide. */
    @Test
    fun shapePixelSizes() {
        assertEquals(1080 to 1350, ShareCardShape.FEED.pixelWidth to ShareCardShape.FEED.pixelHeight)
        assertEquals(1080 to 1920, ShareCardShape.STORY.pixelWidth to ShareCardShape.STORY.pixelHeight)
        assertEquals(1080 to 1080, ShareCardShape.SQUARE.pixelWidth to ShareCardShape.SQUARE.pixelHeight)
    }

    /** The layout sizes in dp, as iOS's points, at 3 px per dp. */
    @Test
    fun shapeLayoutSizes() {
        assertEquals(
            listOf(360 to 450, 360 to 640, 360 to 360),
            ShareCardShape.entries.map { it.widthDp to it.heightDp }
        )
        assertEquals(3f, ShareCardShape.RENDER_SCALE)
    }

    /** The picker's order, and the values analytics and the stored choice use. */
    @Test
    fun shapeOrderAndRawValues() {
        assertEquals(listOf(ShareCardShape.FEED, ShareCardShape.STORY, ShareCardShape.SQUARE), ShareCardShape.entries)
        assertEquals(listOf("4x5", "9x16", "1x1"), ShareCardShape.entries.map { it.raw })
        assertEquals("shareCardShape", ShareCardShape.PREFERENCE_KEY)
    }

    @Test
    fun savedShapeDefaultsToFeed() {
        assertEquals(ShareCardShape.FEED, ShareCardShape.fromRaw(null))
        assertEquals(ShareCardShape.FEED, ShareCardShape.fromRaw("16x9"))
        assertEquals(ShareCardShape.STORY, ShareCardShape.fromRaw("9x16"))
        assertEquals(ShareCardShape.SQUARE, ShareCardShape.fromRaw("1x1"))
    }

    /** The square drops the locality and the guidance; the story has the most room. */
    @Test
    fun metricsPerShape() {
        val feed = ShareCardMetrics.of(ShareCardShape.FEED)
        val story = ShareCardMetrics.of(ShareCardShape.STORY)
        val square = ShareCardMetrics.of(ShareCardShape.SQUARE)
        assertTrue(feed.showsLocality && story.showsLocality)
        assertFalse(square.showsLocality)
        assertEquals(listOf(2, 4, 0), listOf(feed, story, square).map { it.guidanceLines })
        assertEquals(listOf(84f, 112f, 64f), listOf(feed, story, square).map { it.numberSize.value })
    }

    @Test
    fun readingsAreThePm25Pm10AndO3OfTheReading() {
        assertNull(ShareCardContent.readings(null))
        val pollutant = Pollutant(
            stationId = 12, code = "KL", lat = 25.1, lon = 121.7, aqi = 54.0, pm25 = 18.0, pm10 = 40.0,
            no2 = 9.0, so2 = 1.0, co = 0.3, o3 = 31.5, windDirection = 0.0, windSpeed = 0.0,
            publishTime = "2026-08-07T22:00:00", name = "Keelung", nameLocal = "基隆"
        )
        assertEquals(
            listOf(AirIndexType.PM25 to 18.0, AirIndexType.PM10 to 40.0, AirIndexType.O3 to 31.5),
            ShareCardContent.readings(pollutant)
        )
    }

    /**
     * #77 review: the card's locality is the station page's. FOX-114: the township's English comes
     * from the place-name table, the county from the API; neither is machine-translated.
     */
    @Test
    fun localityNamesTheTownshipAsTheStationPageDoes() {
        val pollutant = Pollutant(
            stationId = 12, code = "KL", lat = 25.1, lon = 121.7, aqi = 54.0, pm25 = 18.0, pm10 = 40.0,
            no2 = 9.0, so2 = 1.0, co = 0.3, o3 = 31.5, windDirection = 0.0, windSpeed = 0.0,
            publishTime = "2026-08-07T22:00:00", name = "Keelung", nameLocal = "基隆",
            county = "Keelung City", countyLocal = "基隆市", township = "信義區"
        )
        val places = TaiwanPlaceNames.parse(File("src/main/assets/place_names/taiwan_place_names.json").readText())

        assertEquals(
            "Xinyi District, Keelung City",
            ShareCardContent.locality(pollutant, null, chinese = false, places)
        )
        assertEquals("信義區, 基隆市", ShareCardContent.locality(pollutant, null, chinese = true, places))
        // Without the table, the township shows as written.
        assertEquals("信義區, Keelung City", ShareCardContent.locality(pollutant, null, chinese = false))
        // Without a reading, the station's own locality.
        val station = Station(
            id = 12, countryId = 1, countryCode = "TW", code = "KL", lat = 25.1, lon = 121.7, imageUrl = null,
            name = "Keelung", nameLocal = "基隆", county = "Keelung City", countyLocal = "基隆市", township = "信義區"
        )
        assertEquals("Xinyi District, Keelung City", ShareCardContent.locality(null, station, chinese = false, places))
        assertNull(ShareCardContent.locality(null, null, chinese = false, places))
    }

    // endregion

    // region Files and permission

    /** Station, shape and the time in Taiwan, so no two cards share a name. */
    @Test
    fun fileNaming() {
        val now = Instant.parse("2026-08-07T14:05:12Z")
        assertEquals("TaiwanAir-12-4x5-20260807-220512.png", ShareCardSharing.fileName(12, ShareCardShape.FEED, now))
        assertEquals("TaiwanAir-12-9x16-20260807-220512.png", ShareCardSharing.fileName(12, ShareCardShape.STORY, now))
        assertEquals(
            "TaiwanAir-301-1x1-20260807-220512.png",
            ShareCardSharing.fileName(301, ShareCardShape.SQUARE, now)
        )
        assertNotEquals(
            ShareCardSharing.fileName(12, ShareCardShape.FEED, now),
            ShareCardSharing.fileName(12, ShareCardShape.FEED, now.plusSeconds(1))
        )
    }

    /** Taiwan's date, not UTC's: 01:30 in Taipei is still the previous day in UTC. */
    @Test
    fun fileNamingUsesTaiwanTime() {
        val now = Instant.parse("2026-08-07T17:30:00Z")
        assertEquals("TaiwanAir-1-4x5-20260808-013000.png", ShareCardSharing.fileName(1, ShareCardShape.FEED, now))
    }

    @Test
    fun fileNamesAreSafeForEveryShape() {
        ShareCardShape.entries.forEach {
            assertTrue(Regex("[A-Za-z0-9.-]+").matches(ShareCardSharing.fileName(9, it)))
        }
    }

    /** Android 8–9 need `WRITE_EXTERNAL_STORAGE` at runtime; 10+ (API 29) need nothing. */
    @Test
    fun writePermissionOnlyBelowAndroid10() {
        (26..28).forEach { assertTrue("API $it", ShareCardSharing.needsWritePermission(it)) }
        (29..36).forEach { assertFalse("API $it", ShareCardSharing.needsWritePermission(it)) }
    }

    /** Declared only up to API 28, so Android 10+ never lists or asks for it. */
    @Test
    fun manifestDeclaresWritePermissionUpToApi28() {
        val manifest = xml(File("src/main/AndroidManifest.xml"))
        val permissions = manifest.getElementsByTagName("uses-permission").elements()
            .filter { it.getAttributeNS(ANDROID, "name") == "android.permission.WRITE_EXTERNAL_STORAGE" }
        assertEquals(1, permissions.size)
        assertEquals("28", permissions.single().getAttributeNS(ANDROID, "maxSdkVersion"))
        assertTrue(
            manifest.getElementsByTagName("uses-permission").elements().none {
                it.getAttributeNS(ANDROID, "name") == "android.permission.READ_EXTERNAL_STORAGE"
            }
        )
    }

    /** The FileProvider exposes the share cache and nothing else. */
    @Test
    fun fileProviderExposesOnlyTheShareCache() {
        val paths = xml(File("src/main/res/xml/share_card_paths.xml")).documentElement.childNodes.let { nodes ->
            (0 until nodes.length).mapNotNull { nodes.item(it) as? Element }
        }
        assertEquals(listOf("cache-path"), paths.map { it.tagName })
        assertEquals("${ShareCardSharing.CACHE_DIRECTORY}/", paths.single().getAttribute("path"))
    }

    @Test
    fun pruneRemovesOnlyOldCards() {
        val directory = Files.createTempDirectory("share-cards").toFile()
        val now = Instant.parse("2026-08-07T14:00:00Z")
        val old = File(directory, "old.png").apply {
            writeText("x")
            setLastModified(now.minus(ShareCardSharing.cacheMaxAge).minus(Duration.ofMinutes(1)).toEpochMilli())
        }
        val recent = File(directory, "recent.png").apply {
            writeText("x")
            setLastModified(now.minus(Duration.ofHours(1)).toEpochMilli())
        }
        assertEquals(listOf(old), ShareCardSharing.prune(directory, now))
        assertFalse(old.exists())
        assertTrue(recent.exists())
        directory.deleteRecursively()
    }

    // endregion

    // region Analytics

    @Test
    fun analyticsParameters() {
        val opened = ShareCardSharing.parameters(54.7, ShareCardShape.STORY, stationId = 12)
        assertEquals(mapOf<String, Any>("stationId" to 12, "aqi" to 54, "shape" to "9x16"), opened)

        mapOf(ShareCardAction.SHARE to "share", ShareCardAction.SAVE to "save", ShareCardAction.CANCEL to "cancel")
            .forEach { (action, value) ->
                val parameters = ShareCardSharing.parameters(54.0, ShareCardShape.SQUARE, 12, action)
                assertEquals(value, parameters["action"])
                assertEquals("1x1", parameters["shape"])
            }
    }

    // endregion

    // region Session (cancel)

    @Test
    fun closingUntouchedSessionCancelsOnce() {
        val session = ShareCardSession()
        session.appeared()
        assertTrue(session.disappeared())
        assertFalse(session.disappeared())
    }

    @Test
    fun shareThenFailedSaveIsNotACancel() {
        val session = ShareCardSession()
        session.appeared()
        session.shared()
        session.saveStarted()
        assertFalse(session.saveFinished(saved = false))
        assertFalse(session.disappeared())
        assertTrue(session.isCommitted)
    }

    @Test
    fun failedSaveAfterSuccessfulSaveIsNotACancel() {
        val session = ShareCardSession()
        session.appeared()
        session.saveStarted()
        session.saveStarted()
        assertFalse(session.saveFinished(saved = true))
        assertFalse(session.saveFinished(saved = false))
        assertFalse(session.disappeared())
    }

    @Test
    fun deniedSaveThenCloseCancels() {
        val session = ShareCardSession()
        session.appeared()
        session.saveStarted()
        assertFalse(session.saveFinished(saved = false))
        assertTrue(session.disappeared())
    }

    @Test
    fun closeDuringSaveThatFailsCancelsFromTheSave() {
        val session = ShareCardSession()
        session.appeared()
        session.saveStarted()
        assertFalse(session.disappeared())
        assertTrue(session.saveFinished(saved = false))
    }

    @Test
    fun closeDuringSaveThatSucceedsIsNotACancel() {
        val session = ShareCardSession()
        session.appeared()
        session.saveStarted()
        assertFalse(session.disappeared())
        assertFalse(session.saveFinished(saved = true))
    }

    @Test
    fun reappearingAfterDisappearDoesNotCancelEarly() {
        val session = ShareCardSession()
        session.appeared()
        session.saveStarted()
        assertFalse(session.disappeared())
        session.appeared()
        assertFalse(session.saveFinished(saved = false))
        assertTrue(session.disappeared())
    }

    /** Restored after a rotation: a share before it still counts, and a cancel isn't logged twice. */
    @Test
    fun restoredSessionKeepsItsOutcome() {
        val committed = ShareCardSession(isCommitted = true)
        committed.appeared()
        assertFalse(committed.disappeared())

        val cancelled = ShareCardSession(didCancel = true)
        cancelled.appeared()
        assertFalse(cancelled.disappeared())
    }

    // endregion

    // region Message

    @Test
    fun messageInEnglish() {
        val strings = strings("values")
        val message = ShareCardSharing.message(
            strings.getValue("share_message"),
            "Keelung",
            54.0,
            strings.getValue("airstatus_moderate")
        )
        assertEquals("Keelung: AQI 54, Moderate — via Taiwan Air", message)
        assertEquals(
            "Keelung: AQI 54, Moderate — via Taiwan Air\nhttps://play.google.com/store/apps/details?id=com.kfpun.twaqi",
            ShareCardSharing.shareText(message, "https://play.google.com/store/apps/details?id=com.kfpun.twaqi")
        )
    }

    @Test
    fun messageInTraditionalChinese() {
        val strings = strings("values-zh-rTW")
        assertEquals(
            "基隆：AQI 120，對敏感族群不健康 — 來自 Taiwan Air",
            ShareCardSharing.message(
                strings.getValue("share_message"),
                "基隆",
                120.6,
                strings.getValue("airstatus_unhealthyforsensitivegroup")
            )
        )
    }

    /** Android's card points at Google Play, not the App Store. */
    @Test
    fun brandLinePointsAtGooglePlay() {
        assertEquals("Get Taiwan Air on Google Play", strings("values").getValue("share_download"))
        assertEquals("在 Google Play 下載 Taiwan Air", strings("values-zh-rTW").getValue("share_download"))
    }

    // endregion

    private fun xml(file: File) = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
        .newDocumentBuilder().parse(file)

    private fun org.w3c.dom.NodeList.elements(): List<Element> = (0 until length).map { item(it) as Element }

    /** Unit tests run from android/app. Android unescapes `\'`; these strings have none. */
    private fun strings(folder: String): Map<String, String> =
        xml(File("src/main/res/$folder/strings.xml")).getElementsByTagName("string").elements()
            .associate { it.getAttribute("name") to it.textContent }

    private companion object {
        const val ANDROID = "http://schemas.android.com/apk/res/android"
    }
}
