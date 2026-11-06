package com.kfpun.twaqi.translation

import com.kfpun.twaqi.data.cache.CacheStore
import com.kfpun.twaqi.data.cache.OfflineCacheRetention
import com.kfpun.twaqi.data.model.AqiForecast
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.model.Station
import com.kfpun.twaqi.data.places.TaiwanPlaceNames
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Records what it was asked and answers from [dictionary]; never loads ML Kit. */
private class FakeTranslator(var dictionary: Map<String, String> = emptyMap(), var failure: Exception? = null) :
    Translator {
    val requests = mutableListOf<List<String>>()

    override suspend fun translate(texts: List<String>, target: String): Map<String, String> {
        requests += texts
        failure?.let { throw it }
        return texts.mapNotNull { text -> dictionary[text]?.let { text to it } }.toMap()
    }
}

class OnDeviceTranslationTest {
    private lateinit var root: File
    private var now = Instant.parse("2026-11-06T06:00:00Z")

    @Before
    fun setUp() {
        root = Files.createTempDirectory("translations").toFile()
    }

    @After
    fun tearDown() {
        root.deleteRecursively()
    }

    private fun disk() = TranslationDiskCache(CacheStore(root) { now }, now = { now }, io = Dispatchers.Unconfined)

    private fun station(township: String? = "板橋區", address: String? = "新北市板橋區文化路一段25號") = Station(
        id = 1,
        countryId = 1,
        countryCode = "TW",
        code = "banqiao",
        lat = 25.0,
        lon = 121.4,
        imageUrl = null,
        name = "Banqiao",
        nameLocal = "板橋",
        address = address,
        area = "North",
        areaLocal = "北部空品區",
        county = "New Taipei City",
        countyLocal = "新北市",
        township = township
    )

    private fun pollutant(township: String? = "板橋區", address: String? = "新北市板橋區文化路一段25號") = Pollutant(
        stationId = 1,
        code = "banqiao",
        lat = 25.0,
        lon = 121.4,
        aqi = 50.0,
        pm25 = 10.0,
        pm10 = 20.0,
        no2 = 5.0,
        so2 = 1.0,
        co = 0.3,
        o3 = 30.0,
        windDirection = 0.0,
        windSpeed = 0.0,
        publishTime = "2026-11-06 14:00:00",
        name = "Banqiao",
        nameLocal = "板橋",
        address = address,
        area = "North",
        areaLocal = "北部空品區",
        county = "New Taipei City",
        countyLocal = "新北市",
        township = township
    )

    // Which fields are translated, and which never are.

    /**
     * FOX-114: ML Kit garbled place names (新店區 "New store area", 八德路四段 "paragraph 4, Baide
     * Road"), so no screen that shows a station's township, county or street address sends text
     * to the translator: only the area forecast does. The station page, the welcome flow's card,
     * the favourites and the share card name places from `TaiwanPlaceNames`.
     */
    @Test
    fun placeNamesAndAddressesNeverGoToTheTranslator() {
        val sources = File("src/main/kotlin/com/kfpun/twaqi").walkTopDown().filter { it.isFile }.toList()
        assertTrue("sources not found from ${File(".").absolutePath}", sources.isNotEmpty())
        val senders = sources.filter { "TranslatesOnDevice(" in it.readText() }.map { it.name }.toSet()
        // TranslationCompose.kt defines it; AreaForecastCard.kt sends the forecast text.
        assertEquals(setOf("TranslationCompose.kt", "AreaForecastCard.kt"), senders)
        sources.filter { it.name == "AreaForecastCard.kt" }.forEach { file ->
            listOf("township", "address", "displayLocality").forEach {
                assertFalse("${file.name} mentions $it", it in file.readText())
            }
        }
        listOf("ui/station", "ui/favourites", "onboarding").forEach { dir ->
            File("src/main/kotlin/com/kfpun/twaqi/$dir").walkTopDown().filter { it.isFile }.forEach { file ->
                listOf("OnDeviceTranslation", "rememberShownTranslations", "translations::display").forEach {
                    assertFalse("${file.path} uses $it", it in file.readText())
                }
            }
        }
    }

    @Test
    fun stationPlacesAreNamedFromTheTableNotTheTranslationCache() = runTest {
        // A cache from a FOX-98 build may still hold ML Kit's garbled names: they never show.
        val translator = FakeTranslator()
        val translation = OnDeviceTranslation(translator)
        translation.store("Banqiao area", "板橋區", "en")
        translation.store("No. 25, Section 1, Culture Road", "新北市板橋區文化路一段25號", "en")
        val places = TaiwanPlaceNames.parse(
            File("src/main/assets/place_names/taiwan_place_names.json").readText()
        )

        assertEquals("Banqiao District, New Taipei City", pollutant().displayLocality(chinese = false, places))
        assertEquals("Banqiao District, New Taipei City", station().displayLocality(chinese = false, places))
        assertEquals("板橋區, 新北市", pollutant().displayLocality(chinese = true, places))
        assertTrue(translator.requests.isEmpty())
    }

