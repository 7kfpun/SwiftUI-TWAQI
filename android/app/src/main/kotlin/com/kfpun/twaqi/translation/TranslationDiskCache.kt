package com.kfpun.twaqi.translation

import com.kfpun.twaqi.data.cache.CacheStore
import com.kfpun.twaqi.data.cache.OfflineCacheRetention
import java.time.Instant
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/**
 * On-device translations kept across launches: one small JSON file per target language under the
 * offline cache root (`translations/zh-Hant-en.json`), so [OfflineCacheRetention.purge] removes it
 * once it has gone a week unwritten.
 *
 * Each entry also carries when it was made and is dropped once it is more than a week old, since
 * the file itself is rewritten with every new translation. At most [maxEntries], newest first.
 */
class TranslationDiskCache(
    private val store: CacheStore,
    private val now: () -> Instant = Instant::now,
    private val maxEntries: Int = MAX_ENTRIES,
    private val io: CoroutineDispatcher = Dispatchers.IO
) {
    private data class Entry(val source: String, val translation: String, val savedAt: Instant)

    /** The saved translations into [target], by original; none when missing or unreadable. */
    suspend fun load(target: String): Map<String, String> = withContext(io) {
        entries(target).associate { it.source to it.translation }
    }

    /** Adds [translations] (by original) into [target] to the file, newest first. */
    suspend fun add(target: String, translations: Map<String, String>) {
        if (translations.isEmpty()) return
        withContext(io) {
            synchronized(this@TranslationDiskCache) {
                val time = now()
                val fresh = translations.map { (source, translation) -> Entry(source, translation, time) }
                val kept = entries(target).filter { it.source !in translations }
                write(target, (fresh + kept).take(maxEntries))
            }
        }
    }

    private fun entries(target: String): List<Entry> {
        val text = store.read(fileName(target))?.value ?: return emptyList()
        val root = runCatching { Json.parseToJsonElement(text) as? JsonObject }.getOrNull() ?: return emptyList()
        val time = now()
        return (root["entries"] as? JsonArray).orEmpty().mapNotNull { element ->
            val o = element as? JsonObject ?: return@mapNotNull null
            val source = (o["source"] as? JsonPrimitive)?.takeIf { it.isString }?.content
            val translation = (o["translation"] as? JsonPrimitive)?.takeIf { it.isString }?.content
            val savedAt = (o["savedAt"] as? JsonPrimitive)?.longOrNull?.let(Instant::ofEpochSecond)
            if (source == null || translation.isNullOrEmpty() || OfflineCacheRetention.isExpired(savedAt, time)) {
                null
            } else {
                Entry(source, translation, savedAt!!)
            }
        }
    }

    private fun write(target: String, entries: List<Entry>) {
        val root = buildJsonObject {
            put(
                "entries",
                buildJsonArray {
                    entries.forEach { entry ->
                        add(
                            buildJsonObject {
                                put("source", entry.source)
                                put("translation", entry.translation)
                                put("savedAt", entry.savedAt.epochSecond)
                            }
                        )
                    }
                }
            )
        }
        store.write(fileName(target), root.toString())
    }

    companion object {
        const val DIRECTORY_NAME = "translations"
        const val MAX_ENTRIES = 500

        fun fileName(target: String) = "$DIRECTORY_NAME/${OnDeviceTranslation.SOURCE_LANGUAGE}-$target.json"
    }
}
