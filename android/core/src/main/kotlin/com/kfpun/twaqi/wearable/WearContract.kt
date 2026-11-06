package com.kfpun.twaqi.wearable

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull

/**
 * What the phone app and the Wear OS app send each other over the Wearable Data Layer (FOX-62),
 * the Android side of iOS WatchConnectivity (`PhoneRelay`, `WatchEventRelay`). The Data Layer
 * only connects apps with the same application id (`com.kfpun.twaqi`) and signing key.
 *
 * Every payload is one JSON string under [KEY_PAYLOAD], so both sides read it with plain Kotlin
 * that the unit tests cover.
 */
object WearContract {
    /** The phone's [PhoneState]: one data item, replaced whenever it changes. */
    const val PHONE_STATE_PATH = "/twaqi/phone-state"

    /**
     * Locked-complication hits from the watch ([LockedComplicationPayload]), one data item per
     * batch under this path. The Data Layer keeps an item until the phone has it, so a batch sent
     * while the phone is away arrives later (iOS `transferUserInfo`). The phone logs and deletes it.
     */
    const val WATCH_EVENTS_PATH = "/twaqi/watch-events"

    const val KEY_PAYLOAD = "payload"

    internal val json = Json { ignoreUnknownKeys = true }

    internal fun parseObject(text: String?): JsonObject? =
        text?.let { runCatching { json.parseToJsonElement(it) }.getOrNull() } as? JsonObject
}

/**
 * The phone's state the watch follows.
 *
 * @property favouriteStationIds the reader's favourites, in their order (`FavouritesRepository`).
 * @property isPro FOX-58's `ProRepository.isPro`, or null while the phone hasn't read it yet; the
 *   watch keeps its last answer then.
 * @property languageId the app language's id (`AppLanguage.id`: `system`, `zh-Hant`, `en`, FOX-56).
 */
data class PhoneState(val favouriteStationIds: List<Int>, val isPro: Boolean?, val languageId: String) {
    fun encode(): String = JsonObject(
        buildMap {
            put(FAVOURITES, JsonArray(favouriteStationIds.map(::JsonPrimitive)))
            isPro?.let { put(IS_PRO, JsonPrimitive(it)) }
            put(LANGUAGE, JsonPrimitive(languageId))
        }
    ).toString()

    companion object {
        private const val FAVOURITES = "favouriteStationIds"
        private const val IS_PRO = "isPro"
        private const val LANGUAGE = "language"

        /** Null when [text] isn't a phone state; unreadable favourites are dropped one by one. */
        fun decode(text: String?): PhoneState? {
            val root = WearContract.parseObject(text) ?: return null
            val favourites = (root[FAVOURITES] as? JsonArray)
                ?.mapNotNull { (it as? JsonPrimitive)?.intOrNull }
                ?.distinct()
                .orEmpty()
            return PhoneState(
                favouriteStationIds = favourites,
                isPro = (root[IS_PRO] as? JsonPrimitive)?.booleanOrNull,
                languageId = (root[LANGUAGE] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: SYSTEM_LANGUAGE
            )
        }

        /** `AppLanguage.SYSTEM.id`: follow the device's own language. */
        const val SYSTEM_LANGUAGE = "system"
    }
}

/**
 * A free reader's complication set to a Pro style, so it shows the lock (iOS FOX-63). Logged on
 * the phone as `watch_complication_locked` (FOX-44), since only the phone has Firebase.
 *
 * @property style `ComplicationStyle` id (`labelled`, `numberOnly`, `face`, `status`).
 * @property family the complication type, e.g. `SHORT_TEXT` (iOS: the WidgetKit family).
 * @property index the index id (`aqi`, `pm25`, …).
 */
data class LockedComplicationHit(val style: String, val family: String, val index: String) {
    /** The Firebase event's parameters. Nothing personal: no station, no place. */
    val parameters: Map<String, String> get() = mapOf("style" to style, "family" to family, "index" to index)
}

/** The watch-events payload (iOS `LockedComplicationLog.userInfo(for:)` / `hits(fromUserInfo:)`). */
object LockedComplicationPayload {
    /** The key both sides agree on, as iOS `LockedComplicationLog.userInfoKey`. */
    const val KEY = "watchComplicationLocked"

    fun encode(hits: List<LockedComplicationHit>): String = JsonObject(
        mapOf(
            KEY to JsonArray(
                hits.map { hit -> JsonObject(hit.parameters.mapValues { (_, value) -> JsonPrimitive(value) }) }
            )
        )
    ).toString()

    /** Hits in a payload from [encode]; anything else, and incomplete entries, are ignored. */
    fun decode(text: String?): List<LockedComplicationHit> {
        val entries = WearContract.parseObject(text)?.get(KEY) as? JsonArray ?: return emptyList()
        return entries.mapNotNull { entry ->
            val fields = entry as? JsonObject ?: return@mapNotNull null
            val style = fields.string("style") ?: return@mapNotNull null
            val family = fields.string("family") ?: return@mapNotNull null
            val index = fields.string("index") ?: return@mapNotNull null
            LockedComplicationHit(style, family, index)
        }
    }

    private fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
}