    @Test
    fun cwaWeatherTextIsNeverTranslated() {
        // FOX-93's weather card shows CWA's text in Chinese only: nothing under it goes on device.
        val sources = listOf("ui/station/weather", "data/weather").flatMap { dir ->
            File("src/main/kotlin/com/kfpun/twaqi/$dir").walkTopDown().filter { it.isFile }.toList()
        }
        assertTrue("weather sources not found from ${File(".").absolutePath}", sources.isNotEmpty())
        sources.forEach { file ->
            val text = file.readText()
            listOf("OnDeviceTranslation", "TranslatesOnDevice", "rememberShownTranslations").forEach {
                assertFalse("${file.name} uses $it", it in text)
            }
        }
    }

    @Test
    fun onlyTextWithChineseNeedsTranslation() {
        assertTrue(OnDeviceTranslation.needsTranslation("今日北部普通。"))
        assertFalse(OnDeviceTranslation.needsTranslation("smoke test FOX-8"))
        assertFalse(OnDeviceTranslation.needsTranslation(""))
        assertEquals(listOf("板橋區"), OnDeviceTranslation.translatable(listOf("板橋區", "Banqiao", "板橋區", "", "42-6")))
    }

    // The language switch.

    @Test
    fun targetIsEnglishOutsideChineseAndNoneInChinese() {
        assertNull(OnDeviceTranslation.target(chinese = true))
        assertEquals("en", OnDeviceTranslation.target(chinese = false))
    }

    @Test
    fun chineseShowsTheOriginalEvenWithATranslationCached() = runTest {
        val translator = FakeTranslator(mapOf("板橋區" to "Banqiao District"))
        val service = OnDeviceTranslation(translator)
        service.translate(listOf("板橋區"), OnDeviceTranslation.target(chinese = false))
        val cached: (String, String) -> String? = service::cached

        assertEquals("板橋區", OnDeviceTranslation.display("板橋區", OnDeviceTranslation.target(chinese = true), cached))
        assertEquals("Banqiao District", OnDeviceTranslation.display("板橋區", "en", cached))
    }

    @Test
    fun chineseNeverAsksTheTranslator() = runTest {
        val translator = FakeTranslator(mapOf("板橋區" to "Banqiao District"))
        OnDeviceTranslation(translator).translate(listOf("板橋區"), OnDeviceTranslation.target(chinese = true))
        assertTrue(translator.requests.isEmpty())
    }

    @Test
    fun clearingTheCacheDropsTranslations() {
        val service = OnDeviceTranslation(FakeTranslator())
        service.store("Banqiao District", "板橋區", "en")
        assertEquals("Banqiao District", service.cached("板橋區", "en"))
        service.clearCache()
        assertNull(service.cached("板橋區", "en"))
    }

    // The fallback chain: the Worker's English, then on device, then the original.

    @Test
    fun forecastPrefersTheWorkersTranslation() = runTest {
        val content = "今日北部普通。"
        val forecast = AqiForecast(
            area = "北部",
            forecastDate = "2026-11-06",
            content = content,
            contentI18n = mapOf("zh-Hant" to content, "en" to "North: moderate today.")
        )
        val service = OnDeviceTranslation(FakeTranslator(mapOf(content to "On device.")))
        service.translate(listOf(content), "en")

        val worker = forecast.translatedContent(OnDeviceTranslation.target(chinese = false))
        assertEquals("North: moderate today.", OnDeviceTranslation.forecastText(content, worker, "en", service::cached))
        // No Worker translation: the on-device one.
        assertEquals("On device.", OnDeviceTranslation.forecastText(content, null, "en", service::cached))
        // Neither: the original.
        assertEquals(content, OnDeviceTranslation.forecastText(content, null, "en") { _, _ -> null })
        // Chinese: the original, and no Worker lookup at all.
        assertNull(forecast.translatedContent(OnDeviceTranslation.target(chinese = true)))
        assertEquals(content, OnDeviceTranslation.forecastText(content, null, null, service::cached))
    }

    @Test
    fun noModelOrOfflineShowsTheOriginal() = runTest {
        // The translator answers nothing, as ML Kit does without the model.
        val translator = FakeTranslator()
        val service = OnDeviceTranslation(translator)
        service.translate(listOf("板橋區"), "en")
        assertEquals(listOf(listOf("板橋區")), translator.requests)
        assertEquals("板橋區", OnDeviceTranslation.display("板橋區", "en", service::cached))
    }

    @Test
    fun anErrorShowsTheOriginalAndIsRetriedLater() = runTest {
        val translator = FakeTranslator(mapOf("板橋區" to "Banqiao District"), failure = IOException("offline"))
        val service = OnDeviceTranslation(translator)
        service.translate(listOf("板橋區"), "en")
        assertEquals("板橋區", OnDeviceTranslation.display("板橋區", "en", service::cached))

        translator.failure = null
        service.translate(listOf("板橋區"), "en")
        assertEquals("Banqiao District", OnDeviceTranslation.display("板橋區", "en", service::cached))
    }

