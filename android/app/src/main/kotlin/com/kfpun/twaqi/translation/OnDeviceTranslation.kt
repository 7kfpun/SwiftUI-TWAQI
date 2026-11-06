package com.kfpun.twaqi.translation

import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Puts Chinese-only free text from the API (MOENV's area forecast text) into English on the device
 * (iOS `OnDeviceTranslation`), through a [Translator] (ML Kit in the app, a fake in tests).
 *
 * Only the forecast text goes through it; day names, statuses and pollutants are ordinary
 * localized strings. CWA's weather text is never translated (FOX-93 shows it in Chinese only).
 * Place names never are either (FOX-114): machine translation garbled them (新店區 became "New
 * store area", 八德路四段 "paragraph 4, Baide Road"), so a station's township and county come from
 * `TaiwanPlaceNames` and its street address shows as written.
 * Chinese UIs get the original. Anywhere translation can't happen (model not downloaded, offline,
 * any error) the original Chinese is shown, with no error and no label saying it was translated.
 *
 * Translations are kept in memory ([translations], which the UI observes) and on disk under the
 * offline cache root ([TranslationDiskCache]), so a screen reopened or a later launch does not
 * translate again.
 */
class OnDeviceTranslation(private val translator: Translator, private val disk: TranslationDiskCache? = null) {
    private val state = MutableStateFlow<Map<String, String>>(emptyMap())

    /** Every translation made or loaded so far, by [key]. Compose reads it to redraw when one lands. */
    val translations: StateFlow<Map<String, String>> = state.asStateFlow()

    /** Targets whose disk cache has been read into memory. */
    private val loaded: MutableSet<String> = ConcurrentHashMap.newKeySet()
    private val mutex = Mutex()

    fun cached(text: String, target: String): String? = state.value[key(text, target)]

    fun store(translation: String, text: String, target: String) {
        state.update { it + (key(text, target) to translation) }
    }

    /**
     * Drops every translation held in memory, e.g. when the language changes (iOS clears its cache
     * in `SettingsStore.appLanguage`). The disk copy stays; it is keyed by target language.
     */
    fun clearCache() {
        state.value = emptyMap()
        loaded.clear()
    }

    /**
     * Translates whichever of [texts] are worth it and not yet cached into [target], and caches the
     * results. Does nothing when [target] is null (a Chinese UI). Never throws: a failure leaves
     * the originals showing.
     */
    suspend fun translate(texts: List<String>, target: String?) {
        if (target == null) return
        val worth = translatable(texts)
        if (worth.isEmpty()) return
        mutex.withLock {
            loadFromDisk(target)
            val missing = worth.filter { cached(it, target) == null }
            if (missing.isEmpty()) return
            val results = try {
                translator.translate(missing, target)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                emptyMap()
            }
            val made = missing.mapNotNull { text ->
                results[text]?.trim()?.takeIf { it.isNotEmpty() }?.let { text to it }
            }.toMap()
            if (made.isEmpty()) return
            state.update { current -> current + made.map { (text, translation) -> key(text, target) to translation } }
            disk?.add(target, made)
        }
    }

    private suspend fun loadFromDisk(target: String) {
        if (!loaded.add(target)) return
        val saved = disk?.load(target).orEmpty()
        if (saved.isEmpty()) return
        // Anything translated meanwhile wins over the disk copy.
        state.update { current -> saved.mapKeys { key(it.key, target) } + current }
    }

    companion object {
        /** The API writes Traditional Chinese. */
        const val SOURCE_LANGUAGE = "zh-Hant"

        /** The only language translated into: the app's other language (FOX-56 ships en and zh-Hant). */
        const val ENGLISH = "en"

        /**
         * The language to translate into, or null when the original should show. Chinese reads the
         * API as written; every other locale gets the app's English strings, so English text too.
         * Follows the language chosen under Help (`AppLocale`).
         */
        fun target(chinese: Boolean): String? = if (chinese) null else ENGLISH

        internal fun key(text: String, target: String): String = "$target\u001F$text"

        /** Only text with Chinese in it is worth sending; anything else is shown as is. */
        fun needsTranslation(text: String): Boolean = text.codePoints().anyMatch(Character::isIdeographic)

        /** The texts worth sending, once each, in order. */
        fun translatable(texts: List<String>): List<String> = texts.filter(::needsTranslation).distinct()

        /** What to show for [text] now: the cached translation into [target], else the original. */
        fun display(text: String, target: String?, cached: (text: String, target: String) -> String?): String {
            if (target == null || !needsTranslation(text)) return text
            return cached(text, target) ?: text
        }

        /**
         * MOENV's forecast text in the order iOS shows it: the Worker's translation
         * ([workerTranslation], `content_i18n`) when there is one, else the on-device translation a
         * sentence at a time as far as it has got, else the original.
         */
        fun forecastText(
            content: String,
            workerTranslation: String?,
            target: String?,
            cached: (text: String, target: String) -> String?
        ): String = workerTranslation ?: display(segments(content), target, cached)

        // Long text, a sentence at a time.

        private val enders = setOf('。', '！', '？', '；', '\n')

        /**
         * Sentence-sized pieces of [text], each keeping its closing punctuation, so the first few
         * can be translated before the rest. Joined back together they are exactly [text].
         */
        fun segments(text: String): List<String> {
            val pieces = mutableListOf<String>()
            val current = StringBuilder()
            for (character in text) {
                current.append(character)
                if (character in enders) {
                    pieces += current.toString()
                    current.clear()
                }
            }
            if (current.isNotEmpty()) pieces += current.toString()
            return pieces
        }

        /**
         * The leading [segments] that fill about [characters] characters of the original, always at
         * least one: enough to cover what the collapsed lines show, so the first glance is
         * translated first.
         */
        fun leadingSegments(segments: List<String>, characters: Int): List<String> {
            val taken = mutableListOf<String>()
            var count = 0
            for (segment in segments) {
                taken += segment
                count += segment.length
                if (count >= characters) break
            }
            return taken
        }

        /**
         * [segments] with each translated one swapped in, joined back up. A space goes between
         * pieces once either side is a translation (English sentences need one; Chinese ones run
         * together).
         */
        fun display(
            segments: List<String>,
            target: String?,
            cached: (text: String, target: String) -> String?
        ): String {
            val result = StringBuilder()
            var previousTranslated = false
            for (segment in segments) {
                val shown = display(segment, target, cached)
                val translated = shown != segment
                if (result.isNotEmpty() && (translated || previousTranslated) &&
                    !result.last().isWhitespace() && shown.isNotEmpty() && !shown.first().isWhitespace()
                ) {
                    result.append(' ')
                }
                if (translated) {
                    // Keep the original's line break, if it ended with one.
                    result.append(shown.trim())
                    result.append(segment.takeLastWhile(Char::isWhitespace))
                } else {
                    result.append(shown)
                }
                previousTranslated = translated
            }
            return result.toString()
        }
    }
}