    @Test
    fun blankTranslationsAreIgnoredAndOthersTrimmed() = runTest {
        val service = OnDeviceTranslation(FakeTranslator(mapOf("板橋區" to "  ", "文化路" to " Wenhua Rd. \n")))
        service.translate(listOf("板橋區", "文化路"), "en")
        assertNull(service.cached("板橋區", "en"))
        assertEquals("Wenhua Rd.", service.cached("文化路", "en"))
    }

    // The cache.

    @Test
    fun cachedTextIsNotTranslatedAgain() = runTest {
        val translator = FakeTranslator(mapOf("板橋區" to "Banqiao District", "文化路" to "Wenhua Rd."))
        val service = OnDeviceTranslation(translator)
        service.translate(listOf("板橋區"), "en")
        service.translate(listOf("板橋區", "文化路", "Banqiao"), "en")
        assertEquals(listOf(listOf("板橋區"), listOf("文化路")), translator.requests)
    }

    @Test
    fun translationsSurviveARelaunchFromDisk() = runTest {
        OnDeviceTranslation(FakeTranslator(mapOf("板橋區" to "Banqiao District")), disk()).translate(listOf("板橋區"), "en")
        assertTrue(File(root, TranslationDiskCache.fileName("en")).isFile)

        val translator = FakeTranslator()
        val relaunched = OnDeviceTranslation(translator, disk())
        relaunched.translate(listOf("板橋區"), "en")
        assertEquals("Banqiao District", relaunched.cached("板橋區", "en"))
        assertTrue("nothing to translate again", translator.requests.isEmpty())
    }

    @Test
    fun diskEntriesExpireAfterAWeek() = runTest {
        val cache = disk()
        cache.add("en", mapOf("板橋區" to "Banqiao District"))
        now += Duration.ofDays(3)
        cache.add("en", mapOf("文化路" to "Wenhua Rd."))
        now += Duration.ofDays(5)
        // The file was written 5 days ago, but its first entry is 8 days old.
        assertEquals(mapOf("文化路" to "Wenhua Rd."), cache.load("en"))
    }

    @Test
    fun theDiskCacheLivesUnderTheOfflineCacheRootAndIsPurged() = runTest {
        disk().add("en", mapOf("板橋區" to "Banqiao District"))
        val file = File(root, TranslationDiskCache.fileName("en"))
        assertTrue(file.isFile)
        assertEquals(listOf(file), OfflineCacheRetention.purge(root, now + Duration.ofDays(8)))
    }

    @Test
    fun theDiskCacheKeepsTheNewestEntries() = runTest {
        val cache =
            TranslationDiskCache(CacheStore(root) { now }, now = { now }, maxEntries = 2, io = Dispatchers.Unconfined)
        cache.add("en", mapOf("一" to "One"))
        cache.add("en", mapOf("二" to "Two"))
        cache.add("en", mapOf("三" to "Three"))
        assertEquals(mapOf("三" to "Three", "二" to "Two"), cache.load("en"))
    }

    @Test
    fun aDamagedDiskCacheIsIgnored() = runTest {
        File(root, TranslationDiskCache.fileName("en")).apply { parentFile?.mkdirs() }.writeText("{not json")
        assertEquals(emptyMap<String, String>(), disk().load("en"))
    }

    // Long text, a sentence at a time (iOS AppLanguageTests).

    @Test
    fun segmentsKeepTheirPunctuationAndJoinBackExactly() {
        val text = "今日北部普通。明日良好！\n後天？其他；尾巴"
        val segments = OnDeviceTranslation.segments(text)
        assertEquals(listOf("今日北部普通。", "明日良好！", "\n", "後天？", "其他；", "尾巴"), segments)
        assertEquals(text, segments.joinToString(""))
    }

    @Test
    fun leadingSegmentsCoverAboutTheCollapsedLines() {
        val segments = OnDeviceTranslation.segments("一二三四五。六七八九十。十一十二。")
        assertEquals(listOf("一二三四五。"), OnDeviceTranslation.leadingSegments(segments, 1))
        assertEquals(listOf("一二三四五。", "六七八九十。"), OnDeviceTranslation.leadingSegments(segments, 7))
        assertEquals(segments, OnDeviceTranslation.leadingSegments(segments, 1_000))
    }

    @Test
    fun translatedSegmentsAreSwappedInAsTheyLand() {
        val first = "今日北部普通。"
        val second = "明日良好。"
        val segments = listOf(first, second)
        val service = OnDeviceTranslation(FakeTranslator())
        assertEquals(first + second, OnDeviceTranslation.display(segments, "en", service::cached))

        service.store("Moderate today.", first, "en")
        assertEquals("Moderate today. $second", OnDeviceTranslation.display(segments, "en", service::cached))

        service.store("Good tomorrow.", second, "en")
        assertEquals("Moderate today. Good tomorrow.", OnDeviceTranslation.display(segments, "en", service::cached))

        // Chinese: as written.
        assertEquals(first + second, OnDeviceTranslation.display(segments, null, service::cached))
    }

    @Test
    fun aTranslatedLineKeepsItsLineBreak() {
        val line = "標題\n"
        val service = OnDeviceTranslation(FakeTranslator())
        service.store("Title", line, "en")
        assertEquals("Title\nNext", OnDeviceTranslation.display(listOf(line, "Next"), "en", service::cached))
    }
}
